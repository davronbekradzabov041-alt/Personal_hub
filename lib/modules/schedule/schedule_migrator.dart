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
/// ## Почему версия, а не «посмотрел и ничего не сделал»
///
/// [schemaVersionKey] — маркер версии данных модуля. Без него
/// миграция запускалась бы на каждом холодном старте и каждой новой
/// категории пришлось бы заново доказывать, что она уже перенесена.
/// Маркер пишется ПОСЛЕДНИМ: пока его нет, работа считается
/// незавершённой и будет повторена. Обратный порядок опаснее — запись
/// маркера перед миграцией превратила бы прерванную на полпути
/// миграцию в «успешно завершённую» навсегда.
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
  /// Префикс `schema:` выбран потому, что по нему сразу видно, что
  /// ключ не принадлежит ни событиям, ни категориям: `keys()`
  /// возвращает общие ключи модуля, и служебная запись не должна
  /// выглядеть как часть данных.
  static const String schemaVersionKey = 'schema:version';

  /// Текущая версия схемы данных Schedule.
  ///
  /// Строка, а не число: [ModuleStorage] хранит строки, и сравнение
  /// при чтении не должно зависеть от того, удалит ли кто-то
  /// нечисловую запись. Повышается только этим числом.
  static const String currentSchemaVersion = '2';

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

  /// Выполняет миграцию, если она ещё не выполнялась.
  ///
  /// Исключения НЕ перехватываются: вызывающий (ScheduleModule.onInstall)
  /// обязан решить, что делать с неудачей, и это решение не должно
  /// молча прятаться внутри мигратора. Побочный эффект такого
  /// подхода — частично перенесённые данные остаются в хранилище, но
  /// маркер не записан, поэтому следующий запуск продолжит работу с
  /// того же места.
  Future<ScheduleMigrationResult> run() async {
    final stored = (await _storage.getString(schemaVersionKey))?.trim();
    if (stored == currentSchemaVersion) {
      return ScheduleMigrationResult(previousVersion: stored);
    }

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

    var createdCategories = 0;
    var linkedEvents = 0;
    var detachedEvents = 0;

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
      createdCategories++;
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
          detachedEvents++;
        }
        continue;
      }

      if (link == target.id) continue;
      await _events.update(event.copyWith(categoryId: target.id));
      linkedEvents++;
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

    // Шаг 4. Маркер версии — последним, и только когда всё остальное
    // уже записано.
    await _storage.setString(schemaVersionKey, currentSchemaVersion);

    return ScheduleMigrationResult(
      previousVersion: stored,
      ran: true,
      createdCategories: createdCategories,
      linkedEvents: linkedEvents,
      detachedEvents: detachedEvents,
    );
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

/// Итог одной попытки миграции.
///
/// Не типизированный union в духе `Either` и не void: вызывающему
/// нужно знать, что миграция вообще не запускалась (маркер на месте)
/// и что именно она изменила, чтобы написать об этом в лог, не
/// разбирая хранилище заново.
class ScheduleMigrationResult {
  const ScheduleMigrationResult({
    required this.previousVersion,
    this.ran = false,
    this.createdCategories = 0,
    this.linkedEvents = 0,
    this.detachedEvents = 0,
  });

  /// Что лежало в маркере до запуска; null — миграция не выполнялась
  /// никогда (свежая установка либо данные из сборки до Этапа 7.1).
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