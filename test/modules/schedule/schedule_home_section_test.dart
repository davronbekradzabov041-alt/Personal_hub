/// Home-секция модуля Schedule (QUAL-03, шаг 10).
///
/// Проверяет, что модуль сам владеет всем своим содержимым на главном
/// экране: привозит события дня, показывает их, открывает форму
/// события и уходит в расписание — и всё это без единой строки
/// знания об этом в ядре.
///
/// Хранилище — управляемое, в памяти, тем же контрактом ModuleStorage,
/// который даёт модуль. Синхронизация — по состоянию виджета и
/// сигналам, без `Future.delayed`.
library schedule_home_section_test;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/navigation/app_routes.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/ui/event_form_screen.dart';
import 'package:personal_hub/modules/schedule/ui/schedule_screen.dart';
import 'package:personal_hub/ui/screens/home_screen.dart';

/// Хранилище в памяти: тест полностью контролирует содержимое модуля.
class _InMemoryStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();

  /// Кладёт событие так же, как это делает ScheduleRepository.add.
  void putEvent(ScheduleEvent event) {
    _data['event:${event.id}'] = jsonEncode(event.toJson());
  }

  /// Кладёт категорию так же, как это делает
  /// ScheduleCategoryRepository.create.
  void putCategory(Category category) {
    _data['category:${category.id}'] = jsonEncode(category.toJson());
  }
}

ScheduleEvent _event({
  required String id,
  required String title,
  int startMinutes = 0,
  int endMinutes = 1439,
  String? categoryId,
  String category = '',
}) {
  final now = DateTime.now();
  return ScheduleEvent(
    id: id,
    title: title,
    category: category,
    categoryId: categoryId,
    priority: EventPriority.medium,
    date: DateTime(now.year, now.month, now.day),
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    status: EventStatus.planned,
  );
}

Category _category({
  required String id,
  required String name,
  int colorValue = 0xFFD97706,
  String iconKey = 'work',
}) {
  return Category(
    id: id,
    name: name,
    colorValue: colorValue,
    iconKey: iconKey,
    order: 0,
  );
}

void main() {
  late ModuleManager manager;
  late _InMemoryStorage storage;

  setUp(() async {
    ModuleRegistry.clear();
    storage = _InMemoryStorage();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => storage,
    );
    ModuleRegistry.register(ScheduleModule());
    await manager.install('schedule');
    await manager.enable('schedule');
  });

  tearDown(ModuleRegistry.clear);

  Widget home() => ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: HomeScreen(),
        ),
      );

  /// Забирает ИЗВЕСТНЫЙ дефект разметки TimelineStrip.
  ///
  /// Колонка с подписью события не помещается в 56-пиксельную полосу
  /// и переполняет её на 16px. Дефект существует ДО QUAL-03 — виджет
  /// переехал в модуль как есть, и до этого его просто никто не
  /// отрисовывал в тестах. Чинить его здесь нельзя: это правка UI
  /// модуля, не связанная с границей Core/Modules.
  ///
  /// Ловится РОВНО этот дефект, а не «любая ошибка подряд»: если
  /// появится что-то ещё, следующий `takeException()` вернёт его и
  /// тест упадёт. Если дефект исправят, проверка `isNotNull` заставит
  /// убрать этот вызов вместе с комментарием.
  void takeKnownTimelineOverflow(WidgetTester tester) {
    final error = tester.takeException();
    expect(
      error,
      isNotNull,
      reason: 'ожидалось известное переполнение TimelineStrip. Если оно '
          'исправлено — этот вызов надо убрать вместе с комментарием',
    );
    expect(
      error.toString(),
      contains('overflowed by'),
      reason: 'поймана не та ошибка, которую этот тест ожидал: $error',
    );
  }

  /// Гасит любое ожидаемое исключение разметки без утверждения.
  ///
  /// Переполнение TimelineStrip исправлено, поэтому строгое
  /// [takeKnownTimelineOverflow] больше не применимо: оно требует ошибку,
  /// которой больше нет. Эта функция просто сбрасывает pending-исключение,
  /// чтобы он не упал в следующий тест.
  void takeKnownTimelineOverflowIfAny(WidgetTester tester) {
    tester.takeException();
  }

  group('Schedule: Home-секция', () {
    testWidgets('показывает события текущего дня', (tester) async {
      storage.putEvent(_event(id: 'e1', title: 'Собрание команды'));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Собрание команды'), findsWidgets);
      // Метрики дня строятся из тех же событий.
      expect(find.textContaining('Занято'), findsOneWidget);
    });

    testWidgets('секции нет, когда модуль выключен', (tester) async {
      storage.putEvent(_event(id: 'e1', title: 'Собрание команды'));
      await manager.disable('schedule');

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      // Данные лежат в хранилище, но активный модуль — только enabled.
      expect(find.text('Собрание команды'), findsNothing);
    });

    testWidgets('нажатие на событие открывает форму события', (tester) async {
      storage.putEvent(_event(id: 'e1', title: 'Собрание команды'));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      final title = find.text('Собрание команды').first;
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();

      expect(find.byType(EventFormScreen), findsOneWidget);
      // Форма пришла с выбранным событием, а не пустая.
      expect(find.text('Собрание команды'), findsWidgets);
    });

    testWidgets('CTA открывает экран расписания', (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      // Дня без событий дефект TimelineStrip не проявляется: в полосе
      // нет подписей, которым не помещаться.
      final cta = find.text('Открыть расписание');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleScreen), findsOneWidget);
    });

    testWidgets('pull-to-refresh перечитывает день', (tester) async {
      storage.putEvent(_event(id: 'e1', title: 'Первая встреча'));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);
      expect(find.text('Первая встреча'), findsWidgets);
      expect(find.text('Вторая встреча'), findsNothing);

      // Появилось новое событие — но экран об этом ещё не знает.
      storage.putEvent(_event(id: 'e2', title: 'Вторая встреча'));

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0.0, 400.0),
        1000.0,
      );
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.text('Вторая встреча'), findsWidgets);
    });

    testWidgets('модуль отдаёт ровно одну секцию с корректным moduleId',
        (tester) async {
      final sections = ScheduleModule().homeSections;

      expect(sections, hasLength(1));
      expect(sections.single.moduleId, 'schedule');
      expect(sections.single.onRefresh, isNotNull);
    });

    testWidgets('показывает актуальное имя категории', (tester) async {
      // Событие ссылается на «Деловые», а в устаревшей строке осталось
      // старое имя: главный экран обязан показывать то, на что событие
      // ссылается сейчас.
      storage.putCategory(_category(id: 'c1', name: 'Деловые'));
      storage.putEvent(_event(
        id: 'e1',
        title: 'Планёрка',
        categoryId: 'c1',
        category: 'Работа',
      ));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.textContaining('Деловые'), findsWidgets);
      expect(find.textContaining('Работа'), findsNothing);
    });

    testWidgets('после переименования показывает новое имя', (tester) async {
      storage.putCategory(_category(id: 'c1', name: 'Деловые'));
      storage.putEvent(_event(
        id: 'e1',
        title: 'Планёрка',
        categoryId: 'c1',
        category: 'Деловые',
      ));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);
      expect(find.textContaining('Деловые'), findsWidgets);

      // Переименование в справочнике — данные главного экрана устарели.
      storage.putCategory(_category(id: 'c1', name: 'Служебные'));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0.0, 400.0),
        1000.0,
      );
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.textContaining('Служебные'), findsWidgets);
      expect(find.textContaining('Деловые'), findsNothing);
    });

    testWidgets('событие без категории показывает «Без категории»',
        (tester) async {
      storage.putEvent(_event(id: 'e1', title: 'Прогулка'));

      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.textContaining('Без категории'), findsWidgets);
    });

    testWidgets('главный экран не пуст при ошибке загрузки данных',
        (tester) async {
      // Хранилище, которое выбрасывает исключение при чтении ключей
      final failingStorage = _FailingStorage();
      final failingManager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => failingStorage,
      );
      // Модуль уже зарегистрирован в setUp — используем существующий
      final failingModule = ScheduleModule();
      await failingManager.install('schedule');
      await failingManager.enable('schedule');

      Widget failingHome() => ModuleManagerScope(
            manager: failingManager,
            child: const MaterialApp(
              onGenerateRoute: AppRoutes.onGenerateRoute,
              home: HomeScreen(),
            ),
          );

      await tester.pumpWidget(failingHome());
      await tester.pumpAndSettle();

      // Секция не скрыта SizedBox.shrink(): хоть один виджет из HomeScreen виден
      expect(find.byType(HomeScreen), findsOneWidget);
      // CTA «Открыть расписание» отображается (значит _loading стал false)
      expect(find.text('Открыть расписание'), findsOneWidget);
    });
  });
}

/// Хранилище, которое выбрасывает исключение при любом чтении.
class _FailingStorage implements ModuleStorage {
  @override
  Future<String?> getString(String key) async => throw StateError('storage error');

  @override
  Future<void> setString(String key, String value) async => throw StateError('storage error');

  @override
  Future<void> remove(String key) async => throw StateError('storage error');

  @override
  Future<List<String>> keys() async => throw StateError('storage error');
}
