/// Контракт Home-секций (QUAL-03, шаг 9).
///
/// Проверяет ровно то, ради чего контракт существует:
///
/// * секция появляется на главном экране ТОЛЬКО у активного модуля;
/// * состояние модуля (installed/disabled/uninstalled/enabled)
///   управляет видимостью секции без всякой отдельной синхронизации;
/// * порядок секций задаёт модуль, а не экран;
/// * модуль без вклада не объявляет ничего — и внешний пакет
///   (ExternalModuleAdapter) не может добавить UI, что прямо
///   запрещено Architectural Rule.
library home_section_contract_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/home_section.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_permission.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/screens/home_screen.dart';

ModuleManifest _manifestFor(String id) => ModuleManifest(
      id: id,
      name: 'Demo $id',
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
      description: 'Модуль, отдающий секцию главного экрана',
      permissions: const <ModulePermission>[],
    );

/// Синтетический модуль с одной секцией.
class _ContributingModule extends Module {
  _ContributingModule({required String id, required this.sectionOrder})
      : _manifest = _manifestFor(id);

  final ModuleManifest _manifest;

  /// Порядок секции, который модуль объявляет.
  final int sectionOrder;

  /// Сколько раз ядро дёрнуло onRefresh секции.
  int refreshCalls = 0;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.widgets_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  List<HomeSection> get homeSections => <HomeSection>[
        HomeSection(
          moduleId: id,
          order: sectionOrder,
          builder: (context) => Text(
            'секция $id',
            key: ValueKey<String>('section-$id'),
          ),
          onRefresh: () async => refreshCalls++,
        ),
      ];
}

/// Модуль без вклада в Home — обычный встроенный модуль.
class _PlainModule extends Module {
  _PlainModule(String id) : _manifest = _manifestFor(id);

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ModuleManager manager;

  setUp(() {
    ModuleRegistry.clear();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _ThrowingStorage(),
    );
  });

  tearDown(ModuleRegistry.clear);

  Widget home() => ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(home: HomeScreen()),
      );

  group('HomeSection: значение по умолчанию', () {
    test('модуль без вклада не объявляет ни одной секции', () {
      final module = _PlainModule('plain');

      expect(module.homeSections, isEmpty);
    });

    test('ExternalModuleAdapter не может добавить UI на главный экран', () {
      // Architectural Rule (external_module_adapter.dart): внешний пакет
      // состоит из манифеста, данных и ассетов — своего Dart-кода у него
      // нет и быть не может. Проверяем это структурно, а не запретом:
      // адаптер наследует пустое значение по умолчанию.
      final adapter = ExternalModuleAdapter(_manifestFor('external'));

      expect(adapter.homeSections, isEmpty);
    });

    testWidgets('активный модуль без вклада не рисует ничего', (tester) async {
      ModuleRegistry.register(_PlainModule('plain'));
      manager.setStateForTesting('plain', ModuleState.enabled);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('секция'), findsNothing);
    });
  });

  group('HomeSection: состояние модуля управляет видимостью', () {
    Future<void> pumpWithState(
      WidgetTester tester,
      ModuleState state,
    ) async {
      ModuleRegistry.register(
        _ContributingModule(id: 'demo', sectionOrder: 10),
      );
      manager.setStateForTesting('demo', state);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
    }

    testWidgets('enabled — секция присутствует', (tester) async {
      await pumpWithState(tester, ModuleState.enabled);

      expect(find.byKey(const ValueKey<String>('section-demo')), findsOneWidget);
      expect(find.text('секция demo'), findsOneWidget);
    });

    testWidgets('installed — секции нет: модуль ещё не активен', (tester) async {
      await pumpWithState(tester, ModuleState.installed);

      expect(find.byKey(const ValueKey<String>('section-demo')), findsNothing);
    });

    testWidgets('disabled — секции нет: модуль выключен', (tester) async {
      await pumpWithState(tester, ModuleState.disabled);

      expect(find.byKey(const ValueKey<String>('section-demo')), findsNothing);
    });

    testWidgets('uninstalled — секции нет', (tester) async {
      await pumpWithState(tester, ModuleState.uninstalled);

      expect(find.byKey(const ValueKey<String>('section-demo')), findsNothing);
    });

    testWidgets('переход enabled → disabled убирает секцию без пересборки экрана',
        (tester) async {
      await pumpWithState(tester, ModuleState.enabled);
      expect(find.byKey(const ValueKey<String>('section-demo')), findsOneWidget);

      // Событие менеджера: экран подписан на ModuleManager, поэтому
      // список секций пересобирается сам — без ручного обновления.
      manager.setStateForTesting('demo', ModuleState.disabled);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('section-demo')), findsNothing);
    });

    testWidgets('переход disabled → enabled возвращает секцию', (tester) async {
      await pumpWithState(tester, ModuleState.disabled);
      expect(find.byKey(const ValueKey<String>('section-demo')), findsNothing);

      manager.setStateForTesting('demo', ModuleState.enabled);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('section-demo')), findsOneWidget);
    });
  });

  group('HomeSection: порядок и обновление', () {
    testWidgets('секции идут в порядке, объявленном модулями', (tester) async {
      ModuleRegistry.register(_ContributingModule(id: 'late', sectionOrder: 50));
      ModuleRegistry.register(_ContributingModule(id: 'early', sectionOrder: 5));
      manager.setStateForTesting('late', ModuleState.enabled);
      manager.setStateForTesting('early', ModuleState.enabled);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      final early = tester.getTopLeft(find.byKey(const ValueKey<String>('section-early')));
      final late = tester.getTopLeft(find.byKey(const ValueKey<String>('section-late')));

      expect(early.dy, lessThan(late.dy),
          reason: 'секция с меньшим order должна идти выше');
    });

    testWidgets('pull-to-refresh вызывает onRefresh каждой видимой секции',
        (tester) async {
      final first = _ContributingModule(id: 'first', sectionOrder: 5);
      final second = _ContributingModule(id: 'second', sectionOrder: 10);
      final hidden = _ContributingModule(id: 'hidden', sectionOrder: 20);

      ModuleRegistry.register(first);
      ModuleRegistry.register(second);
      ModuleRegistry.register(hidden);
      manager.setStateForTesting('first', ModuleState.enabled);
      manager.setStateForTesting('second', ModuleState.enabled);
      // третий модуль выключен — его секция не видима и обновляться не должна
      manager.setStateForTesting('hidden', ModuleState.disabled);

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0.0, 400.0),
        1000.0,
      );
      await tester.pumpAndSettle();

      expect(first.refreshCalls, 1, reason: 'onRefresh первой секции вызван');
      expect(second.refreshCalls, 1, reason: 'onRefresh второй секции вызван');
      expect(hidden.refreshCalls, 0,
          reason: 'выключенная секция не обновляется');
    });
  });
}

/// Хранилище-заглушка: тесты контракта не работают с данными.
class _ThrowingStorage implements ModuleStorage {
  @override
  Future<String?> getString(String key) async =>
      throw UnsupportedError('контрактные тесты не читают хранилище');

  @override
  Future<void> setString(String key, String value) async =>
      throw UnsupportedError('контрактные тесты не пишут в хранилище');

  @override
  Future<void> remove(String key) async =>
      throw UnsupportedError('контрактные тесты не пишут в хранилище');

  @override
  Future<List<String>> keys() async =>
      throw UnsupportedError('контрактные тесты не читают хранилище');
}
