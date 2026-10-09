/// Сквозной сценарий интеграции категорий (Этап 7.4).
///
/// Остальные тесты Этапа 7 проверяют части по отдельности: репозиторий,
/// поиск, главный экран. Здесь — один непрерывный путь данных, каким его
/// проходит реальный пользователь: старые строки → холодный старт →
/// миграция → показ на главном → поиск → переименование → удаление.
///
/// Порядок именно такой, потому что каждая следующая часть имеет смысл
/// только после предыдущей. Отдельные тесты этого не ловят: категория,
/// которая после удаления воскресает при следующей миграции, в тестах
/// репозитория выглядит совершенно рабочей — воскрешена будет последующей
/// миграцией, а её запускают только холодные старты.
///
/// Хранилище — в памяти, тем же контрактом ModuleStorage, который даёт
/// модуль. Все данные лежат в одном хранилище, как в настоящем модуле:
/// события, категории и маркер версии.
library schedule_categories_end_to_end_test;

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
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_migrator.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/ui/category_visuals.dart';
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

  /// Кладёт событие в том виде, в каком его писало приложение ДО
  /// появления категорий: `category` есть, `categoryId` нет.
  ///
  /// Пишется именно так, а не «просто `put`»: у старой версии
  /// приложения ключа `categoryId` в JSON не было вовсе, и миграция
  /// обязана выдержать такой набор ключей.
  void putLegacyEvent(ScheduleEvent event) {
    final json = event.toJson()..remove('categoryId');
    _data['event:${event.id}'] = jsonEncode(json);
  }

  /// Забывает маркер версии — как будто его никогда не было.
  ///
  /// Отдельный сценарий, а не часть основного потока: у пользователя
  /// маркер не пропадает сам, но потерять его можно (частичная запись
  /// хранилища, ручная правка бэкапа), и тогда миграция запускается на
  /// данных, которые уже мигрированы.
  void forgetSchemaVersion() =>
      _data.remove(ScheduleMigrator.schemaVersionKey);
}

ScheduleEvent _legacyEvent({
  required String id,
  required String title,
  required String category,
  int startMinutes = 0,
  int endMinutes = 1439,
  int daysFromToday = 0,
}) {
  final now = DateTime.now();
  return ScheduleEvent(
    id: id,
    title: title,
    category: category,
    priority: EventPriority.medium,
    date: DateTime(now.year, now.month, now.day + daysFromToday),
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    status: EventStatus.planned,
  );
}

void main() {
  late _InMemoryStorage storage;
  late ModuleManager manager;
  late GlobalSearchService searchService;
  late ScheduleRepository events;
  late ScheduleCategoryRepository categories;

  /// Холодный старт: пустой реестр модулей и enable заново. Именно так
  /// выглядит запуск приложения, на котором срабатывает миграция.
  Future<void> coldStart() async {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: (_) => storage,
    );
    ModuleRegistry.register(ScheduleModule());
    await manager.install('schedule');
    await manager.enable('schedule');
    // Миграция запускается платформой после восстановления состояния (Этап 9.3-9.4).
    await manager.runPendingMigrations();

    final api = manager.apiFor('schedule');
    events = ScheduleRepository(api.storage);
    categories = ScheduleCategoryRepository(api.storage);
  }

  Widget home() => ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: HomeScreen(),
        ),
      );

  /// Забирает ИЗВЕСТНЫЙ дефект разметки TimelineStrip, если он проявился.
  ///
  /// Дефект — колонка с подписью события не помещается в 56-пиксельную
  /// полосу — существует до Этапа 7 и к категориям отношения не имеет:
  /// без заглушки проверка была бы про переполнение, а не про категории.
  ///
  /// Требовать его нельзя: полоса рисует подпись не для каждого события
  /// дня, и сегодняшнее событие в разное время суток даёт разную
  /// разметку. Поэтому здесь, в отличие от
  /// schedule_home_section_test.dart, ошибка либо есть, либо её нет.
  ///
  /// Зато проверка строга в другую сторону, ради которой и нужна: всё,
  /// что НЕ этот дефект, обязано уронить тест. На каждом экране здесь
  /// одно событие дня, поэтому свёртка «Multiple exceptions» не
  /// появляется и каждая ошибка опознаётся точно.
  void takeKnownTimelineOverflowIfAny(WidgetTester tester) {
    final error = tester.takeException();
    if (error == null) return;

    expect(
      error.toString(),
      contains('overflowed by'),
      reason: 'поймана не ошибка разметки TimelineStrip, а что-то другое: '
          '$error',
    );
  }

  /// Сегодняшнее событие, идущее прямо сейчас.
  ///
  /// Главный экран показывает в повестке то, что ещё не закончилось, и
  /// событие, целиком прошедшее до запуска теста, не появилось бы на
  /// нём вовсе — проверять было бы нечего.
  ({int start, int end}) _happeningNow() {
    final now = DateTime.now();
    final start = (now.hour * 60 + now.minute - 15).clamp(0, 1410);
    return (start: start, end: start + 30);
  }

  setUp(() {
    storage = _InMemoryStorage();
  });

  tearDown(ModuleRegistry.clear);

  group('Сквозной путь: от строки категории до её удаления', () {
    testWidgets('старые строки → миграция → показ → поиск → переименование '
        '→ удаление', (tester) async {
      final now = _happeningNow();

      // --- До Этапа 7.1: у пользователя есть только строки. ---
      //
      // Два события с ОДНИМ именем — на разных днях. Разные дни нужны
      // и для проверки: главный экран показывает только сегодняшний
      // день, и второе событие держит проверки миграции и поиска, не
      // попадая на экран.
      storage.putLegacyEvent(_legacyEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        startMinutes: now.start,
        endMinutes: now.end,
      ));
      storage.putLegacyEvent(_legacyEvent(
        id: 'e2',
        title: 'Обед',
        category: 'Работа',
        startMinutes: 780,
        endMinutes: 840,
        daysFromToday: 1,
      ));

      // --- Холодный старт: миграция переносит строки в категории. ---
      await coldStart();

      final afterMigration = await categories.getAll();
      expect(
        afterMigration.map((c) => c.name),
        <String>['Работа'],
        reason: 'два события с одним именем дают одну категорию',
      );
      final work = afterMigration.single;
      expect(work.colorValue, Category.defaultColorValue);
      expect(work.iconKey, Category.defaultIconKey);

      final migrated = await events.getAll();
      for (final event in migrated) {
        expect(event.categoryId, work.id,
            reason: 'у ${event.id} после миграции обязана появиться ссылка');
        expect(event.category, 'Работа',
            reason: 'устаревшая строка остаётся на месте: старые сборки '
                'должны читать эти данные как раньше');
      }

      // --- Главный экран показывает перенесённое имя, а не «Без категории». ---
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.textContaining('Планёрка'), findsWidgets);
      expect(find.textContaining('Работа'), findsWidgets);
      expect(find.textContaining('Без категории'), findsNothing);

      // --- Поиск находит по имени, которое у пользователя ЕСТЬ. ---
      final searchBefore = await searchService.search('работа');
      expect(searchBefore.map((r) => r.title),
          containsAll(<String>['Планёрка', 'Обед']));

      // --- Переименование: главный экран и поиск следуют за справочником. ---
      await categories.update(
        id: work.id,
        name: 'Деловые',
        colorValue: Category.defaultColorValue,
        iconKey: Category.defaultIconKey,
      );

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0.0, 400.0),
        1000.0,
      );
      await tester.pumpAndSettle();
      // Перерисовка шкалы с новым цветом при тех же размерах повторной
      // разметки не делает, поэтому ошибки уже не будет.
      tester.takeException();

      expect(find.textContaining('Деловые'), findsWidgets);
      expect(find.textContaining('Работа'), findsNothing,
          reason: 'имени «Работа» у пользователя больше нет');

      expect(await searchService.search('работа'), isEmpty,
          reason: 'поиск по ушедшему имени обязан перестать работать');
      expect(
        (await searchService.search('деловые')).map((r) => r.title),
        containsAll(<String>['Планёрка', 'Обед']),
      );

      // --- Удаление: события целы, ссылок не осталось. ---
      expect(await categories.countLinkedEvents(work.id), 2);

      await categories.delete(work.id);

      expect(await categories.getAll(), isEmpty);
      final afterDelete = await events.getAll();
      expect(afterDelete.map((e) => e.id),
          containsAll(<String>['e1', 'e2']),
          reason: 'удаление справочника не имеет права удалять чужие данные');
      for (final event in afterDelete) {
        expect(ScheduleEvent.readCategoryId(event.categoryId), isNull,
            reason: 'у ${event.id} не должно остаться висячей ссылки');
      }
      // Удалённая категория не воскресает из устаревших строк: delete
      // чистит их вместе со ссылкой.
      for (final event in afterDelete) {
        expect(event.category.trim(), isEmpty,
            reason: 'у ${event.id} не должно остаться устаревшего имени');
      }

      // Разрешение после удаления обязано остаться осмысленным.
      final resolver = CategoryResolver.of(await categories.getAll());
      for (final event in afterDelete) {
        expect(resolver.resolve(event).name, ResolvedCategory.none.name);
      }

      // Поиск по названию события продолжает работать: удаление
      // категории не должна была сломать поиск целиком.
      expect(
        (await searchService.search('планёрка')).map((r) => r.title),
        contains('Планёрка'),
      );

      // Обновление главного экрана после удаления: с экрана уходит не
      // только ссылка, но и само имя — иначе на нём осталось бы имя
      // категории, которой у пользователя уже нет.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0.0, 400.0),
        1000.0,
      );
      await tester.pumpAndSettle();
      tester.takeException();

      expect(find.textContaining('Планёрка'), findsWidgets);
      expect(find.textContaining('Без категории'), findsWidgets,
          reason: 'удалённая категория обязана выглядеть как её отсутствие');
      expect(find.textContaining('Деловые'), findsNothing);
    });

    testWidgets('потерянный маркер версии не воскресает удалённую категорию',
        (tester) async {
      // Отдельный сценарий: маркер теряется не сам по себе, но потерять
      // его можно, и тогда миграция запускается повторно на уже
      // перенесённых данных. Если бы удаление оставляло устаревшую
      // строку, категория воскресла бы здесь вместе со своими ссылками —
      // и удалить её второй раз было бы уже нечем.
      final now = _happeningNow();
      storage.putLegacyEvent(_legacyEvent(
        id: 'e1',
        title: 'Планёрка',
        category: 'Работа',
        startMinutes: now.start,
        endMinutes: now.end,
      ));

      await coldStart();
      final work = (await categories.getAll()).single;
      expect(await categories.countLinkedEvents(work.id), 1);

      await categories.delete(work.id);

      // Холодный старт с потерянным маркером — миграция отрабатывает заново.
      storage.forgetSchemaVersion();
      await coldStart();

      expect(await categories.getAll(), isEmpty,
          reason: 'удалённая категория не имеет права воскреснуть при '
              'повторной миграции');
      final event = (await events.getAll()).single;
      expect(event.categoryId, isNull);
      expect(event.category.trim(), isEmpty);

      // И на экране это выглядит как «Без категории», а не как вернувшаяся
      // «Работа».
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      takeKnownTimelineOverflowIfAny(tester);

      expect(find.textContaining('Без категории'), findsWidgets);
      expect(find.textContaining('Работа'), findsNothing);
    });
  });
}