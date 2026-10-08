import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_restorer.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/builtin_module_installer.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

/// Минимальный тестовый модуль — не завязан на Isar/Flutter-виджеты,
/// buildPage не проверяется этими тестами.
class _FakeModule extends Module {
  _FakeModule(this._manifest);
  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

/// Модуль, у которого onEnable() падает. Используется регрессией
/// восстановления: install() проходит, а включение — нет.
class _FailingEnableModule extends Module {
  _FailingEnableModule(this._manifest);

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onEnable(ModuleApi api) async {
    throw StateError('onEnable не удалось');
  }
}

/// Фейковая in-memory реализация ModuleStateStore — заменяет Isar,
/// которого в этой среде нет возможности прогнать через кодогенерацию.
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

/// Фейковая фабрика ModuleStorage — один общий backing-map на moduleId,
/// доступный тесту напрямую, чтобы проверить, что uninstall действительно
/// стирает данные модуля (а не только запись состояния).
class _FakeModuleStorageFactory {
  final Map<String, Map<String, String>> buckets = {};

  ModuleStorage call(String moduleId) {
    final bucket = buckets.putIfAbsent(moduleId, () => {});
    return _FakeModuleStorage(bucket);
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

/// ModuleStatePersistence реагирует на notifyListeners() асинхронно,
/// поэтому перед проверкой состояния хранилища дожидаемся завершения
/// фоновой записи через flush(). Раньше здесь был
/// `Future.delayed(Duration.zero)`, который не доказывает ничего: он
/// отдаёт управление event loop'у ровно один раз и никак не связан с
/// завершением самой записи.
void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _FakeModuleStateStore store;
  late _FakeModuleStorageFactory storageFactory;
  late ModuleStatePersistence persistence;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(_FakeModule(const ModuleManifest(
      id: 'demo',
      name: 'Demo',
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    )));

    searchService = GlobalSearchService();
    storageFactory = _FakeModuleStorageFactory();
    store = _FakeModuleStateStore();
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: storageFactory.call,
    );
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: storageFactory.call,
    );
  });

  tearDown(() {
    persistence.dispose();
    ModuleRegistry.clear();
  });

  test('install → сохраняется', () async {
    await manager.install('demo');
    await persistence.flush();

    final saved = await store.load('demo');
    expect(saved, isNotNull);
    expect(saved!.state, 'installed');
    expect(saved.enabled, isFalse);
  });

  test('enable → сохраняется', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    final saved = await store.load('demo');
    expect(saved!.state, 'enabled');
    expect(saved.enabled, isTrue);
  });

  test('disable → сохраняется', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await manager.disable('demo');
    await persistence.flush();

    final saved = await store.load('demo');
    expect(saved!.state, 'disabled');
    expect(saved.enabled, isFalse);
  });

  test('uninstall → запись остаётся (tombstone), данные удаляются', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await storageFactory.call('demo').setString('note', 'hello');
    await manager.disable('demo');
    await manager.uninstall('demo');
    await persistence.flush();

    final saved = await store.load('demo');
    expect(saved, isNotNull);
    expect(saved!.state, 'uninstalled');
    expect(saved.enabled, isFalse);
    expect(storageFactory.buckets['demo'], isEmpty);
  });

  test('restart → состояние восстанавливается', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    // "Перезапуск": новый ModuleManager поверх того же хранилища —
    // как при холодном старте приложения (main.dart создаёт менеджер
    // заново на каждый запуск, состояние переживает только в Isar).
    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: storageFactory.call,
    );
    await ModuleStateRestorer(freshManager, store).restore();

    expect(freshManager.stateOf('demo'), ModuleState.enabled);
  });

  test('restart → disabled модуль восстанавливается как disabled', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await manager.disable('demo');
    await persistence.flush();

    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: storageFactory.call,
    );
    await ModuleStateRestorer(freshManager, store).restore();

    expect(freshManager.stateOf('demo'), ModuleState.disabled);
  });

  // --- Регрессия: сбой onEnable() при восстановлении не понижает
  // сохранённое намерение «включён» до «установлен, но выключен».

  test('сбой onEnable() при restore не теряет сохранённое «включён»', () async {
    const manifest = ModuleManifest(
      id: 'demo',
      name: 'Demo',
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    );

    // Первый запуск: модуль установлен и включён, намерение записано.
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();
    expect((await store.load('demo'))!.enabled, isTrue);

    // Холодный старт: в реестре уже другой модуль того же id, и его
    // onEnable() падает. install() проходит, enable() — нет.
    ModuleRegistry.clear();
    ModuleRegistry.register(_FailingEnableModule(manifest));

    final fakeStorageFactory = (String moduleId) => storageFactory.call(moduleId);

    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: fakeStorageFactory,
    );
    final freshPersistence = ModuleStatePersistence(freshManager, store);
    await ModuleStateRestorer(freshManager, store).restore();
    await freshPersistence.flush();

    // Сохранённое намерение не понижено.
    final after = await store.load('demo');
    expect(after, isNotNull);
    expect(after!.state, 'enabled');
    expect(after.enabled, isTrue);

    freshPersistence.dispose();
  });

  test('сбой onEnable() при restore: модуль не объявлен включённым, '
      'ошибка наблюдаема, следующий запуск повторяет попытку', () async {
    const manifest = ModuleManifest(
      id: 'demo',
      name: 'Demo',
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    );

    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    ModuleRegistry.clear();
    ModuleRegistry.register(_FailingEnableModule(manifest));

    // Явно создаём функцию-фабрику, чтобы избежать проблем с tear-off.
    final fakeStorageFactory = (String moduleId) => storageFactory.call(moduleId);

    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: fakeStorageFactory,
    );
    final freshPersistence = ModuleStatePersistence(freshManager, store);
    final reported = <ModuleRestoreException>[];
    final restorer = ModuleStateRestorer(
      freshManager,
      store,
      onError: (error, _) => reported.add(error as ModuleRestoreException),
    );

    // Ровно тот порядок, что в main.dart на холодном старте.
    await freshPersistence.runRestoreTransaction(restorer.restore);
    await freshPersistence.flush();

    // Намерение сохранено.
    final after = await store.load('demo');
    expect(after!.state, 'enabled');
    expect(after.enabled, isTrue);

    // Модуль не объявлен включённым: хук упал, активности нет.
    expect(freshManager.stateOf('demo'), ModuleState.installed);
    expect(freshManager.isEnabled('demo'), isFalse);

    // Сбой виден вызывающему, а не проглочен.
    expect(restorer.failedCount, 1);
    expect(reported, hasLength(1));
    expect(reported.single.moduleId, 'demo');

    freshPersistence.dispose();

    // Следующий запуск: модуль починили — включение повторяется.
    ModuleRegistry.clear();
    ModuleRegistry.register(_FakeModule(manifest));

    final fakeStorageFactory2 = (String moduleId) => storageFactory.call(moduleId);

    final nextManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: fakeStorageFactory2,
    );
    final nextPersistence = ModuleStatePersistence(nextManager, store);
    await nextPersistence.runRestoreTransaction(
      () => ModuleStateRestorer(nextManager, store).restore(),
    );
    await nextPersistence.flush();

    expect(nextManager.stateOf('demo'), ModuleState.enabled);
    expect((await store.load('demo'))!.enabled, isTrue);
    nextPersistence.dispose();
  });

  test('успешный restore сохраняет сохранённое «включён»', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    final fakeStorageFactory = (String moduleId) => storageFactory.call(moduleId);

    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: fakeStorageFactory,
    );
    final freshPersistence = ModuleStatePersistence(freshManager, store);
    await freshPersistence.runRestoreTransaction(
      () => ModuleStateRestorer(freshManager, store).restore(),
    );
    await freshPersistence.flush();

    expect(freshManager.stateOf('demo'), ModuleState.enabled);
    final after = await store.load('demo');
    expect(after!.state, 'enabled');
    expect(after.enabled, isTrue);
    freshPersistence.dispose();
  });

  // Bug #6 regression tests
  test('builtin module uninstall + restart → НЕ переустанавливается', () async {
    // Ensure builtin module is installed
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    // User uninstalls the builtin module
    await manager.disable('demo');
    await manager.uninstall('demo');
    await persistence.flush();

    // Verify tombstone exists in store
    final tombstone = await store.load('demo');
    expect(tombstone, isNotNull);
    expect(tombstone!.state, 'uninstalled');
    expect(tombstone.enabled, isFalse);

    // Cold start: new ModuleManager + restore + ensureBuiltinModulesInstalled
    final freshManager = ModuleManager(searchService: GlobalSearchService());
    await ModuleStateRestorer(freshManager, store).restore();
    await ensureBuiltinModulesInstalled(freshManager, store);

    // Module should NOT be auto-reinstalled (stateOf is null because
    // fresh manager never installed it; the tombstone prevents reinstall)
    // It should NOT be installed or enabled
    expect(freshManager.stateOf('demo'), isNot(ModuleState.installed));
    expect(freshManager.stateOf('demo'), isNot(ModuleState.enabled));
  });

  test('builtin module disable + restart → остаётся disabled', () async {
    // Ensure builtin module is installed and disabled
    await manager.install('demo');
    await manager.enable('demo');
    await manager.disable('demo');
    await persistence.flush();

    // Cold start: new ModuleManager + restore + ensureBuiltinModulesInstalled
    final fakeStorageFactory = (String moduleId) => storageFactory.call(moduleId);

    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: fakeStorageFactory,
    );
    await ModuleStateRestorer(freshManager, store).restore();
    await ensureBuiltinModulesInstalled(freshManager, store);

    // Module should remain disabled, not auto-enabled
    expect(freshManager.stateOf('demo'), ModuleState.disabled);
  });

  test('AUD-03: внешний модуль не переживает рестарт (текущий контракт)', () async {
    // Документирует ограничение, а не желаемое поведение.
    //
    // Контракт текущего кода: внешний .phm нужно импортировать заново.
    // Причина структурная — ModuleImporter кладёт в постоянную песочницу
    // только assets/ и README.md, а manifest.json туда не попадает.
    // Значит, после рестарта нечего собрать в ExternalModuleAdapter, и
    // ModuleManager.install() бросает: модуля нет в ModuleRegistry.
    // Запись состояния в Isar при этом остаётся, и повторный импорт
    // её подхватывает.
    await manager.install('demo');
    await manager.enable('demo');
    await persistence.flush();

    // "Перезапуск": реестр модулей пуст, состояние живёт только в store.
    ModuleRegistry.clear();
    final freshManager = ModuleManager(searchService: GlobalSearchService());
    await ModuleStateRestorer(freshManager, store).restore();

    expect(
      freshManager.stateOf('demo'),
      isNull,
      reason: 'без зарегистрированного модуля install() падает, restorer это переживает',
    );
    expect(
      (await store.load('demo'))!.state,
      'enabled',
      reason: 'состояние сохраняется и остаётся ждать повторного импорта',
    );
  });

  group('serialized writes (AUD-08 regression)', () {
    late _SlowFirstSaveStore slowStore;
    late ModuleStatePersistence slowPersistence;

    setUp(() {
      slowStore = _SlowFirstSaveStore();
      slowPersistence = ModuleStatePersistence(
        manager,
        slowStore,
        storageFactory: storageFactory.call,
      );
    });

    tearDown(() {
      slowPersistence.dispose();
    });

    test('быстрые изменения состояния → сохраняется последнее', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await manager.disable('demo');
      await slowPersistence.flush();

      final saved = await slowStore.load('demo');
      expect(saved!.state, 'disabled');
      expect(saved.enabled, isFalse);
      // Записи идут строго в порядке уведомлений: первая — install,
      // последняя — итоговое состояние. Промежуточный 'enabled' может
      // отсутствовать: _sync() по контракту пишет ТЕКУЩЕЕ состояние
      // модуля, а не снимок на момент уведомления.
      expect(slowStore.saveOrder.first, 'installed');
      expect(slowStore.saveOrder.last, 'disabled');
      expect(manager.stateOf('demo'), ModuleState.disabled);
    });

    test('install → enable не теряет enabled при медленной первой записи', () async {
      // Первая запись намеренно медленная: при несериализованных
      // fire-and-forget _sync() она завершалась ПОЗЖЕ второй и
      // затирала её, оставляя устаревшее состояние.
      await manager.install('demo');
      await manager.enable('demo');
      await slowPersistence.flush();

      final saved = await slowStore.load('demo');
      expect(saved!.state, 'enabled');
      expect(saved.enabled, isTrue);
    });

    test('uninstall → flush → reload даёт tombstone', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await storageFactory.call('demo').setString('note', 'hello');
      await slowPersistence.flush();

      await manager.disable('demo');
      await manager.uninstall('demo');
      await slowPersistence.flush();

      final saved = await slowStore.load('demo');
      expect(saved, isNotNull);
      expect(saved!.state, 'uninstalled');
      expect(saved.enabled, isFalse);
      expect(storageFactory.buckets['demo'], isEmpty);
    });

    test('tombstone не затирается более поздним снимком', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await slowPersistence.flush();
      await manager.disable('demo');
      await manager.uninstall('demo');
      await slowPersistence.flush();

      expect(slowStore.saveOrder.last, 'uninstalled');
      expect((await slowStore.load('demo'))!.state, 'uninstalled');
    });

    test('disable → flush → reload фиксирует disabled', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await slowPersistence.flush();

      await manager.disable('demo');
      await slowPersistence.flush();

      final fakeStorageFactory = (String moduleId) => storageFactory.call(moduleId);

      final freshManager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: fakeStorageFactory,
      );
      await ModuleStateRestorer(freshManager, slowStore).restore();
      expect(freshManager.stateOf('demo'), ModuleState.disabled);
    });

    test('ошибка записи не теряется и не ломает очередь', () async {
      final errors = <Object>[];
      final persistenceWithHandler = ModuleStatePersistence(
        manager,
        slowStore,
        storageFactory: storageFactory.call,
        onError: (error, _) => errors.add(error),
      );
      addTearDown(persistenceWithHandler.dispose);

      slowStore.failNextSave = true;
      await manager.install('demo');
      await persistenceWithHandler.flush();

      expect(errors, isNotEmpty, reason: 'ошибка не должна теряться');
      expect(persistenceWithHandler.lastError, isNotNull);

      // Следующая запись всё ещё выполняется: сбой одной не ломает хвост.
      await manager.enable('demo');
      await persistenceWithHandler.flush();
      expect((await slowStore.load('demo'))!.state, 'enabled');
    });

    test('flush дожидается записей, поставленных во время ожидания', () async {
      await manager.install('demo');

      // flush() запущен, но ещё не завершён: следующая операция
      // попадает в очередь уже после его вызова.
      final flushed = slowPersistence.flush();
      await manager.enable('demo');
      await flushed;

      expect(
        (await slowStore.load('demo'))!.state,
        'enabled',
        reason: 'flush() обязан дождаться записей, добавленных после его вызова',
      );
    });
  });

  group('runAndFlush: операция завершена только после записи (AUD-08)',
      () {
    late _GatedStore store;
    late ModuleStatePersistence persistence;

    setUp(() async {
      store = _GatedStore();
      persistence = ModuleStatePersistence(
        manager,
        store,
        storageFactory: storageFactory.call,
      );
    });

    tearDown(() {
      persistence.dispose();
    });

    /// Запускает операцию, не ожидая её, и возвращает её Future.
    Future<void> startCritical(Future<void> Function() operation) {
      final future = persistence.runAndFlush(operation);
      unawaited(future);
      return future;
    }

    test('1. uninstall ждёт persistence: до записи состояния не дошли', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.runAndFlush(() => manager.disable('demo'));
      expect((await store.load('demo'))!.state, 'disabled');

      store.pause();

      // Операция «уходит» в менеджер и возвращается, но запись в
      // хранилище ещё заблокирована — как в реальности, когда Isar
      // отвечает не мгновенно.
      final done = startCritical(() => manager.uninstall('demo'));
      await Future<void>.delayed(Duration.zero);

      expect(manager.stateOf('demo'), ModuleState.uninstalled,
          reason: 'в памяти модуль уже удалён');
      expect((await store.load('demo'))!.state, 'disabled',
          reason: 'но в хранилище ещё старое состояние — запись не завершена');

      store.resume();
      await done;

      expect((await store.load('demo'))!.state, 'uninstalled');
    });

    test('2. после uninstall tombstone и данные модуля уже сохранены',
        () async {
      await manager.install('demo');
      await manager.enable('demo');
      await storageFactory.call('demo').setString('note', 'данные модуля');
      // Порядок uninstall обязан соблюдать сам ModuleManager: сначала
      // выключить, потом удалить.
      await persistence.runAndFlush(() => manager.disable('demo'));
      await persistence.flush();

      store.pause();
      final done = startCritical(() => manager.uninstall('demo'));
      await Future<void>.delayed(Duration.zero);
      store.resume();
      await done;

      final saved = await store.load('demo');
      expect(saved, isNotNull, reason: 'tombstone обязан лежать в хранилище');
      expect(saved!.state, 'uninstalled');
      expect(saved.enabled, isFalse);
      expect(
        storageFactory.buckets['demo'],
        isEmpty,
        reason: 'данные модуля стёрты до возврата операции, а не после',
      );

      // Холодный старт: tombstone не даёт модулю воскреснуть.
      final freshManager = ModuleManager(searchService: GlobalSearchService());
      await ModuleStateRestorer(freshManager, store).restore();
      expect(freshManager.stateOf('demo'), isNull);
    });

    test('3. disable ждёт persistence', () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.flush();

      store.pause();
      final done = startCritical(() => manager.disable('demo'));
      await Future<void>.delayed(Duration.zero);

      expect((await store.load('demo'))!.state, 'enabled',
          reason: 'состояние не должно записаться раньше завершения записи');

      store.resume();
      await done;

      expect((await store.load('demo'))!.state, 'disabled');
    });

    test('4. enable ждёт persistence', () async {
      await manager.install('demo');
      await persistence.flush();

      store.pause();
      final done = startCritical(() => manager.enable('demo'));
      await Future<void>.delayed(Duration.zero);

      expect((await store.load('demo'))!.state, 'installed');

      store.resume();
      await done;

      final saved = await store.load('demo');
      expect(saved!.state, 'enabled');
      expect(saved.enabled, isTrue);
    });

    test('5. быстрые последовательные изменения не теряются', () async {
      await persistence.runAndFlush(() => manager.install('demo'));
      expect((await store.load('demo'))!.state, 'installed');

      await persistence.runAndFlush(() => manager.enable('demo'));
      expect((await store.load('demo'))!.state, 'enabled');

      await persistence.runAndFlush(() => manager.disable('demo'));
      expect((await store.load('demo'))!.state, 'disabled');

      await persistence.runAndFlush(() => manager.uninstall('demo'));
      expect((await store.load('demo'))!.state, 'uninstalled');

      // Порядок записей совпадает с порядком операций: FIFO не нарушен.
      expect(
        store.saveOrder,
        ['installed', 'enabled', 'disabled', 'uninstalled'],
        reason: 'каждая операция обязана записать своё состояние, '
            'а не «последнее на момент фоновой синхронизации»',
      );
    });

    test('6. ошибка persistence: операция честно сообщает о провале записи',
        () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.flush();

      store.failSaves = true;

      await expectLater(
        persistence.runAndFlush(() => manager.disable('demo')),
        throwsA(isA<ModuleStatePersistenceException>()),
      );

      // Ошибка не должна быть «съедена»: молчаливый успех скрыл бы
      // потерю состояния при следующем запуске.
      expect(
        (await store.load('demo'))!.state,
        'enabled',
        reason: 'неудачная запись не должна оставлять новое состояние',
      );
    });

    test('6b. текст ошибки не раскрывает стектрейс и внутренние имена',
        () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.flush();
      store.failSaves = true;

      Object? thrown;
      try {
        await persistence.runAndFlush(() => manager.disable('demo'));
      } catch (error) {
        thrown = error;
      }

      final reason = (thrown! as ModuleStatePersistenceException).reason;
      expect(reason, contains('не сохранено'));
      expect(reason, isNot(contains('#0')));
      expect(reason, isNot(contains('at package:personal_hub')));
    });

    test('7. flush продолжает работать после ошибки предыдущей операции',
        () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.flush();

      store.failNextSave = true;
      await expectLater(
        persistence.runAndFlush(() => manager.disable('demo')),
        throwsA(isA<ModuleStatePersistenceException>()),
      );

      // Хвост очереди не сломан: следующая операция пишет состояние
      // и возвращает успех.
      store.failSaves = false;
      await persistence.runAndFlush(() => manager.enable('demo'));
      expect((await store.load('demo'))!.state, 'enabled');

      // И обычный flush() после ошибки тоже работает.
      await manager.disable('demo');
      await persistence.flush();
      expect((await store.load('demo'))!.state, 'disabled');
    });

    test('8. неудачная операция не превращается в «успешно сохранённую»',
        () async {
      await manager.install('demo');
      await manager.enable('demo');
      await persistence.flush();

      // uninstall включённого модуля запрещён самим ModuleManager.
      await expectLater(
        persistence.runAndFlush(() => manager.uninstall('demo')),
        throwsA(isA<ModuleLifecycleError>()),
      );

      expect((await store.load('demo'))!.state, 'enabled',
          reason: 'несостоявшаяся операция не должна ничего записывать');
    });
  });

  // Регрессия на зону, а не на порядок записей.
  //
  // Очередь записей раньше начиналась с `Future<void>.value()`,
  // созданной в конструкторе persistence. Объект, созданный в
  // setUp() (вне FakeAsync-зоны testWidgets), а использованный
  // внутри testWidgets(), зависал НАВСЕГДА: continuation после
  // `await _store.load(...)` в _sync() не получал управления, и
  // flush() не возвращался. Поэтому этот тест создаёт persistence
  // в setUp() — как в реальном UI-тесте, — и обязан завершиться.
  group('зона очереди (AUD-08 regression)', () {
    testWidgets(
        'flush() завершается, когда persistence создан в setUp, '
        'а использован внутри testWidgets', (tester) async {
      await manager.install('demo');
      await manager.enable('demo');

      // Раньше зависал ровно здесь.
      await persistence.flush();

      expect((await store.load('demo'))!.state, 'enabled');
      expect(persistence.syncCount, greaterThan(0));
    });

    testWidgets('жизненный цикл внутри testWidgets доходит до записи',
        (tester) async {
      await persistence.runAndFlush(() => manager.install('demo'));
      expect((await store.load('demo'))!.state, 'installed');

      await persistence.runAndFlush(() => manager.enable('demo'));
      expect((await store.load('demo'))!.state, 'enabled');
      expect((await store.load('demo'))!.enabled, isTrue);

      await persistence.runAndFlush(() => manager.disable('demo'));
      expect((await store.load('demo'))!.state, 'disabled');

      await persistence.runAndFlush(() => manager.uninstall('demo'));
      final tombstone = await store.load('demo');
      expect(tombstone, isNotNull);
      expect(tombstone!.state, 'uninstalled');
    });

    testWidgets('flush() на пустой очереди завершается сразу',
        (tester) async {
      // Ни одной записи не было — flush() обязан выйти, а не ждать
      // несуществующий хвост очереди.
      await persistence.flush();
      expect(persistence.syncCount, 0);
    });
  });
}

/// Хранилище, запись которого можно остановить и потом отпустить.
///
/// Это ключ к проверке гарантии «операция завершена только после
/// записи»: между завершением вызова и реальной записью появляется
/// контролируемое окно, в котором состояние в хранилище заведомо
/// устарело. Если бы операция возвращалась раньше записи, тест увидел
/// бы старое значение.
class _GatedStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};
  final List<String> saveOrder = <String>[];

  Completer<void>? _gate;
  bool failSaves = false;
  bool failNextSave = false;

  /// Останавливает запись до вызова [resume].
  void pause() {
    _gate = Completer<void>();
  }

  /// Отпускает запись.
  void resume() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    final gate = _gate;
    if (gate != null) {
      await gate.future;
    }
    if (failSaves) {
      throw StateError('хранилище недоступно');
    }
    if (failNextSave) {
      failNextSave = false;
      throw StateError('хранилище недоступно один раз');
    }
    saveOrder.add(snapshot.state);
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

/// Хранилище, у которого ПЕРВАЯ запись намеренно медленная, а все
/// последующие — мгновенные.
///
/// Так воспроизводится исходный баг: при несериализованных
/// fire-and-forget `_sync()` первая (самая ранняя) запись завершалась
/// ПОЗЖЕ второй и затирала её более свежим состоянием. С очередью
/// порядок завершения совпадает с порядком постановки.
class _SlowFirstSaveStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};
  final List<String> saveOrder = <String>[];
  int _saveCount = 0;
  bool failNextSave = false;

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _saveCount++;
    if (_saveCount == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (failNextSave) {
      failNextSave = false;
      throw StateError('сбой записи состояния');
    }
    saveOrder.add(snapshot.state);
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}
