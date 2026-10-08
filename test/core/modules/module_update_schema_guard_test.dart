/// Path A обновления и схема данных (Этап 9.1).
///
/// ## Почему отдельный файл
///
/// `ModuleManager.update()` — короткий путь подмены манифеста из
/// доверенного каталога Module Store. Он не проходит через
/// `ModuleImporter.updateFromBytes`, а значит не имеет ни снимка, ни
/// обмена песочницы, ни отката.
///
/// На Этапе 9.1 ни один путь обновления не переносит данные. Для
/// полного пути это пока безопасно (он и так всё делает правильно, а
/// перенос появится в Этапах 9.3–9.4), но для Path A оставить
/// `schemaVersion` без проверки означало бы тихую порчу данных:
/// код сменяется, форма данных — нет.
///
/// ## Что проверяется
///
/// 1. смена `schemaVersion` через Path A отклоняется ДО обмена реестра;
/// 2. отказ машинно-читаем (код нарушения), а не текстом;
/// 3. смена версии кода при той же схеме по-прежнему разрешена —
///    иначе проверка запрещала бы обычное обновление;
/// 4. реестр после отказа остаётся прежним, данные не тронуты;
/// 5. `_apiCache` сбрасывается после успешного обмена.
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
import 'package:personal_hub/core/modules/module_update_validator.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_provider.dart';
import 'package:personal_hub/core/search/search_result.dart';

/// Хранилище в памяти, считающее записи: обновление не имеет права
/// ничего писать — ни в успешном случае, ни в отказном.
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

  group('Path A: смена схемы данных отклоняется', () {
    test('обновление с другим schemaVersion отклонено', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      expect((await manager.tryInstall('notes')).isSuccess, isTrue);
      storage.reset();

      await expectLater(
        manager.update(ExternalModuleAdapter(_manifest('1.1.0',
            schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'Path A не переносит данные: смена схемы здесь означала бы '
            'новый код поверх данных в старой форме',
      );
    });

    test('отказ не трогает реестр — старая версия осталась на месте', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      storage.reset();

      await expectLater(
        manager.update(
            ExternalModuleAdapter(_manifest('2.0.0', schemaVersion: 5))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.0.0');
      expect(ModuleRegistry.get('notes')!.manifest.schemaVersion, 1);
      expect(manager.stateOf('notes'), ModuleState.installed,
          reason: 'отказ проверок не должен менять состояние модуля');
    });

    test('отказ не пишет в хранилище', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      await storage.setString('event:1', '{"id":"1"}');
      final before = Map<String, String>.from(storage.data);
      storage.reset();

      await expectLater(
        manager.update(
            ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      expect(storage.setCalls, 0);
      expect(storage.removeCalls, 0);
      expect(storage.data, before);
    });

    test('понижение схемы тоже отклоняется', () async {
      // Откат формы данных опаснее прямого обновления: старые данные
      // не заменяются, они просто перестают соответствовать коду.
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(
          ExternalModuleAdapter(_manifest('1.2.0', schemaVersion: 3)));
      await manager.tryInstall('notes');

      await expectLater(
        manager.update(
            ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 1))),
        throwsA(isA<ModuleLifecycleError>()),
      );
    });
  });

  group('Path A: смена версии кода при той же схеме разрешена', () {
    test('обычное обновление продолжает работать', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      expect((await manager.tryInstall('notes')).isSuccess, isTrue);

      await manager.update(
          ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 1)));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.1.0');
      expect(manager.stateOf('notes'), ModuleState.installed);
    });

    test('обновление с той же схемой не пишет в хранилище', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      await storage.setString('event:1', '{"id":"1"}');
      storage.reset();

      await manager.update(
          ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 1)));

      expect(storage.setCalls, 0,
          reason: 'обновление кода не трогает данные пользователя');
      expect(storage.removeCalls, 0);
    });
  });

  group('Валидатор: нарушение машинно-читаемо', () {
    test('код dataSchemaVersionChanged появляется в плане', () {
      // UI обязан решать по коду, а не разбирать русский текст (см.
      // ModuleUpdatePlan): иначе правка формулировки тихо ломает экран.
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0', schemaVersion: 2),
        currentManifest: _manifest('1.0.0'),
      );

      expect(plan.isAccepted, isFalse);
      expect(
        plan.violations.map((v) => v.code),
        contains(ModuleUpdateViolationCode.dataSchemaVersionChanged),
      );
    });

    test('схема без изменений нарушения не даёт', () {
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0'),
        currentManifest: _manifest('1.0.0'),
      );

      expect(plan.isAccepted, isTrue);
      expect(plan.fromVersion!.toString(), '1.0.0');
      expect(plan.toVersion!.toString(), '1.1.0');
    });

    test('нарушение перечислено вместе с прочими, а не вместо них', () {
      // Отказов бывает несколько сразу; показывать их по одному за
      // попытку пользователю нельзя.
      final plan = ModuleUpdateValidator().validate(
        newManifest: _manifest('1.1.0', schemaVersion: 2),
        currentManifest: _manifest('1.0.0'),
        currentState: ModuleState.uninstalled,
      );

      expect(plan.isAccepted, isFalse);
      expect(
        plan.violations.map((v) => v.code),
        containsAll(<ModuleUpdateViolationCode>[
          ModuleUpdateViolationCode.dataSchemaVersionChanged,
          ModuleUpdateViolationCode.moduleNotInstalled,
        ]),
      );
    });
  });

  group('_apiCache сбрасывается после обмена', () {
    test('API после обмена — другой объект', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');

      final before = manager.apiFor('notes');
      await manager.update(
          ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 1)));
      final after = manager.apiFor('notes');

      // Раньше кэш навсегда удерживал _ModuleApiImpl, созданный для
      // ПРЕЖНЕГО Module, и проверка разрешений смотрела на манифест
      // старой версии.
      expect(identical(before, after), isFalse,
          reason: 'кэш обязан быть сброшен: он удерживал старую версию');
    });

    test('добавленное новой версией разрешение действует сразу', () async {
      // Самый наглядный признак устаревшего кэша: модуль, которому
      // новая версия добавила core:search, не смог бы им
      // воспользоваться, пока кэш смотрит в старый манифест.
      final search = GlobalSearchService();
      final manager = ModuleManager(
        searchService: search,
        storageFactory: (_) => storage,
      );
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');

      // 1.0.0 разрешения не имеет.
      expect(
        () => manager.apiFor('notes').registerSearchProvider(_NoopProvider()),
        throwsA(isA<ModuleLifecycleError>()),
      );

      await manager.update(ExternalModuleAdapter(
        _manifestWithPermission('1.1.0'),
      ));

      // Теперь действуют права НОВОГО манифеста.
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
          ExternalModuleAdapter(_manifestWithPermission('1.0.0')));
      await manager.tryInstall('notes');
      manager.apiFor('notes').registerSearchProvider(_NoopProvider());
      expect(search.providerCount, 1);

      // 1.1.0 разрешение убирает.
      await manager.update(ExternalModuleAdapter(_manifest('1.1.0')));

      expect(
        () => manager.apiFor('notes').registerSearchProvider(_NoopProvider()),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'кэш со старым манифестом выдал бы разрешение, которого '
            'у новой версии уже нет',
      );
    });

    test('отказ по схеме кэш НЕ сбрасывает', () async {
      // Иначе неудачное обновление уничтожило бы работающий API
      // модуля, который в реестре остался прежним.
      final manager = buildManager();
      addTearDown(manager.dispose);

      ModuleRegistry.register(ExternalModuleAdapter(_manifest('1.0.0')));
      await manager.tryInstall('notes');
      final before = manager.apiFor('notes');

      await expectLater(
        manager.update(
            ExternalModuleAdapter(_manifest('1.1.0', schemaVersion: 2))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      expect(identical(manager.apiFor('notes'), before), isTrue);
    });
  });
}

/// Манифест с разрешением на поиск — версия, которая его либо имеет,
/// либо нет.
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
