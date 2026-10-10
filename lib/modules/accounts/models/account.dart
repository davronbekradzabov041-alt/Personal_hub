/// Тип аккаунта.
enum AccountType {
  email,
  steam,
  battleNet,
  epicGames,
  uplay,
  gog,
  ea,
  xbox,
  playstation,
  nintendo,
  custom;

  String get label {
    switch (this) {
      case AccountType.email:
        return 'Email';
      case AccountType.steam:
        return 'Steam';
      case AccountType.battleNet:
        return 'Battle.net';
      case AccountType.epicGames:
        return 'Epic Games';
      case AccountType.uplay:
        return 'Ubisoft Connect';
      case AccountType.gog:
        return 'GOG';
      case AccountType.ea:
        return 'EA App';
      case AccountType.xbox:
        return 'Xbox';
      case AccountType.playstation:
        return 'PlayStation';
      case AccountType.nintendo:
        return 'Nintendo';
      case AccountType.custom:
        return 'Другое';
    }
  }

  static AccountType fromString(String value) {
    return AccountType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AccountType.custom,
    );
  }
}

/// Аккаунт — контейнер для учётных данных и профилей игр.
///
/// Поля:
/// - [id] — стабильный UUID, ключ хранения `account:<id>`
/// - [name] — отображаемое имя (обрезается, непустое)
/// - [type] — тип платформы
/// - [iconKey] — ключ иконки (непустая строка)
/// - [colorValue] — ARGB цвет (alpha всегда 0xFF)
/// - [note] — свободная заметка
/// - [createdAt] / [updatedAt] — ISO 8601
class Account {
  final String id;
  final String name;
  final AccountType type;
  final String iconKey;
  final int colorValue;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int defaultColorValue = 0xFF1F2438;
  static const String defaultIconKey = 'default';

  static int normalizeColor(int value) => 0xFF000000 | (value & 0xFFFFFF);

  static String normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Account: имя не может быть пустым');
    }
    return trimmed;
  }

  static String storageKey(String id) => 'account:$id';

  static String? idFromStorageKey(String key) {
    if (!key.startsWith('account:')) return null;
    final id = key.substring('account:'.length);
    return id.isEmpty ? null : id;
  }

Account copyWith({
    String? name,
    AccountType? type,
    String? iconKey,
    int? colorValue,
    String? note,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Account.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) {
    final rawId = json['id'];
    final id = (rawId is String && rawId.trim().isNotEmpty)
        ? rawId.trim()
        : (fallbackId ?? '');
    if (id.isEmpty) {
      throw const FormatException('Account: отсутствует непустой "id"');
    }

    final rawName = json['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : id;

    final rawType = json['type'];
    final type = rawType is String
        ? AccountType.fromString(rawType)
        : AccountType.custom;

    final rawIcon = json['iconKey'];
    final iconKey =
        rawIcon is String && rawIcon.trim().isNotEmpty ? rawIcon : defaultIconKey;

    final rawColor = json['colorValue'];
    final colorValue = rawColor is int
        ? normalizeColor(rawColor)
        : defaultColorValue;

    final rawNote = json['note'];
    final note = rawNote is String ? rawNote : '';

    final rawCreated = json['createdAt'];
    final createdAt = rawCreated is String
        ? DateTime.tryParse(rawCreated) ?? DateTime.now()
        : DateTime.now();

    final rawUpdated = json['updatedAt'];
    final updatedAt = rawUpdated is String
        ? DateTime.tryParse(rawUpdated) ?? createdAt
        : createdAt;

    return Account(
      id: id,
      name: name,
      type: type,
      iconKey: iconKey,
      colorValue: colorValue,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'Account(id: $id, name: $name, type: $type, color: '
      '${colorValue.toRadixString(16).padLeft(8, '0')}, icon: $iconKey)';
}