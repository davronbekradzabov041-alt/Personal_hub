/// Реальный .phm update flow через пользовательский интерфейс (Этап 8.2).
///
/// Обновление из файла — второй вход в механизм обновления модуля, и
/// он обязан вести себя как импорт: тот же PackageReader, тот же
/// security-guard, тот же ManifestValidator и то же требование довести
/// результат до записи состояния (ModuleStatePersistence.runAndFlush).
/// Проверяется наблюдаемыми фактами — версия в ModuleRegistry, версия в
/// записи состояния, содержимое песочницы и данные модуля, — а не тем,
/// какие методы внутри были вызваны.
library module_update_ui_test;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_persistence_scope.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/screens/modules_screen.dart';

const String _moduleId = 'imported';

/// Подменяет FilePicker на уровне платформенного интерфейса: на desktop
/// плагин использует JSONMethodCodec, который декодирует байты в
/// List<dynamic>, а PlatformFile.fromMap требует Uint8List.
///
/// Байты можно заменить между нажатиями — одним и тем же объектом
/// имитируется «пользователь сначала импортировал 1.0.0, потом выбрал
/// файл 1.1.0».
class _StubFilePicker extends FilePicker {
  _StubFilePicker(this.bytes);

  List<int> bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    List<String>? allowedExtensions,
    FileType type = FileType.any,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    int? compressionQuality,
    bool allowCompression = true,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult(<PlatformFile>[
      PlatformFile(
        name: 'module.phm',
        size: bytes.length,
        bytes: Uint8List.fromList(bytes),
      ),
    ]);
  }
}

/// Хранилище состояния в памяти.
class _MemoryStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> snapshots =
      <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => snapshots.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => snapshots[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    snapshots[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    snapshots.remove(moduleId);
  }
}

class _MemoryStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

/// Собирает .phm production-writer'ом, чтобы фикстура не зависела от
/// корректности самодельной сборки архива.
List<int> _phm({
  required String id,
  required String version,
  int apiVersion = 1,
  Map<String, String> assets = const <String, String>{},
  Map<String, String> storage = const <String, String>{},
}) {
  final manifest = ModuleManifest.fromJson(<String, dynamic>{
    'id': id,
    'name': 'Импортированный',
    'version': version,
    'apiVersion': apiVersion,
    'author': 'Test',
    'description': 'AUD-47 fixture',
    'permissions': <String>[],
    'dependencies': <String>[],
    'icon': '',
  });

  return ModulePackageWriter.write(PackageContent(
    manifest: manifest,
    assets: [
      for (final entry in assets.entries)
        PackageAsset(
          path: 'assets/${entry.key}',
          bytes: utf8.encode(entry.value),
        ),
    ],
    data: storage.isEmpty
        ? null
        : PackageData(jsonDecode(jsonEncode(storage)) as Map<String, dynamic>),
  ));
}

/// Один настоящий такет event loop: возвращает управление так же
/// гарантированно, как опрос состояния, но не ждёт миллисекунд.
Future<void> _realTurn() => Directory.systemTemp.stat();

/// Доводит UI до наблюдаемого состояния, не ожидая времени.
///
/// Импорт и обновление — цепочки настоящих файловых операций, и каждая
/// следующая начинается только после того, как event loop разобрал
/// завершение предыдущей. Условие выхода — найден ожидаемый элемент;
/// лимит тактов — только страховка от бесконечного ожидания.
Future<bool> _settle(
  WidgetTester tester,
  Finder finder, {
  int maxTurns = 96,
}) async {
  for (var turn = 0; turn < maxTurns; turn++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.runAsync(_realTurn);
    await tester.pump();
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDir;
  late ModuleManager manager;
  late _MemoryStore stateStore;
  late ModuleStatePersistence persistence;
  late _StubFilePicker picker;

  setUp(() async {
    ModuleRegistry.clear();
    documentsDir = await Directory.systemTemp.createTemp('phm_update_ui_');

    // Песочница модулей и её обмен идут через path_provider — мок
    // обслуживает боевой резолвер ModuleSandboxSwap.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => documentsDir.path,
    );

    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _MemoryStorage(),
    );
    stateStore = _MemoryStore();
    persistence = ModuleStatePersistence(
      manager,
      stateStore,
      storageFactory: (_) => _MemoryStorage(),
    );
    picker = _StubFilePicker([]);
    FilePicker.platform = picker;
  });

  tearDown(() async {
    persistence.dispose();
    ModuleRegistry.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      await documentsDir.delete(recursive: true);
    } catch (_) {
      // каталог мог быть уже удалён
    }
  });

  Widget app() {
    return ModuleStatePersistenceScope(
      persistence: persistence,
      child: ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(home: ModulesScreen()),
      ),
    );
  }

/// Нажатие действия экрана и ожидание его завершения.
///
/// Импорт и обновление пишут на диск (песочница, ассеты), а
/// `testWidgets` работает в fake-async зоне, где реальный I/O не
/// завершается: обработчик нажатия завис бы на первом же await.
/// `tester.runAsync` временно отдаёт управление настоящему event loop.
///
/// [message] — часть сообщения SnackBar'а, по которой видно, что
/// действие ЗАВЕРШИЛОСЬ (успехом или отказом). Ожидание по тексту, а не
/// по времени: иначе тест проходил бы ровно тогда, когда дисковое I/O
/// укладывается в заданный срок.
Future<void> tapAndWait(
  WidgetTester tester,
  String tooltip,
  String message,
) async {
  await tester.runAsync(() => tester.tap(find.byTooltip(tooltip)));
  final shown = await _settle(tester, find.textContaining(message));
  await tester.runAsync(() => persistence.flush());

  // SnackBar прячется сам через несколько секунд, но его таймер живёт в
  // ТОМ таймере, в котором действие было запущено, а действие идёт в
  // реальном event loop (`tester.runAsync`) — значит, прокрутка времени
  // виджета его не сократит. Пока сообщение на экране, следующее
  // сообщение стоит в очереди ScaffoldMessenger и не появляется. Поэтому
  // предыдущее убирается явно: так же, как оно ушло бы у пользователя.
  final messenger = tester.state<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  );
  messenger.clearSnackBars();
  await tester.pumpAndSettle();

  expect(shown, isTrue, reason: 'пользователь должен увидеть «$message». '
      'На экране: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
}

  Directory assetsDir() => Directory(
        path.join(
          documentsDir.path,
          'personal_hub_modules',
          'modules',
          _moduleId,
          'assets',
        ),
      );

  Map<String, String> readAssets() {
    final dir = assetsDir();
    if (!dir.existsSync()) return const {};
    return {
      for (final entity in dir.listSync())
        if (entity is File)
          path.basename(entity.path): entity.readAsStringSync(),
    };
  }

  /// Импортирует 1.0.0 и кладёт в модуль пользовательские данные.
  Future<void> installBaseline(WidgetTester tester) async {
    picker.bytes = _phm(
      id: _moduleId,
      version: '1.0.0',
      assets: {'logo.png': 'старая иконка'},
    );
    await tapAndWait(tester, 'Импорт модуля', 'успешно импортирован');
    expect(manager.stateOf(_moduleId), ModuleState.installed);

    final storage = manager.apiFor(_moduleId).storage;
    await storage.setString('note:1', 'черновик пользователя');
  }

  testWidgets('импорт 1.0.0, затем обновление из файла 1.1.0', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    final storage = manager.apiFor(_moduleId).storage;
    picker.bytes = _phm(
      id: _moduleId,
      version: '1.1.0',
      assets: {'logo.png': 'новая иконка', 'data.json': '{}'},
      storage: {'note:1': 'текст из нового пакета'},
    );

    await tapAndWait(tester, 'Обновить модуль из файла', 'обновлён');

    // Пользователь видит подтверждение именно обновления.

    // Версия в реестре — новая.
    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
    expect(manager.stateOf(_moduleId), ModuleState.installed);

    // Содержимое песочницы заменено содержимым новой версии.
    expect(readAssets(), {'logo.png': 'новая иконка', 'data.json': '{}'});

    // Данные пользователя целы: обновление не переносит и не затирает
    // хранилище, даже когда пакет принёс свой ключ с тем же именем.
    expect(await storage.getString('note:1'), 'черновик пользователя');

    // Версия записана в состояние модуля ДО подтверждения успеха:
    // иначе перезапуск вернул бы прежнюю версию.
    expect(stateStore.snapshots[_moduleId]!.installedVersion, '1.1.0');
    expect(stateStore.snapshots[_moduleId]!.state, 'installed');
  });

  testWidgets('повторное обновление того же файла отклоняется', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    picker.bytes = _phm(id: _moduleId, version: '1.1.0');
    await tapAndWait(tester, 'Обновить модуль из файла', 'обновлён');
    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');

    // Тот же файл второй раз: версия не изменилась — отказ.
    await tapAndWait(tester, 'Обновить модуль из файла', 'Ошибка обновления');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0',
        reason: 'отказ не должен менять версию');
    expect(manager.stateOf(_moduleId), ModuleState.installed);
  });

  testWidgets('обновление неустановленного модуля отказ, а не установка',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    picker.bytes = _phm(id: 'never-installed', version: '1.0.0');

    await tapAndWait(tester, 'Обновить модуль из файла', 'Ошибка обновления');

    expect(ModuleRegistry.contains('never-installed'), isFalse,
        reason: 'обновление не имеет права установить модуль');
    expect(manager.stateOf('never-installed'), isNull);
  });

  testWidgets('откат версии отклоняется с кодом и без побочных эффектов',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    picker.bytes = _phm(id: _moduleId, version: '0.9.0');
    await tapAndWait(tester, 'Обновить модуль из файла', 'Ошибка обновления');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    expect(readAssets(), {'logo.png': 'старая иконка'});
    expect(
      await manager.apiFor(_moduleId).storage.getString('note:1'),
      'черновик пользователя',
    );
    expect(stateStore.snapshots[_moduleId]!.installedVersion, '1.0.0');
  });

  testWidgets('несовместимый apiVersion отклоняется тем же валидатором',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    picker.bytes = _phm(id: _moduleId, version: '1.1.0', apiVersion: 99);
    await tapAndWait(tester, 'Обновить модуль из файла', 'Ошибка обновления');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    expect(readAssets(), {'logo.png': 'старая иконка'});
  });

  testWidgets('битый архив не проходит security-guard', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    // Не ZIP вовсе: security-guard обязан отбить его ДО разбора, иначе
    // недоверенные байты дойдут до парсера манифеста.
    picker.bytes = List<int>.filled(64, 0x41);

    await tapAndWait(tester, 'Обновить модуль из файла', 'Ошибка обновления');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    expect(readAssets(), {'logo.png': 'старая иконка'});
  });

  testWidgets('выключенный модуль обновляется и остаётся выключенным',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    await tester.runAsync(() => manager.enable(_moduleId));
    await tester.runAsync(() => manager.disable(_moduleId));
    await tester.runAsync(() => persistence.flush());
    expect(manager.stateOf(_moduleId), ModuleState.disabled);

    picker.bytes = _phm(id: _moduleId, version: '1.1.0');
    await tapAndWait(tester, 'Обновить модуль из файла', 'обновлён');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
    expect(manager.stateOf(_moduleId), ModuleState.disabled,
        reason: 'обновление не включает и не выключает модуль');
    expect(stateStore.snapshots[_moduleId]!.state, 'disabled');
  });

  testWidgets('включённый модуль обновляется и остаётся включённым',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await installBaseline(tester);

    await tester.runAsync(() => manager.enable(_moduleId));
    await tester.runAsync(() => persistence.flush());
    expect(manager.stateOf(_moduleId), ModuleState.enabled);

    picker.bytes = _phm(id: _moduleId, version: '1.1.0');
    await tapAndWait(tester, 'Обновить модуль из файла', 'обновлён');

    expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
    expect(manager.stateOf(_moduleId), ModuleState.enabled);
    expect(stateStore.snapshots[_moduleId]!.state, 'enabled');
    expect(stateStore.snapshots[_moduleId]!.installedVersion, '1.1.0');
  });
}
