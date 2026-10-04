/// Регрессия AUD-08 на уровне production-обвязки.
///
/// Core-гарантия (операция завершена только после записи состояния)
/// проверяется в test/core/modules/module_state_persistence_test.dart.
/// Здесь проверяется, что реальные кнопки Module Store действительно
/// проходят через эту гарантию: без обвязки сбой записи состояния был
/// бы невидим — кнопка отработала бы «успешно», модуль изменился бы в
/// памяти, а после перезапуска всё вернулось бы назад.
library module_store_persistence_test;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_persistence_scope.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/widgets/module_store/installed_section.dart';

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

class _InMemoryModuleStorage implements ModuleStorage {
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

/// Хранилище состояния, запись которого можно уронить по требованию.
class _ControllableStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};
  bool failSaves = false;

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    if (failSaves) {
      throw StateError('хранилище недоступно');
    }
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

void main() {
  late ModuleManager _manager;
  late _ControllableStore _store;
  late ModuleStatePersistence _persistence;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(
      _FakeModule(
        const ModuleManifest(
          id: 'demo',
          name: 'Демо',
          version: '1.0.0',
          apiVersion: 1,
          author: 'Test',
          description: 'module store persistence test',
          permissions: [],
          dependencies: [],
          icon: 'assets/icon.png',
        ),
      ),
    );
    _manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (moduleId) => _InMemoryModuleStorage(),
    );
    _store = _ControllableStore();
    _persistence = ModuleStatePersistence(
      _manager,
      _store,
      storageFactory: (moduleId) => _InMemoryModuleStorage(),
    );
  });

  tearDown(() {
    _persistence.dispose();
    ModuleRegistry.clear();
  });

  Widget _app() {
    return ModuleStatePersistenceScope(
      persistence: _persistence,
      child: ModuleManagerScope(
        manager: _manager,
        child: const MaterialApp(
          home: Scaffold(body: InstalledSection()),
        ),
      ),
    );
  }

  Future<void> _installEnabled() async {
    await _manager.install('demo');
    await _manager.enable('demo');
    await _persistence.flush();
  }

  testWidgets('кнопка «Выключить» доводит операцию до записи состояния',
      (tester) async {
    await _installEnabled();
    expect((await _store.load('demo'))!.state, 'enabled');

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выключить'));
    await tester.pumpAndSettle();

    expect(_manager.stateOf('demo'), ModuleState.disabled);
    expect(
      (await _store.load('demo'))!.state,
      'disabled',
      reason: 'кнопка обязана довести операцию до записи, а не сменить '
          'состояние только в памяти',
    );
  });

  testWidgets('сбой записи состояния показывается пользователю, а не теряется',
      (tester) async {
    await _installEnabled();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    _store.failSaves = true;

    await tester.tap(find.text('Выключить'));
    await tester.pumpAndSettle();

    // Операция в памяти прошла, но её состояние не сохранено. Раньше
    // такой случай заканчивался молчаливым «успехом» — пользователь
    // обнаруживал потерю изменения только после перезапуска.
    expect(_manager.stateOf('demo'), ModuleState.disabled);
    expect(
      find.textContaining('не сохранено'),
      findsOneWidget,
      reason: 'пользователь обязан узнать, что состояние не записалось',
    );
    expect((await _store.load('demo'))!.state, 'enabled',
        reason: 'в хранилище остаётся прежнее состояние');
  });

  testWidgets('после сбоя следующая операция снова пишет состояние',
      (tester) async {
    await _installEnabled();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    _store.failSaves = true;
    await tester.tap(find.text('Выключить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('не сохранено'), findsOneWidget);

    // Снэкбар живёт 4 секунды, а pumpAndSettle не прокручивает
    // таймер его скрытия — иначе следующая проверка «ошибки больше
    // нет» видела бы старое сообщение и падала не по существу.
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.textContaining('не сохранено'), findsNothing);

    // Хранилище ожило: следующая операция обязана записать состояние,
    // иначе модуль навсегда остался бы рассинхронизированным.
    _store.failSaves = false;
    await tester.tap(find.text('Включить'));
    await tester.pumpAndSettle();

    expect((await _store.load('demo'))!.state, 'enabled');
    expect(find.textContaining('не сохранено'), findsNothing);
  });

  testWidgets('кнопка «Удалить» сохраняет tombstone до завершения операции',
      (tester) async {
    await _installEnabled();
    await _manager.disable('demo');
    await _persistence.flush();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    final saved = await _store.load('demo');
    expect(saved, isNotNull,
        reason: 'tombstone обязан лежать в хранилище после удаления');
    expect(saved!.state, 'uninstalled');
    expect(_manager.stateOf('demo'), ModuleState.uninstalled);
  });
}
