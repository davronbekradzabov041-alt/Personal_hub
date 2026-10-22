/// Тесты автоустановки встроенных модулей (Stage 11).
///
/// Главный сценарий: сбой `onEnable` у ОДНОГО модуля не должен
/// останавливать установку остальных и ронять запуск приложения.
/// Проверяются также корректность состояний, откат и то, что
/// успешное включение по-прежнему работает.
library builtin_module_installer_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/builtin_module_installer.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_permission.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_provider.dart';
import 'package:personal_hub/core/search/search_result.dart';

// --- Тестовые doubles ---

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

class _FakeModuleStorage implements ModuleStorage {
  _FakeModuleStorage(this._bucket);
  final Map<String, String> _bucket;

  @override
  Future<String?> getString(String key) async => _bucket[key];

  @override
  Future<void> setString(String key, String value) async {
    _bucket[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _bucket.remove(key);
  }

  @override
  Future<List<String>> keys() async => _bucket.keys.toList();
}

ModuleManifest _manifest(String id) => ModuleManifest.fromJson(<String, dynamic>{
      'id': id,
      'name': 'Модуль $id',
      'version': '1.0.0',
      'apiVersion': kCoreModuleApiVersion,
      'author': 'Test',
    });

/// Модуль, который молча живёт: ничего не делает в хуках.
class _GoodModule extends Module {
  _GoodModule(String id) : _m = _manifest(id);
  final ModuleManifest _m;

  @override
  ModuleManifest get manifest => _m;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  int get order => 10;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

/// Модуль, который падает в onEnable — «сломанный проверочный».
class _BrokenEnableModule extends Module {
  _BrokenEnableModule(String id) : _m = _manifest(id);
  final ModuleManifest _m;

  @override
  ModuleManifest get manifest => _m;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  int get order => 20;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onEnable(ModuleApi api) async {
    throw ModuleLifecycleError(id, 'onEnable сломан намеренно');
  }
}

/// Модуль, который падает в onInstall.
class _BrokenInstallModule extends Module {
  _BrokenInstallModule(String id) : _m = _manifest(id);
  final ModuleManifest _m;

  @override
  ModuleManifest get manifest => _m;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  int get order => 30;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {
    throw StateError('onInstall сломан намеренно');
  }
}

/// Модуль, регистрирующий SearchProvider: проверяет, что onEnable
/// реально дорабатывает до конца и провайдер доступен.
///
/// Разрешение [ModulePermission.coreSearch] обязательно: без него
/// `api.registerSearchProvider()` бросает ModuleLifecycleError — ровно
/// тот путь, который и проверяется в соседних тестах со сбоем.
class _SearchingModule extends Module {
  _SearchingModule(String id)
      : _m = ModuleManifest.fromJson(<String, dynamic>{
          'id': id,
          'name': 'Модуль $id',
          'version': '1.0.0',
          'apiVersion': kCoreModuleApiVersion,
          'author': 'Test',
          'permissions': [ModulePermission.coreSearch.id],
        });
  final ModuleManifest _m;

  @override
  ModuleManifest get manifest => _m;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  int get order => 40;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onEnable(ModuleApi api) async {
    api.registerSearchProvider(_NoopProvider());
  }

  @override
  Future<void> onDisable(ModuleApi api) async {
    // Провайдер снимается через api в тесте; здесь проверяем только
    // что хук вызывается и не мешает установке.
  }
}

class _NoopProvider implements SearchProvider {
  @override
  Future<List<SearchResult>> search(String query) async => const [];
}

void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _FakeModuleStateStore store;

  setUp(() {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
    final buckets = <String, Map<String, String>>{};
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: (moduleId) =>
          _FakeModuleStorage(buckets.putIfAbsent(moduleId, () => {})),
    );
    store = _FakeModuleStateStore();
  });

  tearDown(ModuleRegistry.clear);

  group('Успешная установка', () {
    test('все модули доходят до enabled и попадают в installed',
        () async {
      ModuleRegistry.registerAll([
        _GoodModule('good1'),
        _GoodModule('good2'),
        _SearchingModule('searching'),
      ]);

      final report =
          await ensureBuiltinModulesInstalled(manager, store);

      expect(report.hasFailures, isFalse);
      expect(report.installed, containsAll(['good1', 'good2', 'searching']));
      expect(report.failed, isEmpty);
      expect(manager.stateOf('good1'), ModuleState.enabled);
      expect(manager.stateOf('good2'), ModuleState.enabled);
      expect(manager.stateOf('searching'), ModuleState.enabled);
    });

    test('хук onEnable отрабатывает: SearchProvider зарегистрирован',
        () async {
      ModuleRegistry.register(_SearchingModule('searching'));
      expect(searchService.providerCount, 0);

      await ensureBuiltinModulesInstalled(manager, store);

      expect(searchService.providerCount, 1);
    });

    test('уже известный модуль не устанавливается повторно', () async {
      ModuleRegistry.register(_GoodModule('good1'));
      // Состояние уже сохранено — как после предыдущего запуска.
      await store.save(ModuleStateSnapshot(
        moduleId: 'good1',
        state: 'enabled',
        installedVersion: '1.0.0',
        enabled: true,
        installedAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));

      final report =
          await ensureBuiltinModulesInstalled(manager, store);

      expect(report.installed, isEmpty);
      expect(report.failed, isEmpty);
      expect(manager.stateOf('good1'), null,
          reason: 'setUp не восстанавливает состояния — store.load '
              'говорит «уже был», и install не вызывается');
    });
  });

  group('Сбой одного модуля не роняет остальные', () {
    test('onEnable падает: модуль в failed, остальные установлены', () async {
      ModuleRegistry.registerAll([
        _GoodModule('good1'),
        _BrokenEnableModule('broken'),
        _GoodModule('good2'),
      ]);

      // Не бросает — и это главное утверждение теста.
      final report =
          await ensureBuiltinModulesInstalled(manager, store);

      expect(report.failed, ['broken']);
      expect(report.installed, containsAll(['good1', 'good2']));
      expect(manager.stateOf('good1'), ModuleState.enabled);
      expect(manager.stateOf('good2'), ModuleState.enabled);
    });

    test('onEnable падает: состояние откатывается, не остаётся enabled',
        () async {
      ModuleRegistry.register(_BrokenEnableModule('broken'));

      await ensureBuiltinModulesInstalled(manager, store);

      // ModuleManager вызывает хук ДО мутации состояния, поэтому
      // неудачный enable не оставляет ложного enabled.
      expect(manager.stateOf('broken'), ModuleState.installed);
    });

    test('onInstall падает: модуль в failed, остальные работают', () async {
      ModuleRegistry.registerAll([
        _BrokenInstallModule('brokenInstall'),
        _GoodModule('good1'),
      ]);

      final report =
          await ensureBuiltinModulesInstalled(manager, store);

      expect(report.failed, ['brokenInstall']);
      expect(report.installed, ['good1']);
      expect(manager.stateOf('good1'), ModuleState.enabled);
      // tryInstall откатывает состояние неудачной установки.
      expect(manager.stateOf('brokenInstall'), null);
    });

    test('сбойное включение не мешает повторному включению вручную',
        () async {
      ModuleRegistry.register(_BrokenEnableModule('broken'));

      final report =
          await ensureBuiltinModulesInstalled(manager, store);
      expect(report.failed, ['broken']);

      // Пользователь жмёт «Включить» на странице «Модули» — модуль
      // обязан снова попытаться (и снова честно упасть), а не
      // застрять в недоступном состоянии.
      await expectLater(
        manager.enable('broken'),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('broken'), ModuleState.installed);
    });

    test('несколько сбоев собираются в один отчёт', () async {
      ModuleRegistry.registerAll([
        _BrokenEnableModule('brokenA'),
        _GoodModule('good1'),
        _BrokenInstallModule('brokenB'),
        _BrokenEnableModule('brokenC'),
      ]);

      final report =
          await ensureBuiltinModulesInstalled(manager, store);

      expect(report.failed, containsAll(['brokenA', 'brokenB', 'brokenC']));
      expect(report.installed, ['good1']);
      expect(manager.stateOf('good1'), ModuleState.enabled);
    });
  });

  group('Пустой реестр', () {
    test('возвращает пустой отчёт', () async {
      final report =
          await ensureBuiltinModulesInstalled(manager, store);
      expect(report.isEmpty, isTrue);
      expect(report.hasFailures, isFalse);
    });
  });
}
