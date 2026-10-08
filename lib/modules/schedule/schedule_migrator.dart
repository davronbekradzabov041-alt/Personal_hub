import '../../core/modules/module_data_migration.dart';
import '../../core/modules/module_migration_planner.dart';
import '../../core/modules/module_migration_runner.dart';
import '../../core/modules/module_schema_marker.dart';
import '../../core/modules/module_storage.dart';
import 'models/category.dart';
import 'models/schedule_event.dart';
import 'schedule_category_repository.dart';
import 'schedule_repository.dart';

/// Переносит старые строковые категории событий в настоящие Category
/// (Этап 7.2).
///
/// ## Что именно чинится
///
/// До Этапа 7.1 у события была только строка [ScheduleEvent.category],
/// введённая пользователем от руки. Этап 7.1 добавил
/// [ScheduleEvent.categoryId] — ссылку на категорию, но НЕ перенёс
/// старые данные: событие, сохранённое до 7.1, читается с
/// `categoryId == null`, и его категория существует только как текст.
///
/// Миграция превращает этот текст в полноценные категории: создаёт
/// недостающие `category:<id>` и проставляет событиям ссылки.
///
/// ## Отношение к Migration System (Этап 9.1)
///
/// Ключ `schema:version` и его разбор принадлежат теперь платформе
/// ([ModuleSchemaMarker]), а не этому файлу: иначе у модуля и у
/// платформы было бы по владельцу одного и того же маркера, и они
/// разошлись бы при первом же нестандартном значении.
///
/// [schemaVersionKey] и [currentSchemaVersion] оставлены как
/// тонкие ссылки на платформенные константы, потому что на них
/// завязаны существующие тесты Schedule; владения у них больше нет.
///
/// Сам перенос вынесен в [ScheduleCategoriesMigration] —
/// обычный шаг [ModuleDataMigration]. Это не переименование ради
/// единообразия: шаг и его маркер — разные вещи. Шаг преобразует
/// данные, а версию записывает вызывающий ([ModuleSchemaMarker.write]
/// ниже), и именно поэтому прерванный на полпути перенос не может
/// выглядеть как завершённый.
///
/// ## Почему версия, а не «посмотрел и ничего не сделал»
///
/// Пока маркера нет, работа считается незавершённой и будет повторена.
/// Маркер пишется ПОСЛЕДНИМ: обратный порядок опаснее — запись
/// маркера перед переносом превратила бы прерванную миграцию в
/// «успешно завершённую» навсегда.
///
/// ## Идемпотентность
///
/// Повторный запуск на перенесённых данных не меняет ничего: категории
/// сопоставляются по [Category.nameKey] (регистр и края пробелов не
/// различаются) и переиспользуются, а события с уже проставленной
/// ссылкой не переписываются. Поэтому даже полная потеря маркера
/// (старый бэкап, ручное редактирование хранилища) даёт тот же
/// результат — ни дублей категорий, ни новых id.
///
/// Старая строка [ScheduleEvent.category] при этом НЕ очищается. Она
/// больше не источник правды, но остаётся запасным значением для
/// сборок без `categoryId` и для чтения старых бэкапов. Плата за это
/// известна и учтена в [ScheduleCategoryRepository.delete]: удаление
/// категории обязано очищать строку у её событий, иначе миграция без
/// маркера воскресила бы удалённую категорию.
class ScheduleMigrator {
  ScheduleMigrator(
    this._storage, {
    ScheduleRepository? eventRepository,
    ScheduleCategoryRepository? categoryRepository,
  })  : _eventRepository = eventRepository,
        _categoryRepository = categoryRepository;

  /// Ключ маркера версии данных модуля.
  ///
  /// Ссылка на платформенный [ModuleSchemaMarker.key], а не
  /// собственный литерал: маркер один на всё приложение, и место,
  /// где он назван, должно быть одно.
  static const String schemaVersionKey = ModuleSchemaMarker.key;

  /// Текущая версия схемы данных Schedule.
  ///
  /// Число, а не строка, и не вычисляется из имени файла: версия
  /// данных — целое число, и разбором строки занимается платформа
  /// (ModuleSchemaMarker). Значение '2' означает ровно то же, что
  /// значило раньше: данные после Этапа 7.2, с настоящими
  /// категориями и ссылками на них.
  static const int currentSchemaVersion = 2;

  final ModuleStorage _storage;

  /// Кэшируются в [_eventRepository] / [_categoryRepository] при первом
  /// обращении, поэтому повторные [run] не создают новые репозитории.
  ScheduleRepository? _eventRepository;
  ScheduleCategoryRepository? _categoryRepository;

  // Ленивое создание с кэшированием: иначе на каждый вызов
  // _categories читался бы заново, а тестам с внедрёнными
  // репозиториями пришлось бы держать два источника правды.
  ScheduleRepository get _events =>
      _eventRepository ??= ScheduleRepository(_storage);

  ScheduleCategoryRepository get _categories =>
      _categoryRepository ??= ScheduleCategoryRepository(_storage);

  /// Выполняет перенос, если он ещё не выполнялся.
  ///
  /// Исключения НЕ перехватываются: вызывающий (ScheduleModule.onInstall)
  /// обязан решить, что делать с неудачей, и это решение не должно
  /// молча прятаться внутри мигратора. Побочный эффект такого
  /// подхода — частично перенесённые данные остаются в хранилище, но
  /// маркер не записан, поэтому следующий запуск продолжит работу с
  /// того же места.
  Future<ScheduleMigrationResult> run() async {
    final stored = await ModuleSchemaMarker.read(_storage);
    if (stored == currentSchemaVersion) {
      return ScheduleMigrationResult(previousVersion: '$stored');
    }

    final migration = ScheduleCategoriesMigration(
      eventRepository: _events,
      categoryRepository: _categories,
    );

    final plan = const ModuleMigrationPlanner().plan(
      currentSchemaVersion: stored,
      targetSchemaVersion: currentSchemaVersion,
      migrations: <ModuleDataMigration>[migration],
    );

    final result = await const ModuleMigrationRunner().run(
      plan: plan,
      storage: _storage,
    );

    return ScheduleMigrationResult(
      previousVersion: '$stored',
      ran: result.executedSteps > 0,
      createdCategories: migration.createdCategories,
      linkedEvents: migration.linkedEvents,
      detachedEvents: migration.detachedEvents,
    );
  }
}

/// Один шаг переноса данных Schedule: строковые категории → Category.
///
/// Объявлен [ModuleDataMigration], чтобы был ровно один владелец
/// маркера (платформа) и один формат шага для всех модулей. Сам шаг
/// маркер не пишет: [ModuleDataMigration.run] этого и не должен
/// делать, решение о версии принимает вызыващий.
class ScheduleCategoriesMigration implements ModuleDataMigration {
  ScheduleCategoriesMigration({
    ScheduleRepository? eventRepository,
    ScheduleCategoryRepository? categoryRepository,
  })  : _eventRepository = eventRepository,
        _categoryRepository = categoryRepository;

  /// Данные до Этапа 7.2: у события есть только строка категории.
  @override
  int get fromVersion => 1;

  /// Данные после Этапа 7.2: настоящие Category и ссылка categoryId.
  @override
  int get toVersion => ScheduleMigrator.currentSchemaVersion;

  /// Сколько категорий создано из старых строковых имён.
  int createdCategories = 0;

  /// Сколько событий получило ссылку.
  int linkedEvents = 0;

  /// Сколько висячих ссылок снято (восстановить их было нечем).
  int detachedEvents = 0;

  ScheduleRepository? _eventRepository;
  ScheduleCategoryRepository? _categoryRepository;

  ModuleStorage? _storage;

  ScheduleRepository get _events =>
      _eventRepository ??= ScheduleRepository(_requireStorage());

  ScheduleCategoryRepository get _categories =>
      _categoryRepository ??= ScheduleCategoryRepository(_requireStorage());

  ModuleStorage _requireStorage() {
    final storage = _storage;
    if (storage == null) {
      throw StateError(
        'ScheduleCategoriesMigration.run() не вызывался — репозитории '
        'неизвестны. Передайте их в конструктор или вызовите run().',
      );
    }
    return storage;
  }

  @override
  Future<void> run(ModuleStorage storage) async {
    _storage = storage;

    final events = await _readEventsInStableOrder();

    // Существующие категории — источник правды по тому, что уже есть.
    // Ключ индекса — nameKey, а не id: сопоставлять надо то, что видит
    // пользователь.
    final existing = await _categories.getAll();
    final existingIds = <String>{
      for (final category in existing) category.id,
    };
    final byName = <String, Category>{};
    for (final category in existing) {
      byName.putIfAbsent(Category.nameKey(category.name), () => category);
    }

    var created = 0;
    var linked = 0;
    var detached = 0;

    // Шаг 1. Собрать имена в порядке первого появления и создать
    // недостающие категории.
    //
    // Сначала создание, потом простановка ссылок — так событие никогда
    // не ссылается на ещё не существующую категорию, даже если
    // миграция оборвётся на середине.
    for (final event in events) {
      final link = ScheduleEvent.readCategoryId(event.categoryId);
      // Валидная ссылка — событие уже перенесено, его имя не создаёт
      // новую категорию. Висячая ссылка (id есть, категории нет) —
      // наоборот, подлежит переносу заново.
      if (link != null && existingIds.contains(link)) continue;

      final name = _legacyNameOf(event);
      if (name == null) continue;

      final key = Category.nameKey(name);
      if (byName.containsKey(key)) continue;

      final category = await _categories.create(
        name: name,
        colorValue: Category.defaultColorValue,
        iconKey: Category.defaultIconKey,
      );
      byName[key] = category;
      existingIds.add(category.id);
      created++;
    }

    // Шаг 2. Проставить ссылки событиям.
    for (final event in events) {
      final link = ScheduleEvent.readCategoryId(event.categoryId);
      final dangling = link != null && !existingIds.contains(link);
      if (link != null && !dangling) continue;

      final name = _legacyNameOf(event);
      final target = name == null ? null : byName[Category.nameKey(name)];

      if (target == null) {
        // Висячая ссылка, восстановить которую нечем: имени нет и
        // категории с таким id нет. Оставить её значило бы сохранить
        // ссылку, которая не разрешится никогда, — снимаем, и событие
        // честно становится «без категории».
        if (dangling) {
          await _events.update(event.copyWith(categoryId: null));
          detached++;
        }
        continue;
      }

      if (link == target.id) continue;
      await _events.update(event.copyWith(categoryId: target.id));
      linked++;
    }

    // Шаг 3. Плотный порядок категорий 0..n-1.
    //
    // create() уже добавляет в конец, но разрывы и дубли могут прийти
    // из данных, собранных до миграции. Порядок при этом
    // сохраняется: перенумерация меняет только числа, не перестановку.
    final ordered = await _categories.getAll();
    await _categories.reorder(<String>[
      for (final category in ordered) category.id,
    ]);

    // Счётчики заполняются только после того, как все шаги прошли:
    // частично выполненный перенос не должен выглядеть как завершённый
    // даже в отчёте.
    createdCategories = created;
    linkedEvents = linked;
    detachedEvents = detached;
  }

  /// События в стабильном порядке: дата, время начала, id.
  ///
  /// [ScheduleRepository.getAll] сортирует по дате и времени, но не
  /// добавляет id как последний ключ, а `List.sort` не гарантирует
  /// стабильность. Для миграции этого мало: порядок первого появления
  /// имени задаёт `order` создаваемых категорий, и результат обязан
  /// быть воспроизводимым — иначе два одинаковых хранилища дали бы
  /// разные категории в разном порядке.
  Future<List<ScheduleEvent>> _readEventsInStableOrder() async {
    final events = await _events.getAll();
    events.sort((a, b) {
      final byDate = a.dateKey.compareTo(b.dateKey);
      if (byDate != 0) return byDate;
      final byStart = a.startMinutes.compareTo(b.startMinutes);
      if (byStart != 0) return byStart;
      return a.id.compareTo(b.id);
    });
    return events;
  }

  /// Устаревшее имя категории события; null, если переносить нечего.
  static String? _legacyNameOf(ScheduleEvent event) {
    final trimmed = event.category.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Итог одной попытки переноса.
///
/// Не типизированный union в духе `Either` и не void: вызывающему
/// нужно знать, что перенос вообще не запускался (маркер на месте)
/// и что именно он изменил, чтобы написать об этом в лог, не
/// разбирая хранилище заново.
class ScheduleMigrationResult {
  const ScheduleMigrationResult({
    required this.previousVersion,
    this.ran = false,
    this.createdCategories = 0,
    this.linkedEvents = 0,
    this.detachedEvents = 0,
  });

  /// Что лежало в маркере до запуска; '1' — миграция не выполнялась
  /// никогда (свежая установка либо данные из сборки до Этапа 7.1,
  /// где маркера не было вовсе).
  final String? previousVersion;

  /// false — данные уже этой версии, запись не трогали.
  final bool ran;

  /// Сколько категорий создано из старых строковых имён.
  final int createdCategories;

  /// Сколько событий получило ссылку.
  final int linkedEvents;

  /// Сколько висячих ссылок снято (восстановить их было нечем).
  final int detachedEvents;
}