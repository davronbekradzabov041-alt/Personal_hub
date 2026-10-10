/// Статус игры в профиле.
enum GameStatus {
  backlog,
  playing,
  completed,
  dropped;

  String get label {
    switch (this) {
      case GameStatus.backlog:
        return 'В планах';
      case GameStatus.playing:
        return 'Играю';
      case GameStatus.completed:
        return 'Пройдено';
      case GameStatus.dropped:
        return 'Брошено';
    }
  }

  static GameStatus fromString(String value) {
    return GameStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GameStatus.backlog,
    );
  }
}

/// Платформа игры.
enum GamePlatform {
  pc,
  steam,
  epicGames,
  gog,
  ea,
  uplay,
  battleNet,
  xbox,
  playstation,
  nintendo,
  mobile,
  other;

  String get label {
    switch (this) {
      case GamePlatform.pc:
        return 'PC';
      case GamePlatform.steam:
        return 'Steam';
      case GamePlatform.epicGames:
        return 'Epic Games';
      case GamePlatform.gog:
        return 'GOG';
      case GamePlatform.ea:
        return 'EA App';
      case GamePlatform.uplay:
        return 'Ubisoft Connect';
      case GamePlatform.battleNet:
        return 'Battle.net';
      case GamePlatform.xbox:
        return 'Xbox';
      case GamePlatform.playstation:
        return 'PlayStation';
      case GamePlatform.nintendo:
        return 'Nintendo';
      case GamePlatform.mobile:
        return 'Мобильная';
      case GamePlatform.other:
        return 'Другое';
    }
  }

  static GamePlatform fromString(String value) {
    return GamePlatform.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GamePlatform.other,
    );
  }
}

/// Игровой профиль — запись об игре в аккаунте.
///
/// Поля:
/// - [id] — стабильный UUID, ключ хранения `game:<id>`
/// - [accountId] — ссылка на аккаунт (обязательна при создании)
/// - [title] — название игры (обрезается, непустое)
/// - [platform] — платформа
/// - [region] — регион (опционально)
/// - [status] — статус прохождения
/// - [playtimeMinutes] — время игры в минутах
/// - [startedAt] / [completedAt] — даты начала/завершения (опционально)
/// - [coverAssetKey] — ключ обложки в ассетах модуля (опционально)
/// - [categoryIds] — список ссылок на категории
/// - [note] — свободная заметка
/// - [createdAt] / [updatedAt] — ISO 8601
class GameProfile {
  final String id;
  final String accountId;
  final String title;
  final GamePlatform platform;
  final String? region;
  final GameStatus status;
  final int playtimeMinutes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? coverAssetKey;
  final List<String> categoryIds;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GameProfile({
    required this.id,
    required this.accountId,
    required this.title,
    required this.platform,
    this.region,
    required this.status,
    required this.playtimeMinutes,
    this.startedAt,
    this.completedAt,
    this.coverAssetKey,
    required this.categoryIds,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int defaultPlaytimeMinutes = 0;

  static String normalizeTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('GameProfile: название не может быть пустым');
    }
    return trimmed;
  }

  static String storageKey(String id) => 'game:$id';

  static String? idFromStorageKey(String key) {
    if (!key.startsWith('game:')) return null;
    final id = key.substring('game:'.length);
    return id.isEmpty ? null : id;
  }

static const Object _notProvided = Object();

  GameProfile copyWith({
    String? accountId,
    String? title,
    GamePlatform? platform,
    Object? region = _notProvided,
    GameStatus? status,
    int? playtimeMinutes,
    DateTime? startedAt,
    DateTime? completedAt,
    String? coverAssetKey,
    List<String>? categoryIds,
    String? note,
    DateTime? updatedAt,
  }) {
    return GameProfile(
      id: id,
      accountId: accountId ?? this.accountId,
      title: title ?? this.title,
      platform: platform ?? this.platform,
      region: identical(region, _notProvided) ? this.region : region as String?,
      status: status ?? this.status,
      playtimeMinutes: playtimeMinutes ?? this.playtimeMinutes,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      coverAssetKey: coverAssetKey ?? this.coverAssetKey,
      categoryIds: categoryIds ?? this.categoryIds,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'accountId': accountId,
        'title': title,
        'platform': platform.name,
        if (region != null) 'region': region,
        'status': status.name,
        'playtimeMinutes': playtimeMinutes,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        if (coverAssetKey != null) 'coverAssetKey': coverAssetKey,
        'categoryIds': categoryIds,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory GameProfile.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) {
    final rawId = json['id'];
    final id = (rawId is String && rawId.trim().isNotEmpty)
        ? rawId.trim()
        : (fallbackId ?? '');
    if (id.isEmpty) {
      throw const FormatException('GameProfile: отсутствует непустой "id"');
    }

    final rawAccountId = json['accountId'];
    final accountId = rawAccountId is String && rawAccountId.trim().isNotEmpty
        ? rawAccountId.trim()
        : '';

    final rawTitle = json['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : id;

    final rawPlatform = json['platform'];
    final platform = rawPlatform is String
        ? GamePlatform.fromString(rawPlatform)
        : GamePlatform.other;

    final rawRegion = json['region'];
    final region = (rawRegion is String && rawRegion.trim().isNotEmpty)
        ? rawRegion.trim()
        : null;

    final rawStatus = json['status'];
    final status = rawStatus is String
        ? GameStatus.fromString(rawStatus)
        : GameStatus.backlog;

    final rawPlaytime = json['playtimeMinutes'];
    final playtimeMinutes = rawPlaytime is int ? rawPlaytime : defaultPlaytimeMinutes;

    final rawStarted = json['startedAt'];
    final startedAt = rawStarted is String
        ? DateTime.tryParse(rawStarted)
        : null;

    final rawCompleted = json['completedAt'];
    final completedAt = rawCompleted is String
        ? DateTime.tryParse(rawCompleted)
        : null;

    final rawCover = json['coverAssetKey'];
    final coverAssetKey = (rawCover is String && rawCover.trim().isNotEmpty)
        ? rawCover.trim()
        : null;

    final rawCategories = json['categoryIds'];
    final categoryIds = rawCategories is List
        ? rawCategories.whereType<String>().toList()
        : <String>[];

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

    return GameProfile(
      id: id,
      accountId: accountId,
      title: title,
      platform: platform,
      region: region,
      status: status,
      playtimeMinutes: playtimeMinutes,
      startedAt: startedAt,
      completedAt: completedAt,
      coverAssetKey: coverAssetKey,
      categoryIds: categoryIds,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'GameProfile(id: $id, accountId: $accountId, title: $title, '
      'status: $status, platform: $platform, playtime: ${playtimeMinutes}m)';
}