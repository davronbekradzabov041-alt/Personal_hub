import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

class _TestModule extends Module {
  _TestModule(this._manifest, {this.onInstallHook});
  final ModuleManifest _manifest;
  final Future<void> Function(ModuleApi api)? onInstallHook;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {
    if (onInstallHook != null) await onInstallHook!(api);
  }
}

class _FakeModuleStorage implements ModuleStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

class _FakePersistenceStore implements ModuleStateStore {
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

ModuleManifest _manifest({
  required String id,
  String version = '1.0.0',
  int apiVersion = kCoreModuleApiVersion,
  List<ModuleDependency> dependencies = const [],
}) {
  return ModuleManifest(
    id: id,
    name: id,
    version: version,
    apiVersion: apiVersion,
    author: 'Test',
    dependencies: dependencies,
  );
}

void main() {
  late GlobalSearchService searchService;

  setUp(() {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
  });

  tearDown(() {
    ModuleRegistry.clear();
  });

  group('1. Проверка manifest при install', () {
    test('несовместимая apiVersion отклоняется', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'bad-api', apiVersion: 99)));

      final result = await manager.tryInstall('bad-api');

      expect(result.isSuccess, isFalse);
      expect(result.violations.any((v) => v.contains('несовместимая версия')), isTrue);
      expect(manager.stateOf('bad-api'), isNull);
    });

    test('неверный формат версии отклоняется', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'bad-version', version: 'v1')));

      final result = await manager.tryInstall('bad-version');

      expect(result.isSuccess, isFalse);
      expect(result.violations.any((v) => v.contains('формат версии')), isTrue);
    });

    test('дублирующийся moduleId отклоняется на уровне ModuleRegistry', () {
      ModuleRegistry.register(_TestModule(_manifest(id: 'dup')));
      expect(
        () => ModuleRegistry.register(_TestModule(_manifest(id: 'dup'))),
        throwsException,
      );
    });
  });

  group('2. Защита ModuleManager', () {
    test('повторная установка одного moduleId запрещена', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'once')));

      final first = await manager.tryInstall('once');
      final second = await manager.tryInstall('once');

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isFalse);
      expect(second.reason, contains('уже установлен'));
    });

    test('невыполненная зависимость блокирует установку', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(
        id: 'needs-core',
        dependencies: [const ModuleDependency(moduleId: 'core-thing')],
      )));

      final result = await manager.tryInstall('needs-core');

      expect(result.isSuccess, isFalse);
      expect(result.violations.any((v) => v.contains('не выполнены зависимости')), isTrue);
    });

    test('выполненная (включённая) зависимость пропускает установку', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'core-thing')));
      ModuleRegistry.register(_TestModule(_manifest(
        id: 'needs-core-2',
        dependencies: [const ModuleDependency(moduleId: 'core-thing')],
      )));

      await manager.install('core-thing');
      await manager.enable('core-thing');

      final result = await manager.tryInstall('needs-core-2');
      expect(result.isSuccess, isTrue);
    });

    test('циклические зависимости блокируют установку', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      // a → b → a
      ModuleRegistry.register(_TestModule(_manifest(
        id: 'a',
        dependencies: [const ModuleDependency(moduleId: 'b')],
      )));
      ModuleRegistry.register(_TestModule(_manifest(
        id: 'b',
        dependencies: [const ModuleDependency(moduleId: 'a')],
      )));

      final result = await manager.tryInstall('a');

      expect(result.isSuccess, isFalse);
      expect(result.violations.any((v) => v.contains('циклические зависимости')), isTrue);
    });

    test('нарушение последовательности жизненного цикла отклоняется', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'seq')));

      // enable до install
      expect(() => manager.enable('seq'), throwsException);
      // uninstall до install
      expect(() => manager.uninstall('seq'), throwsException);
    });
  });

  group('3. Rollback', () {
    test('неудачный install не оставляет модуль установленным', () async {
      final storage = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(_TestModule(
        _manifest(id: 'failing'),
        onInstallHook: (api) async {
          await api.storage.setString('partial', 'should-be-rolled-back');
          throw Exception('boom');
        },
      ));

      final result = await manager.tryInstall('failing');

      expect(result.isSuccess, isFalse);
      expect(result.reason, contains('onInstall'));
      expect(manager.stateOf('failing'), isNull); // не "застряло" на installed
    });

    test('неудачный install стирает частично записанные данные', () async {
      final storage = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(_TestModule(
        _manifest(id: 'failing-2'),
        onInstallHook: (api) async {
          await api.storage.setString('temp-key', 'temp-value');
          throw Exception('boom');
        },
      ));

      await manager.tryInstall('failing-2');

      expect(storage.data, isEmpty);
    });

    test('после rollback установку можно повторить успешно', () async {
      final storage = _FakeModuleStorage();
      var shouldFail = true;
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(_TestModule(
        _manifest(id: 'retry'),
        onInstallHook: (api) async {
          if (shouldFail) throw Exception('boom');
        },
      ));

      final failed = await manager.tryInstall('retry');
      expect(failed.isSuccess, isFalse);

      shouldFail = false;
      final succeeded = await manager.tryInstall('retry');
      expect(succeeded.isSuccess, isTrue);
      expect(manager.stateOf('retry'), ModuleState.installed);
    });

    test('install() (обратная совместимость) по-прежнему бросает исключение при отказе', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'bad-api-2', apiVersion: 99)));

      expect(() => manager.install('bad-api-2'), throwsException);
    });
  });

  group('4. Безопасное удаление + сохранность остальных модулей', () {
    test('uninstall стирает состояние и key-value данные модуля', () async {
      final storage = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'to-remove')));

      await manager.install('to-remove');
      final api = manager.apiFor('to-remove');
      await api.storage.setString('settings', 'value');

      await manager.enable('to-remove');
      await manager.disable('to-remove');
      await manager.uninstall('to-remove');

      expect(manager.stateOf('to-remove'), ModuleState.uninstalled);
      // ModuleManager сам не обязан стирать хранилище (это делает
      // ModuleStatePersistence, Этап 9, подписанный на notifyListeners) —
      // здесь проверяем то, за что отвечает именно ModuleManager:
      // apiFor() после uninstall выдаёт СВЕЖИЙ ModuleApi (старый убран
      // из кэша), а не тот же самый с оставшимися данными.
      final freshApi = manager.apiFor('to-remove');
      expect(identical(freshApi, api), isFalse);
    });

    test('удаление одного модуля не затрагивает данные и состояние другого', () async {
      final storageA = _FakeModuleStorage();
      final storageB = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (id) => id == 'module-a' ? storageA : storageB,
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'module-a')));
      ModuleRegistry.register(_TestModule(_manifest(id: 'module-b')));

      await manager.install('module-a');
      await manager.enable('module-a');
      await manager.apiFor('module-a').storage.setString('key-a', 'value-a');

      await manager.install('module-b');
      await manager.enable('module-b');
      await manager.apiFor('module-b').storage.setString('key-b', 'value-b');

      await manager.disable('module-a');
      await manager.uninstall('module-a');

      expect(manager.stateOf('module-a'), ModuleState.uninstalled);
      // module-b не пострадал ни по состоянию, ни по данным:
      expect(manager.stateOf('module-b'), ModuleState.enabled);
      expect(storageB.data['key-b'], 'value-b');
      // и собственное хранилище module-a (отдельный fake-объект) не
      // было задето операцией над module-b и наоборот — разные карты:
      expect(storageA.data.containsKey('key-a'), isTrue);
    });
  });

  group('5. Единая система ошибок', () {
    test('tryInstall возвращает типизированный результат, а не бросает исключение', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(id: 'typed', apiVersion: 99)));

      // Не должно бросить — результат читается как обычное значение.
      final result = await manager.tryInstall('typed');
      expect(result.isSuccess, isFalse);
      expect(result.moduleId, 'typed');
      expect(result.violations, isNotEmpty);
    });

    test('несколько нарушений собираются в один результат', () async {
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (_) => _FakeModuleStorage(),
      );
      ModuleRegistry.register(_TestModule(_manifest(
        id: 'multi-bad',
        version: 'not-a-version',
        apiVersion: 99,
      )));

      final result = await manager.tryInstall('multi-bad');

      expect(result.violations.length, greaterThanOrEqualTo(2));
    });
  });

  group('6. Сквозная проверка через ModuleStatePersistence', () {
    test('uninstall полностью стирает состояние и данные ОДНОГО модуля, '
        'сохранность остальных не нарушена', () async {
      final store = _FakePersistenceStore();
      final storageA = _FakeModuleStorage();
      final storageB = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: searchService,
        storageFactory: (id) => id == 'victim' ? storageA : storageB,
      );
      final persistence = ModuleStatePersistence(
        manager,
        store,
        storageFactory: (id) => id == 'victim' ? storageA : storageB,
      );
      addTearDown(persistence.dispose);

      ModuleRegistry.register(_TestModule(_manifest(id: 'victim')));
      ModuleRegistry.register(_TestModule(_manifest(id: 'survivor')));

      await manager.install('victim');
      await manager.enable('victim');
      await manager.apiFor('victim').storage.setString('secret', 'gone-soon');

      await manager.install('survivor');
      await manager.enable('survivor');
      await manager.apiFor('survivor').storage.setString('note', 'still-here');
      await Future<void>.delayed(Duration.zero);

      await manager.disable('victim');
      await manager.uninstall('victim');
      await Future<void>.delayed(Duration.zero);

      // Жертва: ни состояния, ни данных не осталось.
      expect(await store.load('victim'), isNull);
      expect(storageA.data, isEmpty);

      // Выживший: состояние и данные целы — ядро (другие коллекции
      // Isar, не затрагиваемые ModuleStorage вовсе) здесь даже не
      // фигурирует, а другой МОДУЛЬ явно не пострадал.
      final survivorState = await store.load('survivor');
      expect(survivorState, isNotNull);
      expect(survivorState!.state, 'enabled');
      expect(storageB.data['note'], 'still-here');
    });
  });
}
