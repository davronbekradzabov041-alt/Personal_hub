/// Категория для группировки аккаунтов и игр.
///
/// Поля:
/// - [id] — стабильный UUID, ключ хранения `category:<id>`
/// - [name] — отображаемое имя (обрезается, непустое, уникально без учёта регистра)
/// - [iconKey] — ключ иконки (непустая строка)
/// - [colorValue] — ARGB цвет (alpha всегда 0xFF)
/// - [order] — позиция в пользовательском порядке (плотно 0..n-1)
class Category {
  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final int order;

  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.order,
  });

  static const int defaultColorValue = 0xFF1F2438;
  static const String defaultIconKey = 'default';

  static int normalizeColor(int value) => 0xFF000000 | (value & 0xFFFFFF);

  static String normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Category: имя не может быть пустым');
    }
    return trimmed;
  }

  static String storageKey(String id) => 'category:$id';

  static String? idFromStorageKey(String key) {
    if (!key.startsWith('category:')) return null;
    final id = key.substring('category:'.length);
    return id.isEmpty ? null : id;
  }

  static String nameKey(String name) => name.trim().toLowerCase();

  Category copyWith({
    String? name,
    String? iconKey,
    int? colorValue,
    int? order,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'order': order,
      };

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

    final rawIcon = json['iconKey'];
    final iconKey =
        rawIcon is String && rawIcon.trim().isNotEmpty ? rawIcon : defaultIconKey;

    final rawColor = json['colorValue'];
    final colorValue = rawColor is int
        ? normalizeColor(rawColor)
        : defaultColorValue;

    final rawOrder = json['order'];
    final order = rawOrder is int ? rawOrder : 0;

    return Category(
      id: id,
      name: name,
      iconKey: iconKey,
      colorValue: colorValue,
      order: order,
    );
  }

  @override
  String toString() =>
      'Category(id: $id, name: $name, order: $order, color: '
      '${colorValue.toRadixString(16).padLeft(8, '0')}, icon: $iconKey)';
}