/// `ModuleManager.update()` после Этапа 8.1-А.
///
/// Проверяются три вещи, ради которых обмен и вынесен и делался:
/// реализация заменяется, ДАННЫЕ ОСТАЮТСЯ, состояние не меняется;
/// отказ не трогает ничего. Файловая часть обновления (обмен
/// песочницы, снимок, откат) живёт в
/// test/core/modules/platform/module_importer_update_test.dart.
library module_update_swap_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/module_update_plan.dart';
import 'package:personal_hub/core/modules/module_update_validator.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

class _StubModule extends Module {
  _StubModule(this._manifest);

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {}
}

class _FakeModuleStorage implements ModuleStorage {
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

ModuleManifest _manifest({
  String id = 'notes',
  String version = '1.0.0',
}) =>
    ModuleManifest(
      id: id,
      name: 'Заметки',
      version: version,
      apiVersion: 1,
      author: 'Test',
    );

void main() {
  late ModuleManager manager;
  late Map<String, _FakeModuleStorage> storages;

  setUp(() {
    ModuleRegistry.clear();
    storages = <String, _FakeModuleStorage>{};
    // Фабрика возвращает ОДИН экземпляр на moduleId — так же, как
    // настоящая ModuleStorageIsar: это тонкая обёртка над одними и
    // теми же строками Isar, а не новое хранилище. Прежний double
    // создавал новую пустую карту на каждый вызов, из-за чего сброс
    // кэша ModuleApi (Этап 9.1) выглядел бы как потеря данных, хотя
    // данными является содержимое за moduleId, а не объект-обёртка.
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (moduleId) =>
          storages[moduleId] ??= _FakeModuleStorage(),
    );
  });

  Future<void> install(_StubModule module, ModuleState state) async {
    // Хранилище создаётся здесь явно, а не лениво фабрикой: тест
    // обращается к нему напрямую и не должен зависеть от того, был ли
    // ModuleApi уже запрошен.
    storages[module.id] = _FakeModuleStorage();
    ModuleRegistry.register(module);
    final result = await manager.tryInstall(module.id);
    expect(result.isSuccess, isTrue, reason: result.reason);
    if (state == ModuleState.enabled) {
      await manager.enable(module.id);
    }
  }

  group('обновление подменяет реализацию, не трогая данные', () {
    test('версия в реестре обновляется, состояние и хранилище — нет', () async {
      final first = _StubModule(_manifest(version: '1.0.0'));
      await install(first, ModuleState.enabled);

      final storage = storages['notes']!;
      await storage.setString('note:1', 'черновик');
      await storage.setString('schema:version', '3');

      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.update(_StubModule(_manifest(version: '1.1.0')));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.1.0');
      expect(manager.stateOf('notes'), ModuleState.enabled,
          reason: 'update не включает и не выключает модуль');
      expect(storage.getString('note:1'), completion('черновик'));
      expect(storage.getString('schema:version'), completion('3'));
      expect(notifications, 1);
    });

    test('выключенный модуль обновляется и остаётся выключенным', () async {
      final first = _StubModule(_manifest(version: '1.0.0'));
      await install(first, ModuleState.installed);

      await manager.update(_StubModule(_manifest(version: '1.2.0')));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.2.0');
      expect(manager.stateOf('notes'), ModuleState.installed);
    });

    test('ModuleApi и хранилище те же: uninstall+install не происходит', () async {
      final first = _StubModule(_manifest(version: '1.0.0'));
      await install(first, ModuleState.enabled);
      final storage = storages['notes']!;

      await manager.update(_StubModule(_manifest(version: '1.1.0')));

      // Если бы обновление прошло через uninstall+install, кэш
      // ModuleApi был бы сброшен и модуль получил бы НОВОЕ хранилище.
      expect(identical(manager.apiFor('notes').storage, storage), isTrue);
    });

    test('отказ проверок не трогает реестр и данные', () async {
      final first = _StubModule(_manifest(version: '1.0.0'));
      await install(first, ModuleState.enabled);
      final storage = storages['notes']!;
      await storage.setString('note:1', 'черновик');

      await expectLater(
        manager.update(_StubModule(_manifest(version: '0.9.0'))),
        throwsA(isA<ModuleLifecycleError>()),
      );

      expect(ModuleRegistry.get('notes'), same(first),
          reason: 'непрошедшая проверка не должна подменять реализацию');
      expect(storage.getString('note:1'), completion('черновик'));
    });

    test('отказ называет причину', () async {
      await install(_StubModule(_manifest(version: '2.0.0')), ModuleState.enabled);

      await expectLater(
        manager.update(_StubModule(_manifest(version: '1.0.0'))),
        throwsA(
          isA<ModuleLifecycleError>().having(
            (e) => e.reason,
            'reason',
            contains('откат версии запрещён'),
          ),
        ),
      );
    });

    test('та же версия по-прежнему отказ', () async {
      await install(_StubModule(_manifest(version: '1.0.0')), ModuleState.enabled);

      await expectLater(
        manager.update(_StubModule(_manifest(version: '1.0.0'))),
        throwsA(
          isA<ModuleLifecycleError>().having(
            (e) => e.reason,
            'reason',
            contains('версия не изменилась'),
          ),
        ),
      );
    });

    test('политика отката задаётся снаружи и реально действует', () async {
      manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (moduleId) =>
            storages[moduleId] = _FakeModuleStorage(),
        updateValidator: ModuleUpdateValidator(
          policy: const ModuleUpdatePolicy(allowDowngrade: true),
        ),
      );
      await install(_StubModule(_manifest(version: '2.0.0')), ModuleState.enabled);

      await manager.update(_StubModule(_manifest(version: '1.5.0')));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.5.0');
    });

    test('обновление неустановленного модуля по-прежнему запрещено', () async {
      ModuleRegistry.register(_StubModule(_manifest(version: '1.0.0')));

      await expectLater(
        manager.update(_StubModule(_manifest(version: '1.1.0'))),
        throwsA(
          isA<ModuleLifecycleError>().having(
            (e) => e.reason,
            'reason',
            contains('не установлен'),
          ),
        ),
      );
    });
  });

  group('границы ModuleManager.update', () {
    test('обмен НЕ трогает песочницу внешнего модуля', () async {
      // ModuleManager.update подменяет ТОЛЬКО объект в реестре: работа с
      // файловой системой — это отдельная операция (Этап 8.1-Б,
      // ModuleImporter.updateFromBytes + ModuleSandboxSwap). Проверяется,
      // чтобы «обмен» в двух разных слоях не путались: реестровый обмен
      // без обмена песочницы — это половина обновления, а не оно само.
      await install(_StubModule(_manifest(version: '1.0.0')), ModuleState.enabled);

      await manager.update(_StubModule(_manifest(version: '1.1.0')));

      expect(ModuleRegistry.get('notes')!.manifest.version, '1.1.0');
    });

    test('валидатор менеджера доступен снаружи для предпроверки', () async {
      await install(_StubModule(_manifest(version: '1.0.0')), ModuleState.enabled);

      final plan = manager.updateValidator.validate(
        newManifest: _manifest(version: '1.1.0'),
        currentManifest: ModuleRegistry.get('notes')!.manifest,
        currentState: manager.stateOf('notes'),
      );

      expect(plan.isAccepted, isTrue);
    });
  });
}