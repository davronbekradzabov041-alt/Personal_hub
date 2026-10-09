/// Path A обновления и схема данных (Этап 9.6).
///
/// На Этапе 9.3–9.4 миграция данных была реализована: ModuleManager.update
/// и ModuleImporter.updateFromBytes теперь запускают миграцию через
/// ModuleMigrationRunner после swap реестра. Валидатор больше НЕ отклоняет
/// смену schemaVersion — он пропускает обновление, а Runner решает,
/// можно ли выполнить миграцию (и если нет — откат реестра и ошибка).
///
/// Что проверяется:
/// 1. Валидатор принимает смену schemaVersion (нет нарушения dataSchemaVersionChanged).
/// 2. Обновление с другой схемой проходит валидацию, но если миграции нет —
///    Runner бросает migrationMissing, реестр откатывается.
/// 3. Обновление с той же схемой по-прежнему разрешено и не пишет в хранилище.
/// 4. Реестр после неудачной миграции остаётся прежним, данные не тронуты.
/// 5. _apiCache сбрасывается после успешного обмена, при неудаче миграции
///    реестр откатывается и кэш пересоздаётся для старой версии.
library module_update_schema_guard_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_permission.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/module_update_plan.dart';
import 'package:personal_hub/core/modules/module_data_migration.dart';
import 'package:personal_hub/core/modules/module_update_validator.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_provider.dart';
import 'package:personal_hub/core/search/search_result.dart';

/// Хранилище в памяти, считающее записи.
class _CountingStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};
  int setCalls = 0;
  int removeCalls = 0;

  void reset() {
    setCalls = 0;
    removeCalls = 0;
  }

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    setCalls++;
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    removeCalls++;
    data.remove(key);
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

ModuleManifest _manifest(String version, {int schemaVersion = 1}) {
  return ModuleManifest.fromJson(<String, dynamic>{
    'id': 'notes',
    'name': 'Заметки',
    'version': version,
    'apiVersion': 1,
    'author': 'Test',
    'schemaVersion': schemaVersion,
  });
}

/// Внешний модуль БЕЗ миграций — для тестов, где миграция должна НЕ найтись.
class _ModuleNoMigrations extends ExternalModuleAdapter {
  _ModuleNoMigrations(super.manifest);

  @override
  List<ModuleDataMigration> get dataMigrations => const <ModuleDataMigration>[];
}

/// Внешний модуль С миграцией 1->2 — для тестов успешной миграции.
class _ModuleWithMigration extends ExternalModuleAdapter {
  _ModuleWithMigration(super.manifest);

  @override
  List<ModuleDataMigration> get dataMigrations =>
      <ModuleDataMigration>[_TestMigration()];
}

class _TestMigration implements ModuleDataMigration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Future<void> run(ModuleStorage storage) async {
    await storage.setString('migrated', 'true');
  }
}

void main() {
  late _CountingStorage storage;

  setUp(() {
    ModuleRegistry.clear();
    storage = _CountingStorage();
  });

  tearDown(ModuleRegistry.clear);

  ModuleManager buildManager() => ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => storage,
      );

  group('Валидатор: смена schemaVersion принимается', () {
    test('валидатор не выдаёт dataSchemaVersionChanged', () {
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0', schemaVersion: 2),
        currentManifest: _manifest('1.0.0'),
      );

      expect(plan.isAccepted, isTrue);
      expect(
        plan.violations.map((v) => v.code),
        isNot(contains(ModuleUpdateViolationCode.dataSchemaVersionChanged)),
      );
    });

    test('схема без изменений — нарушений нет', () {
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0'),
        currentManifest: _manifest('1.0.0'),
      );

      expect(plan.isAccepted, isTrue);
    });

    test('другие нарушения (uninstalled) всё равно ловятся', () {
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0', schemaVersion: 2),
        currentManifest: _manifest('1.0.0'),
        currentState: ModuleState.uninstalled,
      );

      expect(plan.isAccepted, isFalse);
      expect(
        plan.violations.map((v) => v.code),
        contains(ModuleUpdateViolationCode.moduleNotInstalled),
      );
      expect(
        plan.violations.map((v) => v.code),
        isNot(contains(ModuleUpdateViolationCode.dataSchemaVersionChanged)),
      );
    });
  });

  group('Path A: обновление с другой схемой — миграция через Runner', () {
    test('модуль БЕЗ миграций: обновление падает с migrationMissing, реестр откат', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      storage.reset();

      await expectLater(
        manager.update(_ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'миграции нет — Runner бросает migrationMissing',
      );

      // Реестр откатился к старой версии
      expect(ModuleRegistry.get('notes')!.manifest.version, '1.0.0');
      expect(ModuleRegistry.get('notes')!.manifest.schemaVersion, 1);
      expect(manager.stateOf('notes'), ModuleState.installed,
          reason: 'состояние модуля не меняется');
    });

    test('модуль БЕЗ миграций: при неудаче миграции хранилище не тронуто', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      await storage.setString('event:1', '{"id":"1"}');
      final before = Map<String, String>.from(storage.data);
      storage.reset();

      await expectLater(
        manager.update(_ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      // Хранилище не изменилось (миграция не запускалась, маркер не записан)
      expect(storage.setCalls, 0);
      expect(storage.removeCalls, 0);
      expect(storage.data, before);
    });

    test('модуль С миграцией 1->2: обновление успешно, маркер записан', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleWithMigration(_manifest('1.0.0', schemaVersion: 1)));
      await manager.tryInstall('notes');
      storage.reset();

      await manager.update(_ModuleWithMigration(_manifest('1.1.0', schemaVersion: 2)));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.1.0');
      expect(ModuleRegistry.get('notes')!.manifest.schemaVersion, 2);
      expect(manager.stateOf('notes'), ModuleState.installed);
      // Миграция записала маркер и данные
      expect(storage.setCalls, greaterThan(0));
      expect(storage.data['migrated'], 'true');
    });

    test('понижение схемы: Runner отклоняет (dataSchemaIncompatible)', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleWithMigration(_manifest('1.2.0', schemaVersion: 3)));
      await manager.tryInstall('notes');
      storage.reset();

      await expectLater(
        manager.update(_ModuleWithMigration(_manifest('1.1.0', schemaVersion: 1))),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'обратный перенос не поддерживается',
      );

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.2.0');
      expect(ModuleRegistry.get('notes')!.manifest.schemaVersion, 3);
    });
  });

  group('Path A: смена версии кода при той же схеме', () {
    test('обычное обновление продолжает работать', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      expect((await manager.tryInstall('notes')).isSuccess, isTrue);

      await manager.update(_ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 1)));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.1.0');
      expect(manager.stateOf('notes'), ModuleState.installed);
    });

    test('обновление с той же схемой не пишет в хранилище', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      await storage.setString('event:1', '{"id":"1"}');
      storage.reset();

      await manager.update(_ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 1)));

      expect(storage.setCalls, 0,
          reason: 'обновление кода не трогает данные пользователя');
      expect(storage.removeCalls, 0);
    });
  });

  group('_apiCache сбрасывается после обмена', () {
    test('API после обмена — другой объект', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');

      final before = manager.apiFor('notes');
      await manager.update(
          _ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 1)));
      final after = manager.apiFor('notes');

      expect(identical(before, after), isFalse,
          reason: 'кэш обязан быть сброшен: он удерживал старую версию');
    });

    test('добавленное новой версией разрешение действует сразу', () async {
      final search = GlobalSearchService();
      final manager = ModuleManager(
        searchService: search,
        storageFactory: (_) => storage,
      );
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');

      expect(
        () => manager.apiFor('notes').registerSearchProvider(_NoopProvider()),
        throwsA(isA<ModuleLifecycleError>()),
      );

      await manager.update(_ModuleNoMigrations(
        _manifestWithPermission('1.1.0'),
      ));

      manager.apiFor('notes').registerSearchProvider(_NoopProvider());
      expect(search.providerCount, 1);
    });

    test('отозванное новой версией разрешение перестаёт действовать', () async {
      final search = GlobalSearchService();
      final manager = ModuleManager(
        searchService: search,
        storageFactory: (_) => storage,
      );
      addTearDown(manager.dispose);

      ModuleRegistry.register(
          _ModuleNoMigrations(_manifestWithPermission('1.0.0')));
      await manager.tryInstall('notes');
      manager.apiFor('notes').registerSearchProvider(_NoopProvider());
      expect(search.providerCount, 1);

      await manager.update(_ModuleNoMigrations(_manifest('1.1.0')));

      expect(
        () => manager.apiFor('notes').registerSearchProvider(_NoopProvider()),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'кэш со старым манифестом выдал бы разрешение, которого '
            'у новой версии уже нет',
      );
    });

    test('при неудаче миграции реестр откатывается, кэш пересоздаётся для старой версии', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(_ModuleNoMigrations(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      final before = manager.apiFor('notes');

      await expectLater(
        manager.update(_ModuleNoMigrations(_manifest('1.1.0', schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      // Реестр откатился, кэш пересоздан для старой версии (НОВЫЙ объект)
      expect(identical(manager.apiFor('notes'), before), isFalse,
          reason: 'после отката миграции кэш очищается и создаётся заново для старой версии');
    });
  });
}

ModuleManifest _manifestWithPermission(String version) {
  return ModuleManifest.fromJson(<String, dynamic>{
    'id': 'notes',
    'name': 'Заметки',
    'version': version,
    'apiVersion': 1,
    'author': 'Test',
    'permissions': [ModulePermission.coreSearch.id],
  });
}

class _NoopProvider implements SearchProvider {
  @override
  Future<List<SearchResult>> search(String query) async => const [];
}