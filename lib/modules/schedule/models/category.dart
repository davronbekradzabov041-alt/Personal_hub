/// Категория события расписания.
///
/// Модель намеренно НЕ знает ни о Flutter, ни о ModuleStorage, ни о
/// Isar — ровно как `ScheduleEvent` (см. соседний файл). Причина та же:
/// хранилище и рендеринг — разные слои, а модель обязана разбираться из
/// чужого JSON без зависимости от Flutter. Всё, что нужно UI (иконка,
/// цветной кружок), получается из `iconKey` и `colorValue` позже, в
/// слое виджетов.
///
/// Поля и их смысл:
///
/// * [id] — непрозрачный и НЕИЗМЕННЫЙ. Он же имя ключа хранения
///   (`category:<id>`), поэтому переименование категории не трогает
///   StoredLink и не ломает ссылки событий. Как и id события,
///   генерируется из микросекундного счётчика.
/// * [name] — то, что видит пользователь. Хранится уже обрезанным от
///   пробелов и уникальным без учёта регистра (обе гарантии держит
///   ScheduleCategoryRepository, а не конструктор: иначе они обходились
///   бы прямым Category.fromJson из испорченного хранилища).
/// * [colorValue] — 32-битный ARGB (`0xAARRGGBB`) как целое число.
///   Не hex-строка: та допускает три корректных записи одного цвета
///   (`#FFF`, `#FFFFFF`, `ffffff`) и требует договорённостей о
///   нормализации, которых иначе не будет. Не enum: категорию выбирает
///   пользователь, а перенумерация enum молча испортила бы все
///   сохранённые значения. Alpha всегда приведена к `0xFF` — иначе
///   сравнение и сортировка цветов не имеют смысла, а текст на
///   произвольном фоне становится нечитаемым.
/// * [iconKey] — строковый идентификатор из фиксированного каталога
///   иконок модуля, а не `IconData` и не code point. `IconData` не
///   сериализуется в JSON, а code point привязывает хранилище к версии
///   шрифта Material Icons и к tree-shaking: переименованный глиф
///   дал бы неотличимое от нуля значение. Тот же приём уже применён в
///   ModuleManifest.icon, где он выбран ровно по этой причине.
///   Каталог иконок появится вместе с UI (Этап 7.5); здесь хранится
///   только ключ, а неизвестный ключ обязан отрисоваться запасной
///   иконкой, а не упасть.
/// * [order] — позиция в пользовательском порядке, плотно `0..n-1`.
///   Натуральный порядок не годится: он меняется при пересоздании
///   удалённой категории, а ключи хранилища возвращаются в порядке
///   вставки строк Isar, а не в порядке, который задумал пользователь.
class Category {
  final String id;
  final String name;

  /// 32-битный ARGB. Всегда с alpha `0xFF` — см. [normalizeColor].
  final int colorValue;

  /// Ключ иконки из каталога модуля. Не пустая строка.
  final String iconKey;

  /// Позиция в пользовательском порядке, плотно `0..n-1`.
  final int order;

  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.order,
  });

  /// Значение цвета, когда сохранённые данные битые или неполные.
  ///
  /// Не «красивый» цвет, а нейтральный: он виден только на сломанных
  /// данных, и настоящая палитра подбора живёт в UI (AppColors).
  /// Дублировать дизайн-токен здесь нельзя — модель не знает про Flutter.
  static const int defaultColorValue = 0xFF1F2438;

  /// Ключ иконки, когда он отсутствует или неизвестен.
  ///
  /// Каталог иконок (Этап 7.5) обязан трактовать любой неизвестный ключ
  /// как «показать запасную иконку», поэтому значение не обязано
  /// существовать в каталоге — оно лишь обязано быть стабильным.
  static const String defaultIconKey = 'default';

  /// Приводит произвольное целое к непрозрачному 32-битному ARGB.
  ///
  /// `& 0xFFFFFF` отбрасывает всё старше 24 бит, поэтому отрицательное
  /// или «длинное» значение (например, из рукописного бэкапа) не
  /// превращается в мусор, а просто обрезается до RGB.
  static int normalizeColor(int value) => 0xFF000000 | (value & 0xFFFFFF);

  /// Обрезает имя и проверяет, что после этого оно не пустое.
  ///
  /// Бросает [FormatException] на пустом — это ошибка данных, а не
  /// нарушение доменного правила, и разбирать её должен парсер, а не
  /// репозиторий.
  static String normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Category: имя не может быть пустым');
    }
    return trimmed;
  }

  /// Ключ, под которым категория лежит в ModuleStorage модуля.
  static String storageKey(String id) => 'category:$id';

  /// Id категории из ключа хранения; null, если ключ не наш.
  static String? idFromStorageKey(String key) {
    if (!key.startsWith('category:')) return null;
    final id = key.substring('category:'.length);
    return id.isEmpty ? null : id;
  }

  /// Ключ сравнения имён: регистр и края пробелов не различаются.
  ///
  /// Единственное место, где определена uniqueness — и репозиторий, и
  /// тесты обязаны приходить именно сюда, иначе «Учёба» и «учёба»
  /// однажды окажутся двумя разными категориями.
  static String nameKey(String name) => name.trim().toLowerCase();

  Category copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? order,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'order': order,
      };

  /// Разбирает категорию из JSON.
  ///
  /// [fallbackId] используется, когда в самом объекте нет `id`: ключ
  /// хранения `category:<id>` — источник правды по идентичности, и он
  /// выживает даже в записи, у которой тело потерялось.
  ///
  /// Неизвестное или битое значение НЕ приводит к исключению: подставляется
  /// запасное, и битая категория не должна ронять чтение остальных — так
  /// же, как битое событие не должно ронять весь список событий.
  /// Единственное, что обязано быть, — непустой `id`.
  factory Category.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) {
    final rawId = json['id'];
    final id = (rawId is String && rawId.trim().isNotEmpty)
        ? rawId.trim()
        : (fallbackId ?? '');
    if (id.isEmpty) {
      throw const FormatException('Category: отсутствует непустой "id"');
    }

    final rawName = json['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : id;

    final rawColor = json['colorValue'];
    final colorValue = rawColor is int
        ? normalizeColor(rawColor)
        : defaultColorValue;

    final rawIcon = json['iconKey'];
    final iconKey =
        rawIcon is String && rawIcon.trim().isNotEmpty ? rawIcon : defaultIconKey;

    final rawOrder = json['order'];
    final order = rawOrder is int ? rawOrder : 0;

    return Category(
      id: id,
      name: name,
      colorValue: colorValue,
      iconKey: iconKey,
      order: order,
    );
  }

  @override
  String toString() =>
      'Category(id: $id, name: $name, order: $order, color: '
      '${colorValue.toRadixString(16).padLeft(8, '0')}, icon: $iconKey)';
}