import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
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

/// AUD-47: импорт .phm в UI обязан доходить до записи состояния.
///
/// Кнопки Module Store проходят через `runModuleAction` →
/// `ModuleStatePersistence.runAndFlush` — та гарантия, которую ввёл
/// AUD-08. Импорт .phm — это тоже изменение состояния модулей
/// (регистрация + установка), но он шёл мимо этой гарантии: SnackBar
/// «успешно импортирован» показывался до записи `ModuleStateRecord`,
/// и немедленное завершение процесса теряло результат импорта.
///
/// Проверяем здесь не «был ли вызван flush», а наблюдаемый факт:
/// в момент, когда SnackBar об успехе уже на экране, запись
/// обязана лежать в хранилище. Иначе пользователь, увидевший
/// «успешно», правомерно считать импорт завершённым.
class _StubFilePicker extends FilePicker {
  _StubFilePicker(this._bytes);

  final Uint8List _bytes;

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
        name: 'imported.phm',
        size: _bytes.length,
        bytes: _bytes,
      ),
    ]);
  }
}

/// Импорт пишет на диск (sandbox, assets), а `testWidgets` работает в
/// fake-async зоне, где реальный I/O никогда не завершается: обработчик
/// нажатия навсегда зависал бы на первом же await, и импорт выглядел бы
/// как «модуль не установился». `tester.runAsync` временно отдаёт
/// управление настоящему event loop, поэтому нажатие и ожидание
/// выполняются внутри него.
///
/// Ожидание — по СИГНАЛУ ЗАВЕРШЕНИЯ, а не по времени. Раньше здесь стоял
/// `Future.delayed(500ms)`: тест проходил ровно тогда, когда дисковое I/O
/// укладывалось в полсекунды — на медленной машине падал без причины, а
/// при быстром импорте 500ms были лишними. Теперь используются
/// существующие контракты боевого кода:
///
/// * успех — запись в ModuleStateStore дошла до конца
///   ([_RecordingStore.saveFinished]) плюс `ModuleStatePersistence.flush()`;
/// * отказ — ошибка записи дошла до `onError` того же persistence
///   ([writeFailed]).
///
/// Оба сигнала приходят от production-кода, поэтому тест падает, если
/// убрать синхронизацию: без `runAndFlush` успешный SnackBar появляется
/// ДО того, как запись завершится (первый тест это и проверяет).
Future<void> _importViaUi(
  WidgetTester tester, {
  required ModuleStatePersistence persistence,
  required Future<void> done,
}) async {
  await tester.runAsync(() async {
    await tester.tap(find.byTooltip('Импорт модуля'));
    await done;
    await persistence.flush();
  });
}

/// Ждёт сигнала записи, не нажимая кнопку повторно: применяется, когда
/// нажатие уже состоялось, а запись была придержана барьером.
Future<void> _awaitWrite(
  WidgetTester tester, {
  required ModuleStatePersistence persistence,
  required Future<void> done,
}) async {
  await tester.runAsync(() async {
    await done;
    await persistence.flush();
  });
}

/// Доводит UI до наблюдаемого состояния, не ожидая времени.
///
/// Импорт состоит из цепочки настоящих файловых операций, и каждая
/// следующая начинается только после того, как event loop разобрал
/// завершение предыдущей. Поэтому одного «пустого» `runAsync` мало:
/// за один настоящий такет продвигается один шаг цепочки. Шаг здесь
/// сделан реальной операцией ФС ([_realTurn]) — она возвращает
/// управление event loop'у так же гарантированно, как и опрос
/// состояния, но не ждёт ни миллисекунд.
///
/// Условие выхода — найден ожидаемый элемент, а не «прошло N тактов»:
/// обычно цепочка укладывается в несколько шагов, а лимит [maxTurns] —
/// только страховка от бесконечного ожидания при поломке.
Future<void> _settle(
  WidgetTester tester,
  Finder finder, {
  int maxTurns = 64,
}) async {
  for (var turn = 0; turn < maxTurns; turn++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(_realTurn);
    await tester.pump();
  }
}

/// Один настоящий такет event loop.
Future<void> _realTurn() => Directory.systemTemp.stat();

/// Ждёт появления элемента, качая настоящий event loop и кадры.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await _settle(tester, finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ModuleManager manager;
  late _RecordingStore store;
  late ModuleStatePersistence persistence;
  late Completer<void> writeFailed;
  late Directory supportDir;
  late List<int> phmBytes;

  setUp(() async {
    ModuleRegistry.clear();
    supportDir = await Directory.systemTemp.createTemp('phm_aud47_');

    // sandbox импортера строится через getApplicationDocumentsDirectory
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => supportDir.path,
    );

    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _InMemoryStorage(),
    );
    store = _RecordingStore();
    // Ошибка записи приходит в onError — это сигнал завершения для
    // неуспешного пути.
    writeFailed = Completer<void>();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: (_) => _InMemoryStorage(),
      onError: (Object _, StackTrace __) {
        if (!writeFailed.isCompleted) writeFailed.complete();
      },
    );

    phmBytes = _buildPhm(id: 'imported', name: 'Импортированный');

    // FilePicker заглушаем: он отдаёт подготовленный .phm.
    // Регистрируем свою заглушку (см. _StubFilePicker) — на уровне
    // платформенного интерфейса, а не MethodChannel: на desktop
    // плагин использует JSONMethodCodec, который декодирует байты в
    // List<dynamic>, а PlatformFile.fromMap требует Uint8List.
    FilePicker.platform = _StubFilePicker(Uint8List.fromList(phmBytes));
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
      await supportDir.delete(recursive: true);
    } catch (_) {
      // временный каталог мог быть уже удалён импортёром
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

  testWidgets('AUD-47: импорт доводится до записи состояния до отчёта об успехе',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Запись состояния НЕ завершится, пока тест её не отпустит.
    // Если бы UI не ждал запись (то есть без runAndFlush), успешный
    // SnackBar показался бы уже сейчас — и проверка это поймала бы.
    store.blockSaves();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Импорт модуля'));
      await store.saveEntered.future; // запись началась и висит на барьере
    });
    // Даём UI возможность продвинуться до конца: без runAndFlush
    // успешный SnackBar показался бы здесь — запись ещё висит, а отчёт
    // об успехе уже на экране. С runAndFlush он не появится никогда,
    // пока запись не завершена.
    await _settle(tester, find.textContaining('успешно импортирован'));

    expect(
      find.textContaining('успешно импортирован'),
      findsNothing,
      reason: 'успех нельзя показывать, пока состояние не записано',
    );
    expect(store.saveCount, 1, reason: 'запись была начата, но не завершена');
    expect(
      (await store.loadAll()).where((s) => s.moduleId == 'imported'),
      isEmpty,
      reason: 'незавершённая запись не должна считаться выполненной',
    );

    // Отпускаем запись и дожидаемся её завершения — снова по сигналу.
    store.releaseSaves();
    await _awaitWrite(
      tester,
      persistence: persistence,
      done: store.saveFinished.future,
    );
    await _pumpUntilFound(tester, find.textContaining('успешно импортирован'));

    // Импорт завершён.
    expect(manager.stateOf('imported'), ModuleState.installed);
    expect(find.textContaining('успешно импортирован'), findsWidgets);

    // Состояние записано — ровно одна запись, без дублей и хвоста.
    // Без runAndFlush запись была бы ещё в фоновой очереди, и
    // немедленное завершение процесса её теряло бы.
    expect(store.saveCount, 1);
    expect(persistence.syncCount, 1);
    expect(persistence.lastError, isNull);

    // Записанное состояние соответствует состоянию в памяти.
    final snapshots = await store.loadAll();
    final imported = snapshots.firstWhere(
      (s) => s.moduleId == 'imported',
      orElse: () =>
          throw StateError('состояние imported отсутствует в хранилище'),
    );
    expect(imported.state, 'installed');
  });

  testWidgets('AUD-47: сбой записи состояния при импорте показывается пользователю',
      (tester) async {
    store.failSaves = true;

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _importViaUi(tester, persistence: persistence, done: writeFailed.future);
    await _pumpUntilFound(tester, find.textContaining('не сохранено'));

    // Пользователь не должен увидеть ложное «успешно».
    expect(find.textContaining('успешно импортирован'), findsNothing,
        reason: 'незаписанное состояние нельзя подтверждать как успех');
    expect(find.textContaining('не сохранено'), findsWidgets,
        reason: 'пользователь обязан увидеть причину отказа');
    expect(persistence.lastError, isNotNull);
    expect(persistence.errorCount, greaterThan(0));
  });
}

/// Хранилище состояния: пишет в память, умеет упасть по требованию,
/// считает реальные записи (а не вызовы) и даёт тесту сигналы о ходе
/// записи вместо ожидания по времени.
class _RecordingStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};
  bool failSaves = false;
  int saveCount = 0;

  /// Пока не отпущен через [releaseSaves], запись висит на этом барьере.
  /// Моделирует «запись ещё не завершена» — без всякой задержки.
  final Completer<void> _gate = Completer<void>();
  bool _gated = false;

  /// Запись началась: тест может убедиться, что UI её ЖДЁТ.
  final Completer<void> saveEntered = Completer<void>();

  /// Первая запись успешно завершилась.
  final Completer<void> saveFinished = Completer<void>();

  void blockSaves() => _gated = true;

  void releaseSaves() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    saveCount++;
    if (!saveEntered.isCompleted) saveEntered.complete();
    if (_gated) await _gate.future;
    if (failSaves) {
      throw StateError('хранилище недоступно');
    }
    _data[snapshot.moduleId] = snapshot;
    if (!saveFinished.isCompleted) saveFinished.complete();
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

class _InMemoryStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}

/// Собирает валидный .phm production-writer'ом (не тестовым ZIP-хелпером),
/// чтобы фикстура не зависела от корректности самодельной сборки архива.
List<int> _buildPhm({required String id, required String name}) {
  final manifestJson = jsonEncode(<String, dynamic>{
    'id': id,
    'name': name,
    'version': '1.0.0',
    'apiVersion': 1,
    'author': 'Test',
    'description': 'AUD-47 fixture',
    'permissions': <String>[],
    'dependencies': <String>[],
    'icon': '',
  });

  return ModulePackageWriter.write(
    PackageContent(
      manifest: _manifestOf(manifestJson),
      readme: '# Импортированный модуль',
    ),
  );
}

ModuleManifest _manifestOf(String manifestJson) {
  return ModuleManifest.fromJson(jsonDecode(manifestJson) as Map<String, dynamic>);
}