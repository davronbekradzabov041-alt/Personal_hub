import 'dart:convert';

import '../../core/modules/module_storage.dart';
import 'models/category.dart';
import 'models/schedule_event.dart';
import 'schedule_repository.dart';

/// Нарушение правил работы с категориями.
///
/// Один тип на все доменные отказы — пустое имя, дубль имени, попытка
/// изменить или удалить несуществующую категорию, некорректный порядок
/// перестановки. Вызывающий (будущий UI, Этап 7.5) разбирает причину по
/// [reason], а не по типу исключения — тот же приём, что в
/// ModuleLifecycleError.
class ScheduleCategoryException implements Exception {
  ScheduleCategoryException(this.reason);

  /// Текст для показа пользователю, без стектрейса.
  final String reason;

  @override
  String toString() => reason;
}

/// Хранилище категорий Schedule.
///
/// Поверх того же ModuleStorage, что и ScheduleRepository: категория —
/// такая же пользовательская запись модуля, как событие, и лежит рядом
/// с ним под ключом `category:<id>`. Ни отдельной Isar-коллекции, ни
/// нового слоя хранения не заводится, и это не упрощение, а требование
/// архитектуры: backup, restore, откат и очистка при uninstall работают
/// по ВСЕМ ключам ModuleStorage (см. ModuleBackupWriter,
/// ModuleStorageSerializer, ModuleStatePersistence), поэтому категории
/// попадают в .pmb/.pbk и откатываются вместе с событиями без единой
/// строки кода в Core и Module Platform.
///
/// Чего репозиторий НЕ делает намеренно:
///
/// * не кэширует между вызовами — так же, как ScheduleRepository.
///   Каждый getAll() читает хранилище, поэтому изменения, сделанные из
///   другой вкладки или восстановлением из backup, видны сразу;
/// * не знает про UI: что показывать, каким цветом и в каком порядке
///   выводить — работа слоя виджетов (см. `ui/category_visuals.dart`).
///   Единственное, что репозиторию про события знать обязано, — как
///   определить «связано ли событие с этой категорией»: без этого
///   удаление оставляло бы висящие ссылки (Этап 7.2);
///
/// * не хранит «системную» категорию «Без категории». Отсутствие
///   категории выражается пустой ссылкой, а не записью: см. Stage 7
///   audit, §11.
class ScheduleCategoryRepository {
  ScheduleCategoryRepository(
    this._storage, {
    int Function()? idGenerator,
    ScheduleRepository? eventRepository,
  })  : _idGenerator = idGenerator ?? _microsecondId,
        _events = eventRepository ?? ScheduleRepository(_storage);

  final ModuleStorage _storage;

  /// Источник id. Внедряется только ради тестов: столкновение id
  /// проверяется в [create], и единственный способ воспроизвести его
  /// детерминированно — подставить генератор (см. ModuleManager,
  /// где storageFactory внедряется ровно для этого).
  final int Function() _idGenerator;

  /// События модуля.
  ///
  /// Нужны не для красоты, а ради одного инварианта: удаление категории
  /// обязано разорвать её ссылки. Пока Category и ScheduleEvent были
  /// независимы, каждый мог забыть про другой; теперь разрыв ссылок —
  /// часть [delete], и вызывающий не может его упустить.
  ///
  /// По умолчанию строится поверх того же хранилища — обе сущности
  /// принадлежат одному модулю. Внедряется только в тестах, которым
  /// нужно подсунуть хранилище, срывающее запись на нужном шаге.
  final ScheduleRepository _events;

  static int _microsecondId() => DateTime.now().microsecondsSinceEpoch;

  /// Префикс ключа категории в ModuleStorage.
  ///
  /// Не пересекается с `event:` у ScheduleRepository — по этому же
  /// префиксу getAll() отличает свои записи от чужих, как и там.
  static const String keyPrefix = 'category:';

  /// Все категории в пользовательском порядке.
  ///
  /// Сортировка по (order, id), а не только по order: если в хранилище
  /// попались одинаковые или битые значения order (рукная правка
  /// backup, частично прерванная миграция), порядок вывода всё равно
  /// остаётся определённым, а не зависит от порядка строк Isar.
  ///
  /// Записи с нечитаемым значением пропускаются, а не роняют чтение:
  /// одна битая категория не должна прятать остальные.
  Future<List<Category>> getAll() async => _readSorted();

  /// Категория по id; null, если такой нет.
  Future<Category?> getById(String id) async {
    final raw = await _storage.getString(Category.storageKey(id));
    return _decode(raw, fallbackId: id);
  }

  /// Категория по имени без учёта регистра и краёв пробелов; null, если
  /// такой нет.
  ///
  /// Нужен UI для показа «уже существует» до попытки сохранения.
  Future<Category?> findByName(String name) async {
    final key = Category.nameKey(name);
    for (final category in await _readSorted()) {
      if (Category.nameKey(category.name) == key) return category;
    }
    return null;
  }

  /// Создаёт категорию в конце списка.
  ///
  /// [order] новой категории равен последнему существующему order плюс
  /// один, а не количеству категорий: при нормальных данных это одно и
  /// то же (плотно `0..n-1`), но на битых данных «добавить в конец»
  /// должно означать конец, а не середину.
  ///
  /// Бросает [ScheduleCategoryException] на пустом имени и на дубле
  /// имени без учёта регистра.
  Future<Category> create({
    required String name,
    required int colorValue,
    required String iconKey,
  }) async {
    final normalizedName = _requireName(name);
    final normalizedIcon = _requireIcon(iconKey);

    final existing = await _readSorted();
    _assertNameFree(normalizedName, excludingId: null, existing: existing);

    final order = existing.isEmpty ? 0 : existing.last.order + 1;
    final category = Category(
      id: await _generateId(),
      name: normalizedName,
      colorValue: Category.normalizeColor(colorValue),
      iconKey: normalizedIcon,
      order: order,
    );

    await _write(category);
    return category;
  }

  /// Переименовывает и перекрашивает категорию.
  ///
  /// [order] здесь НЕ принимается намеренно: порядком управляют
  /// create/delete/reorder, и если бы update его принимал, порядок
  /// можно было бы испортить обычным редактированием. Заодно это
  /// снимает вопрос «а какой order передать» с вызывающего кода.
  Future<Category> update({
    required String id,
    required String name,
    required int colorValue,
    required String iconKey,
  }) async {
    final current = await getById(id);
    if (current == null) {
      throw ScheduleCategoryException('категория «$id» не найдена');
    }

    final normalizedName = _requireName(name);
    final normalizedIcon = _requireIcon(iconKey);

    final updated = Category(
      id: current.id,
      name: normalizedName,
      colorValue: Category.normalizeColor(colorValue),
      iconKey: normalizedIcon,
      // Порядок сохраняется: переименование не двигает категорию.
      order: current.order,
    );

    _assertNameFree(
      normalizedName,
      excludingId: current.id,
      existing: await _readSorted(),
    );

    await _write(updated);
    return updated;
  }

  /// Удаляет категорию: разрывает её ссылки и перенумеровывает
  /// оставшиеся в плотный `0..n-1`.
  ///
  /// Порядок записи здесь — часть контракта, а не деталь реализации.
  /// Сначала события, потом сама категория: если процесс оборвётся
  /// посередине, останется категория, на которую ссылается меньше
  /// событий, — но НЕ останется события, ссылающегося на уже
  /// несуществующую категорию. Обратный порядок создаёт ровно ту
  /// висячую ссылку, которой здесь быть не должно.
  ///
  /// События не удаляются: терять чужие данные при удалении справочника
  /// нельзя. Ссылка просто становится пустой, а это то же состояние,
  /// с которого начинается любое новое событие.
  ///
  /// Устаревшая строка [ScheduleEvent.category] очищается ВМЕСТЕ со
  /// ссылкой, и это не косметика. Миграция (ScheduleMigrator)
  /// восстанавливает категории из этих строк каждый раз, когда не находит
  /// маркера версии. Оставь мы строку — удалённая категория воскресла бы
  /// при следующей миграции вместе со своими ссылками: удалить её
  /// второй раз было бы уже нечем.
  ///
  /// Перенумерация идёт с места удаления и выше — записи ниже по
  /// порядку не трогаются вообще.
  Future<void> delete(String id) async {
    final current = await getById(id);
    if (current == null) {
      throw ScheduleCategoryException('категория «$id» не найдена');
    }

    await _detachEvents(current);
    await _storage.remove(Category.storageKey(id));

    final remaining = await _readSorted();
    for (var index = 0; index < remaining.length; index++) {
      final category = remaining[index];
      if (category.order == index) continue;
      await _write(category.copyWith(order: index));
    }
  }

  /// Сколько событий затронет удаление категории [id].
  ///
  /// Нужен не для украшения диалога, а чтобы показать пользователю
  /// реальную цену действия ДО того, как он его подтвердит. Поэтому
  /// считает ровно те же события, которые снимет [delete], и использует
  /// тот же предикат [_isLinkedTo]: если бы счётчик считал иначе, диалог
  /// мог бы пообещать «3 события», а удаление затронуло бы пять — или
  /// наоборот, тихо потерять категорию у событий, которые он даже не
  /// упомянул.
  ///
  /// Категории [id] может не быть — тогда 0, а не исключение: вызов
  /// идёт из UI, который перечитывает список независимо от того, какую
  /// строку пользователь уже начал удалять.
  Future<int> countLinkedEvents(String id) async {
    final category = await getById(id);
    if (category == null) return 0;

    var count = 0;
    for (final event in await _events.getAll()) {
      if (_isLinkedTo(event, category)) count++;
    }
    return count;
  }

  /// Снимает категорию со всех её событий.
  ///
  /// Событие считается связанным двумя способами, и нужны оба:
  ///
  /// * по [ScheduleEvent.categoryId] — обычный случай;
  /// * по устаревшей строке [ScheduleEvent.category], когда ссылки ещё
  ///   нет. Такое бывает на данных, ещё не прошедших миграцию, и без этой
  ///   проверки та же строка воскресила бы удалённую категорию.
  Future<void> _detachEvents(Category category) async {
    for (final event in await _events.getAll()) {
      if (!_isLinkedTo(event, category)) continue;

      await _events.update(event.copyWith(categoryId: null, category: ''));
    }
  }

  /// Связано ли событие с категорией — правило «связанности» ровно одно
  /// на репозиторий, чтобы [countLinkedEvents] и [_detachEvents] не
  /// могли разойтись.
  static bool _isLinkedTo(ScheduleEvent event, Category category) {
    if (ScheduleEvent.readCategoryId(event.categoryId) == category.id) {
      return true;
    }

    // Устаревшая строка учитывается только когда ссылки нет: иначе
    // событие, уже переведённое в «Учёбу», считалось бы ещё и
    // принадлежащим «Работе» из-за старой записи.
    return event.categoryId == null &&
        event.category.trim().isNotEmpty &&
        Category.nameKey(event.category) == Category.nameKey(category.name);
  }

  /// Переставляет категории в заданном порядке.
  ///
  /// [idsInOrder] — полный новый порядок: ровно все существующие
  /// категории, каждая ровно один раз. Частичный список не принимается:
  /// иначе неперечисленные категории получили бы «висящие» order, и
  /// плотность пришлось бы додумывать репозиторию. Пропуск или дубль в
  /// списке означает, что у вызывающего устаревшие данные, и это
  /// сообщается ошибкой, а не молча исправляется.
  Future<void> reorder(List<String> idsInOrder) async {
    final existing = await _readSorted();
    final byId = <String, Category>{
      for (final category in existing) category.id: category,
    };

    if (idsInOrder.length != existing.length) {
      throw ScheduleCategoryException(
        'порядок должен перечислять все категории '
        '(ожидалось ${existing.length}, получено ${idsInOrder.length})',
      );
    }

    final seen = <String>{};
    for (final id in idsInOrder) {
      if (!byId.containsKey(id)) {
        throw ScheduleCategoryException('категория «$id» не найдена');
      }
      if (!seen.add(id)) {
        throw ScheduleCategoryException('категория «$id» указана дважды');
      }
    }

    for (var index = 0; index < idsInOrder.length; index++) {
      final category = byId[idsInOrder[index]]!;
      if (category.order == index) continue;
      await _write(category.copyWith(order: index));
    }
  }

  // --- Внутреннее ---

  /// Читает и разбирает все категории, сортируя по (order, id).
  Future<List<Category>> _readSorted() async {
    final keys = await _storage.keys();

    final categories = <Category>[];
    for (final key in keys) {
      final id = Category.idFromStorageKey(key);
      if (id == null) continue;

      final raw = await _storage.getString(key);
      final category = _decode(raw, fallbackId: id);
      if (category == null) continue;
      categories.add(category);
    }

    categories.sort(_compareByOrderThenId);
    return categories;
  }

  /// Порядок вывода: сначала order, при равенстве — id.
  ///
  /// Сравнение строк здесь осознанное: id непрозрачен, но детерминирован,
  /// а порядок вывода обязан быть воспроизводимым.
  static int _compareByOrderThenId(Category a, Category b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  }

  /// Разбирает значение ключа; null, если значение отсутствует или
  /// нечитаемо.
  ///
  /// Идентичность берётся из ключа хранения (`fallbackId`), потому что
  /// он переживает потерю тела записи, а `id` из JSON — только
  /// дополняет его.
  static Category? _decode(String? raw, {required String fallbackId}) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return Category.fromJson(decoded, fallbackId: fallbackId);
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(Category category) {
    return _storage.setString(
      Category.storageKey(category.id),
      jsonEncode(category.toJson()),
    );
  }

  /// Идентификатор, ещё не занятый в хранилище.
  ///
  /// Счётчик микросекунд — тот же, что у событий (EventFormScreen), и
  /// вероятность совпадения на практике нулевая. Но «на практике» здесь
  /// не аргумент: два категории, созданные в один и тот же тик теста,
  /// столкнулись бы и молча перезаписали друг друга (ключ у них общий).
  /// Поэтому кандидат проверяется и при занятости сдвигается на единицу.
  Future<String> _generateId() async {
    var candidate = _idGenerator();
    while (await _storage.getString(Category.storageKey('$candidate')) != null) {
      candidate++;
    }
    return '$candidate';
  }

  static String _requireName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ScheduleCategoryException('название категории не может быть пустым');
    }
    return trimmed;
  }

  static String _requireIcon(String iconKey) {
    final trimmed = iconKey.trim();
    if (trimmed.isEmpty) {
      throw ScheduleCategoryException('иконка категории не может быть пустой');
    }
    return trimmed;
  }

  /// Проверяет уникальность имени без учёта регистра.
  ///
  /// [excludingId] — категория, которую сейчас редактируют: её самое
  /// имя не должно конфликтовать с самим собой, иначе update был бы
  /// невозможен в принципе.
  static void _assertNameFree(
    String name, {
    required String? excludingId,
    required List<Category> existing,
  }) {
    final key = Category.nameKey(name);
    for (final category in existing) {
      if (category.id == excludingId) continue;
      if (Category.nameKey(category.name) != key) continue;
      throw ScheduleCategoryException('категория «${category.name}» уже существует');
    }
  }
}