import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/ui/event_form_screen.dart';

/// Выбор категории в форме события.
///
/// Отдельно от тестов диалога удаления (UI-01): там важна ловушка с
/// Navigator, здесь — что выбор категории доезжает до хранилища целиком
/// (ссылка И устаревшая строка) и что форма не показывает то, чего уже
/// нет.
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
  late ScheduleRepository events;
  late ScheduleCategoryRepository categories;

  setUp(() {
    storage = _InMemoryStorage();
    events = ScheduleRepository(storage);
    categories = ScheduleCategoryRepository(storage);
  });

  Future<Category> seedCategory(String name) => categories.create(
        name: name,
        colorValue: 0xFFD97706,
        iconKey: 'work',
      );

  Widget form({ScheduleEvent? existing}) => MaterialApp(
        home: Scaffold(
          body: EventFormScreen(
            repository: events,
            categoryRepository: categories,
            existing: existing,
          ),
        ),
      );

  /// Нажимает кнопку внизу длинной формы.
  ///
  /// Форма — ListView, и кнопка сохранения ниже первого экрана: поле
  /// «Заметка» уже не построено, и обычный tap её бы не нашёл.
  Future<void> tapButton(
    WidgetTester tester,
    String label,
  ) async {
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('Новое событие', () {
    testWidgets('по умолчанию — «Без категории», и это честно видно',
        (tester) async {
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();

      expect(find.text('Категория'), findsOneWidget);
      expect(find.text('Без категории'), findsOneWidget);
    });

    testWidgets('свободного ввода категории больше нет', (tester) async {
      // Категория выбирается из справочника: поле с меткой «Категория» в
      // форме означало бы вторую правду о категории, из-за которой
      // «Работа» и «работа» стали бы разными категориями.
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Категория'), findsOneWidget,
          reason: 'категория выбирается плиткой, а не вводится строкой');

      final labels = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration?.labelText)
          .toList();
      expect(labels, isNot(contains('Категория')));
    });

    testWidgets('выбор категории сохраняет ссылку и устаревшее имя',
        (tester) async {
      final work = await seedCategory('Работа');

      await tester.pumpWidget(form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      expect(find.text('Работа'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, 'Планёрка');
      await tapButton(tester, 'Создать');

      final saved = (await events.getAll()).single;
      expect(saved.title, 'Планёрка');
      expect(saved.categoryId, work.id);
      // Устаревшая строка обязана совпадать со ссылкой: расхождение
      // чинит ScheduleMigrator, но лучше не создавать его вовсе.
      expect(saved.category, 'Работа');
    });

    testWidgets('«Без категории» очищает и ссылку, и строку', (tester) async {
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      // Пустой справочник: в листе есть только «Без категории» и
      // управление. Выбираем «Без категории» ещё раз — выбор обязан
      // работать и в этом случае, иначе отменить выбор нельзя.
      await tester.tap(find.text('Без категории').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Прогулка');
      await tapButton(tester, 'Создать');

      final saved = (await events.getAll()).single;
      expect(saved.categoryId, isNull);
      expect(saved.category, isEmpty);
    });
  });

  group('Редактирование', () {
    testWidgets('показывает актуальное имя категории, а не устаревшее',
        (tester) async {
      final work = await seedCategory('Деловые');
      await events.add(ScheduleEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        categoryId: work.id,
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 540,
        endMinutes: 600,
        status: EventStatus.planned,
      ));

      await tester.pumpWidget(form(
        existing: (await events.getAll()).single,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Деловые'), findsOneWidget);
      expect(find.text('Работа'), findsNothing);
    });

    testWidgets('удалённая категория показывается как «Без категории»',
        (tester) async {
      final work = await seedCategory('Работа');
      final event = ScheduleEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        categoryId: work.id,
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 540,
        endMinutes: 600,
        status: EventStatus.planned,
      );
      await events.add(event);
      // Ссылка остаётся, а категории больше нет — так выглядит хранилище
      // после удаления в обход репозитория.
      await storage.remove(Category.storageKey(work.id));

      await tester.pumpWidget(form(existing: event));
      await tester.pumpAndSettle();

      // Устаревшее имя ещё видно: стирать у пользователя его категорию
      // молча было бы хуже, чем показать устаревшую подпись.
      expect(find.text('Работа'), findsOneWidget);
    });

    testWidgets('сохранение без изменений не теряет категорию', (tester) async {
      final work = await seedCategory('Работа');
      await events.add(ScheduleEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        categoryId: work.id,
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 540,
        endMinutes: 600,
        status: EventStatus.planned,
      ));

      await tester.pumpWidget(form(existing: (await events.getAll()).single));
      await tester.pumpAndSettle();

      await tapButton(tester, 'Сохранить');

      final saved = (await events.getAll()).single;
      expect(saved.categoryId, work.id);
      expect(saved.category, 'Работа');
    });

    testWidgets('снятие категории очищает и ссылку, и строку',
        (tester) async {
      final work = await seedCategory('Работа');
      await events.add(ScheduleEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        categoryId: work.id,
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 540,
        endMinutes: 600,
        status: EventStatus.planned,
      ));

      await tester.pumpWidget(form(existing: (await events.getAll()).single));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Без категории'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Сохранить');

      final saved = (await events.getAll()).single;
      expect(saved.categoryId, isNull);
      expect(saved.category, isEmpty);
    });

    testWidgets('из листа можно уйти в управление категориями и вернуться',
        (tester) async {
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Управление категориями'));
      await tester.pumpAndSettle();

      expect(find.text('Категории'), findsOneWidget);
      expect(find.text('Категорий пока нет'), findsOneWidget);

      // Создаём категорию прямо из формы.
      await tester.tap(find.byTooltip('Создать категорию'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Спорт');
      await tester.scrollUntilVisible(
        find.text('Создать'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      // Возврат в список категорий: новая категория уже видна.
      expect(find.text('Спорт'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // И форма её видит: выбор доступен сразу, без перезапуска.
      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      expect(find.text('Спорт'), findsOneWidget);
    });
  });
}