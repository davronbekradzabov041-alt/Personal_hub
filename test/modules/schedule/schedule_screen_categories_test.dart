import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/ui/category_form_screen.dart';
import 'package:personal_hub/modules/schedule/ui/category_list_view.dart';
import 'package:personal_hub/modules/schedule/ui/event_form_screen.dart';
import 'package:personal_hub/modules/schedule/ui/schedule_screen.dart';

/// Категории как часть расписания: третья вкладка и её FAB.
///
/// Отдельный файл от тестов списка категорий: здесь важна не логика
/// списка, а то, что он вообще стал частью Schedule и что FAB на вкладке
/// категорий создаёт категорию, а не событие.
class _InMemoryStorage implements ModuleStorage {
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

void main() {
  late ModuleManager manager;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(ScheduleModule());
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _InMemoryStorage(),
    );
    manager.setStateForTesting('schedule', ModuleState.enabled);
  });

  tearDown(() {
    manager.dispose();
    ModuleRegistry.clear();
  });

  Widget schedule() => ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(
          home: ScheduleScreen(moduleId: 'schedule'),
        ),
      );

  testWidgets('у расписания три вкладки, третья — «Категории»', (tester) async {
    await tester.pumpWidget(schedule());
    await tester.pumpAndSettle();

    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Календарь'), findsOneWidget);
    expect(find.text('Категории'), findsOneWidget);
  });

  testWidgets('вкладка категорий показывает список', (tester) async {
    await tester.pumpWidget(schedule());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Категории'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryListView), findsOneWidget);
    expect(find.text('Категорий пока нет'), findsOneWidget);
  });

  testWidgets('FAB на вкладке категорий создаёт категорию', (tester) async {
    await tester.pumpWidget(schedule());
    await tester.pumpAndSettle();

    // На вкладке событий FAB добавляет событие: тот же самый FAB в двух
    // смыслах был бы источником ошибок, а второй FAB стоит ноль.
    expect(find.byTooltip('Добавить событие'), findsOneWidget);

    await tester.tap(find.text('Категории'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Создать категорию'), findsOneWidget);
    expect(find.byTooltip('Добавить событие'), findsNothing);

    await tester.tap(find.byTooltip('Создать категорию'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryFormScreen), findsOneWidget);
  });

  testWidgets('FAB на вкладке событий по-прежнему создаёт событие',
      (tester) async {
    await tester.pumpWidget(schedule());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Добавить событие'));
    await tester.pumpAndSettle();

    expect(find.byType(EventFormScreen), findsOneWidget);
    expect(find.byType(CategoryFormScreen), findsNothing);
  });
}