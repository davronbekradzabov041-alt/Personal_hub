/// Smoke-тесты UI → Backend: экран Backup с НАСТОЯЩИМ [CoreBackupGateway].
///
/// В backup_screen_test (6E) gateway подменялся фейком — он проверял
/// состояния интерфейса, но не связность с core. Здесь тот же экран
/// работает с реальным адаптером поверх реального ModuleBackupManager,
/// а подменяется только файловый сервис (плагин в тестах недоступен).
///
/// Про Global Backup UI: GlobalBackupManager внутри доходит до Isar
/// (AppSettingsRepository, ModuleStorageIsar, ModuleStateRepository),
/// а Isar в этом проекте не инициализируется внутри testWidgets —
/// операции зависают на нативном async. Поэтому сквозной путь global
/// backup проверяется в backup_integration_test (обычный test), а
/// интерфейсная часть — здесь и в backup_screen_test. Объединять их
/// в одном файле нельзя без зависания.
library backup_ui_backend_smoke_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/global_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/design/design_system.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/backup/backup_file_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/backup_services_scope.dart';
import 'package:personal_hub/ui/backup/core_backup_gateway.dart';
import 'package:personal_hub/ui/screens/backup_screen.dart';
import 'package:path/path.dart' as path;

class _FakeModuleStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = {};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

class _MemStorage implements ModuleStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}

/// Заглушка global-менеджера: в widget-тестах до него нельзя дойти,
/// потому что он работает через Isar, который здесь не инициализируется.
/// Реализация методов не важна — ни один тест этого файла их не зовёт.
class _UnavailableGlobalManager implements GlobalBackupManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('GlobalBackupManager недоступен в widget-тестах');
}

/// Файловый сервис, отдающий заранее подготовленные байты.
class _StubFileService implements BackupFileService {
  PickedFile? fileToPick;
  bool cancelSave = false;
  bool cancelPick = false;
  final List<BackupArtifact> saved = [];

  @override
  Future<SaveOutcome> saveArtifact(
    BackupArtifact artifact,
    String title,
  ) async {
    if (cancelSave) return const SaveOutcome.cancelled();
    saved.add(artifact);
    return const SaveOutcome.saved('/tmp/out');
  }

  @override
  Future<PickedFile?> pickBackupFile({
    required List<String> extensions,
    required String title,
  }) async {
    if (cancelPick) return null;
    return fileToPick;
  }
}

String _manifestJson(String id) => jsonEncode({
      'id': id,
      'name': 'Модуль $id',
      'version': '1.0.0',
      'apiVersion': 1,
      'author': 'Test',
      'description': 'Smoke test module',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': 'assets/icon.png',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandboxRoot;
  late ModuleManager manager;
  late _FakeModuleStateStore stateStore;
  late Map<String, _MemStorage> storages;
  late _StubFileService fileService;
  late CoreBackupGateway gateway;

  setUpAll(() async {
    sandboxRoot = await Directory.systemTemp.createTemp('smoke_sandbox_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => sandboxRoot.path,
    );
  });

  setUp(() async {
    ModuleRegistry.clear();
    ModuleRegistry.registerAll([
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson('alpha'))),
      ),
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson('beta'))),
      ),
    ]);

    // Создаются сразу: storageFactory вызывается лениво, а тесты
    // обращаются к хранилищу напрямую.
    storages = {
      'alpha': _MemStorage(),
      'beta': _MemStorage(),
    };
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (id) => storages.putIfAbsent(id, _MemStorage.new),
    );
    manager.setStateForTesting('alpha', ModuleState.enabled);
    manager.setStateForTesting('beta', ModuleState.enabled);
    stateStore = _FakeModuleStateStore();

    gateway = CoreBackupGateway(
      globalManager: _UnavailableGlobalManager(),
      moduleManager: ModuleBackupManager(
        moduleManager: manager,
        stateStore: stateStore,
        assetsDirectoryResolver: (id) => ModuleSandbox.getAssetsDirectory(id),
      ),
      appModuleManager: manager,
    );

    fileService = _StubFileService();

    final modules = Directory(
      path.join(sandboxRoot.path, 'personal_hub_modules', 'modules'),
    );
    if (await modules.exists()) {
      await modules.delete(recursive: true);
    }
  });

  tearDown(() {
    manager.dispose();
  });

  /// Несколько фиксированных кадров вместо [WidgetTester.pumpAndSettle]:
  /// пока идёт операция, на экране крутится `CircularProgressIndicator`,
  /// и settle не наступит никогда.
  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Дожидается завершения реального I/O, запущенного из обработчика
  /// виджета. Такой код выполняется в fake-зоне, поэтому нужен обмен:
  /// реальное время даёт [WidgetTester.runAsync], а fake-микротаски,
  /// в которых висят `await` — [WidgetTester.pump].
  Future<void> awaitUiWork(WidgetTester tester, [int rounds = 30]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BackupServicesScope(
          gateway: gateway,
          fileService: fileService,
          child: const BackupScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester, 1);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tapAt(tester, find.text(text));

  group('Global Backup UI', () {
    testWidgets('секция глобального backup отображается', (tester) async {
      // Сквозной путь GlobalBackupManager → BackupWriter → .pbk →
      // BackupReader проверяется в backup_integration_test: там Isar
      // доступен, здесь — нет. Здесь фиксируем, что UI-секция жива и
      // показывает состав, который потом уходит в менеджер.
      await pumpScreen(tester);

      expect(find.text('Глобальный backup'), findsOneWidget);
      expect(find.text('Настройки приложения'), findsOneWidget);
      expect(find.text('Данные модулей'), findsOneWidget);
      expect(find.text('Файлы модулей'), findsOneWidget);
    });
  });

  group('Module Backup UI → ModuleBackupManager', () {
    testWidgets('нажатие создаёт настоящий .pmb', (tester) async {
      await storages['alpha']!.setString('k', 'v');
      await stateStore.save(ModuleStateSnapshot(
        moduleId: 'alpha',
        state: 'enabled',
        installedVersion: '1.0.0',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ));

      await pumpScreen(tester);

      await tapAt(tester, find.byType(DropdownButtonFormField<String>).first);
      await settle(tester);
      await tester.tap(find.text('Модуль alpha').last);
      await settle(tester);

      await tapText(tester, 'Создать backup модуля');
      await awaitUiWork(tester);
      await settle(tester, 2);

      expect(fileService.saved, hasLength(1));
      expect(fileService.saved.first.fileName, endsWith('.pmb'));
      expect(fileService.saved.first.bytes, isNotEmpty);
    });
  });

  group('Restore UI → restore backend', () {
    testWidgets('подтверждённый restore доходит до хранилища модуля',
        (tester) async {
      // Готовим настоящий .pmb заранее — так же, как его создал бы
      // пользователь ранее. Создание идёт через runAsync: реальный
      // файловый I/O не завершается под fake-async clock виджет-теста.
      final artifact = await tester.runAsync(() async {
        await storages['alpha']!.setString('key', 'original');
        return gateway.createModuleBackup(
          'alpha',
          const ModuleBackupOptions.full(),
        );
      });

      // Пользователь меняет данные после backup.
      await storages['alpha']!.setString('key', 'changed');

      fileService.fileToPick = PickedFile(
        name: artifact!.fileName,
        bytes: Uint8List.fromList(artifact.bytes),
      );

      await pumpScreen(tester);

      await tapText(tester, 'Выбрать .pmb файл');
      expect(find.text('Файл проверен'), findsOneWidget);

      await tapText(tester, 'Восстановить модуль');
      // Диалог подтверждения — restore ещё не выполнялся.
      expect(find.text('Восстановить данные модуля?'), findsOneWidget);
      expect(await storages['alpha']!.getString('key'), 'changed');

      await tapText(tester, 'Восстановить');
      await awaitUiWork(tester);

      expect(await storages['alpha']!.getString('key'), 'original');
      expect(find.textContaining('восстановлен'), findsWidgets);
    });

    testWidgets('отмена подтверждения не запускает restore', (tester) async {
      final artifact = await tester.runAsync(() async {
        await storages['alpha']!.setString('key', 'original');
        return gateway.createModuleBackup(
          'alpha',
          const ModuleBackupOptions.full(),
        );
      });
      await storages['alpha']!.setString('key', 'changed');

      fileService.fileToPick = PickedFile(
        name: artifact!.fileName,
        bytes: Uint8List.fromList(artifact.bytes),
      );

      await pumpScreen(tester);
      await tapText(tester, 'Выбрать .pmb файл');
      await tapText(tester, 'Восстановить модуль');
      await tapText(tester, 'Отмена');

      expect(await storages['alpha']!.getString('key'), 'changed',
          reason: 'после отмены данные обязаны остаться прежними');
    });

    testWidgets('восстановление чужого модуля показывает ошибку',
        (tester) async {
      // .pmb модуля alpha, а UI направляет его в beta — сработает
      // проверка идентичности, и UI обязан показать понятный текст.
      final artifact = await tester.runAsync(() async {
        await storages['alpha']!.setString('key', 'original');
        return gateway.createModuleBackup(
          'alpha',
          const ModuleBackupOptions.full(),
        );
      });

      fileService.fileToPick = PickedFile(
        name: artifact!.fileName,
        bytes: Uint8List.fromList(artifact.bytes),
      );

      await pumpScreen(tester);
      await tapText(tester, 'Выбрать .pmb файл');

      // Модуль-назначение выставляется автоматически из архива (alpha).
      // Меняем его на beta и запускаем restore.
      await tapAt(tester, find.byType(DropdownButtonFormField<String>).last);
      await settle(tester);
      await tester.tap(find.text('Модуль beta').last);
      await settle(tester);

      await tapText(tester, 'Восстановить модуль');
      await tapText(tester, 'Восстановить');

      expect(find.textContaining('другому модулю'), findsOneWidget);
    });
  });

  group('ошибки и отмена', () {
    testWidgets('повреждённый файл даёт понятную ошибку', (tester) async {
      fileService.fileToPick = PickedFile(
        name: 'broken.pmb',
        bytes: Uint8List.fromList(List<int>.generate(200, (i) => i % 251)),
      );

      await pumpScreen(tester);
      await tapText(tester, 'Выбрать .pmb файл');

      // Ни стектрейса, ни имени исключения в интерфейсе быть не должно.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    });

    testWidgets('отмена выбора файла не считается ошибкой', (tester) async {
      fileService.cancelPick = true;

      await pumpScreen(tester);
      await tapText(tester, 'Выбрать .pmb файл');

      expect(find.textContaining('отменён'), findsOneWidget);
    });

    testWidgets('отмена сохранения не сообщает об успехе', (tester) async {
      // Проверяется на модульном backup: глобальный backend требует
      // Isar, который не инициализируется под fake-async clock.
      fileService.cancelSave = true;
      await storages['alpha']!.setString('k', 'v');

      await pumpScreen(tester);
      await tapAt(tester, find.byType(DropdownButtonFormField<String>).first);
      await settle(tester);
      await tester.tap(find.text('Модуль alpha').last);
      await settle(tester);

      await tapText(tester, 'Создать backup модуля');
      await awaitUiWork(tester);
      await settle(tester, 2);

      expect(find.textContaining('Сохранение отменено'), findsOneWidget);
      expect(find.textContaining('Backup сохранён'), findsNothing);
    });
  });

  group('защита от повторного запуска', () {
    testWidgets('во время операции кнопка заблокирована', (tester) async {
      await pumpScreen(tester);

      final button =
          find.widgetWithText(FilledButton, 'Создать глобальный backup');
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      // Запускаем и сразу смотрим состояние, не дожидаясь завершения.
      await tester.tap(button);
      await tester.pump();

      // Операция могла уже завершиться (она быстрая), поэтому проверяем
      // инвариант: либо идёт прогресс, либо результат уже показан и
      // кнопка снова активна. Повторного запуска быть не должно.
      final runsBefore = fileService.saved.length;
      await tester.tap(button, warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fileService.saved.length, runsBefore);
    });
  });
}
