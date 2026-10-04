import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/ui/category_form_screen.dart';
import 'package:personal_hub/modules/schedule/ui/category_list_view.dart';
import 'package:personal_hub/modules/schedule/ui/category_visuals.dart';

/// Список категорий: создание, редактирование, удаление и порядок.
///
/// Проверяется на настоящих виджетах с настоящим репозиторием поверх
/// хранилища в памяти: список, форма и репозиторий — одна связка, и
/// подмена любого её звена (например, «у настоящего экрана другой
/// счётчик событий в диалоге удаления») проверить бы не позволила.
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
  late _InMemoryStorage storage;
  late ScheduleCategoryRepository categories;
  late ScheduleRepository events;

  setUp(() {
    storage = _InMemoryStorage();
    categories = ScheduleCategoryRepository(storage);
    events = ScheduleRepository(storage);
  });

  Widget view({VoidCallback? onCreateRequested}) => MaterialApp(
        home: Scaffold(
          body: CategoryListView(
            repository: categories,
            onCreateRequested: onCreateRequested,
          ),
        ),
      );

  /// Экранная обёртка — как её открывает форма события.
  Widget screen() => MaterialApp(home: CategoryListScreen(repository: categories));

  Future<Category> seedCategory(String name) => categories.create(
        name: name,
        colorValue: 0xFFD97706,
        iconKey: 'work',
      );

  Future<ScheduleEvent> seedEvent({
    required String id,
    String? categoryId,
    String category = '',
  }) async {
    final event = ScheduleEvent(
      id: id,
      title: 'Событие $id',
      category: category,
      categoryId: categoryId,
      priority: EventPriority.medium,
      date: DateTime(2026, 1, 15),
      startMinutes: 540,
      endMinutes: 600,
      status: EventStatus.planned,
    );
    await events.add(event);
    return event;
  }

  /// Создание категории через экранную кнопку.
  Future<void> createThroughScreen(
    WidgetTester tester, {
    required String name,
  }) async {
    await tester.tap(find.byTooltip('Создать категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, name);
    await tester.pump();
  }

  group('Пустое состояние', () {
    testWidgets('подсказывает создать категорию', (tester) async {
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();

      expect(find.text('Категорий пока нет'), findsOneWidget);
      expect(find.text('Создать категорию'), findsOneWidget);
    });

    testWidgets('кнопка создания уходит наверх, если её переопределили',
        (tester) async {
      // Вкладка расписания показывает FAB на экране: две кнопки
      // «создать категорию» на одном экране сбивали бы с толку.
      var called = false;
      await tester.pumpWidget(view(onCreateRequested: () => called = true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Создать категорию'));
      expect(called, isTrue);
    });
  });

  group('Создание', () {
    testWidgets('форма сохраняет имя, цвет и иконку', (tester) async {
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Создать категорию'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Работа');
      await tester.pump();

      // Второй цвет палитры и иконка study — выбор не дефолтный.
      await tester.tap(find.bySemanticsLabel(RegExp('^Цвет ')).at(1));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Иконка study'));
      await tester.pump();

      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      final all = await categories.getAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'Работа');
      expect(all.single.colorValue, categoryPalette[1]);
      expect(all.single.iconKey, 'study');
      expect(find.text('Работа'), findsOneWidget,
          reason: 'созданная категория обязана появиться в списке');
    });

    testWidgets('пустое имя не создаёт категорию и объясняет почему',
        (tester) async {
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Создать категорию'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(await categories.getAll(), isEmpty);
      expect(find.text('название категории не может быть пустым'), findsOneWidget);
      expect(find.byType(CategoryFormScreen), findsOneWidget,
          reason: 'форма обязана остаться открытой, чтобы не терять ввод');
    });

    testWidgets('дубль имени не создаёт вторую категорию', (tester) async {
      await seedCategory('Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await createThroughScreen(tester, name: '  работа ');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(await categories.getAll(), hasLength(1));
      expect(find.textContaining('уже существует'), findsOneWidget);
    });

    testWidgets('категория, созданная с экрана, попадает в список',
        (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await createThroughScreen(tester, name: 'Здоровье');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(find.text('Здоровье'), findsOneWidget);
      expect((await categories.getAll()).single.name, 'Здоровье');
    });
  });

  group('Редактирование', () {
    testWidgets('переименование меняет название в списке', (tester) async {
      await seedCategory('Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Деловые');
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect((await categories.getAll()).single.name, 'Деловые');
      expect(find.text('Деловые'), findsOneWidget);
      expect(find.text('Работа'), findsNothing);
    });

    testWidgets('своё имя не считается дублем самого себя', (tester) async {
      final category = await seedCategory('Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      // Меняем только цвет, имя остаётся прежним.
      await tester.tap(find.bySemanticsLabel(RegExp('^Цвет ')).at(2));
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      final updated = await categories.getById(category.id);
      expect(updated, isNotNull);
      expect(updated!.name, 'Работа');
      expect(updated.colorValue, categoryPalette[2]);
    });
  });

  group('Удаление', () {
    testWidgets('диалог называет число затронутых событий', (tester) async {
      final work = await seedCategory('Работа');
      await seedEvent(id: 'e1', categoryId: work.id, category: 'Работа');
      await seedEvent(id: 'e2', categoryId: work.id, category: 'Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить категорию?'), findsOneWidget);
      expect(find.textContaining('У 2 событий'), findsOneWidget);
      expect(find.textContaining('станут без категории'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(await categories.getAll(), isEmpty);
      final remaining = await events.getAll();
      expect(remaining, hasLength(2), reason: 'события не удаляются');
      for (final event in remaining) {
        expect(event.categoryId, isNull);
      }
    });

    testWidgets('одно затронутое событие читается по-русски', (tester) async {
      final work = await seedCategory('Работа');
      await seedEvent(id: 'e1', categoryId: work.id, category: 'Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию'));
      await tester.pumpAndSettle();

      expect(find.textContaining('У 1 события'), findsOneWidget);
    });

    testWidgets('пять затронутых событий читаются по-русски', (tester) async {
      final work = await seedCategory('Работа');
      for (final id in <String>['e1', 'e2', 'e3', 'e4', 'e5']) {
        await seedEvent(id: id, categoryId: work.id, category: 'Работа');
      }

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию'));
      await tester.pumpAndSettle();

      expect(find.textContaining('У 5 событий'), findsOneWidget);
    });

    testWidgets('неиспользуемая категория говорит об этом прямо',
        (tester) async {
      await seedCategory('Пустая');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию'));
      await tester.pumpAndSettle();

      expect(
        find.text('Категория «Пустая» не используется ни одним событием.'),
        findsOneWidget,
      );
    });

    testWidgets('«Отмена» ничего не удаляет', (tester) async {
      final work = await seedCategory('Работа');
      await seedEvent(id: 'e1', categoryId: work.id, category: 'Работа');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(await categories.getById(work.id), isNotNull);
      expect((await events.getAll()).single.categoryId, work.id);
    });

    testWidgets('после удаления порядок остаётся плотным', (tester) async {
      await seedCategory('Первая');
      await seedCategory('Вторая');
      await seedCategory('Третья');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить категорию').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      final remaining = await categories.getAll();
      expect(remaining.map((c) => c.name), <String>['Вторая', 'Третья']);
      expect(remaining.map((c) => c.order), <int>[0, 1]);
    });
  });

  group('Порядок', () {
    testWidgets('перетаскивание сохраняет новый порядок', (tester) async {
      await seedCategory('Первая');
      await seedCategory('Вторая');
      await seedCategory('Третья');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      // Перетаскивание пошаговое: ReorderableListView отслеживает
      // движение указателя между кадрами, и одним teleport-сдвигом
      // список не переставил бы.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var step = 0; step < 4; step++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      final all = await categories.getAll();
      expect(all.first.name, 'Вторая');
      expect(all.map((c) => c.order), <int>[0, 1, 2]);
    });
  });
}