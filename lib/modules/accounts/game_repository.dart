import 'dart:convert';

import '../../core/modules/module_storage.dart';
import 'account_repository.dart';
import 'category_repository.dart';
import 'models/game_profile.dart';
import 'uuid.dart';

/// Исключения репозитория игр.
class GameRepositoryException implements Exception {
  GameRepositoryException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Хранилище игровых профилей.
///
/// Ключи: `game:<uuid>`. Связи: accountId -> Account, categoryIds -> Category.
/// Не кэширует между вызовами.
class GameRepository {
  GameRepository(
    this._storage,
    this._accountRepository,
    this._categoryRepository, {
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? generateUuidV4;

  final ModuleStorage _storage;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final String Function() _idGenerator;

  static const String keyPrefix = 'game:';

  static const Object _notProvided = Object();

  /// Все игры в порядке createdAt.
  Future<List<GameProfile>> getAll() async {
    final keys = await _storage.keys();
    final gameKeys = keys.where((k) => k.startsWith(keyPrefix));

    final games = <GameProfile>[];
    for (final key in gameKeys) {
      final raw = await _storage.getString(key);
      if (raw == null) continue;
      final game = _decode(raw, fallbackId: GameProfile.idFromStorageKey(key));
      if (game != null) games.add(game);
    }

    games.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return games;
  }

  /// Игры конкретного аккаунта.
  Future<List<GameProfile>> getByAccount(String accountId) async {
    final all = await getAll();
    return all.where((g) => g.accountId == accountId).toList();
  }

  /// Игры с конкретной категорией.
  Future<List<GameProfile>> getByCategory(String categoryId) async {
    final all = await getAll();
    return all.where((g) => g.categoryIds.contains(categoryId)).toList();
  }

  /// Игра по id; null, если нет.
  Future<GameProfile?> getById(String id) async {
    final raw = await _storage.getString(GameProfile.storageKey(id));
    return _decode(raw, fallbackId: id);
  }

  /// Создаёт игровой профиль.
  ///
  /// Проверяет существование аккаунта и категорий.
  /// Бросает [GameRepositoryException] на пустом названии, несуществующем аккаунте/категории.
  Future<GameProfile> create({
    required String accountId,
    required String title,
    required GamePlatform platform,
    String? region,
    required GameStatus status,
    required int playtimeMinutes,
    DateTime? startedAt,
    DateTime? completedAt,
    String? coverAssetKey,
    required List<String> categoryIds,
    required String note,
  }) async {
    try {
      final normalizedTitle = GameProfile.normalizeTitle(title);

      // Проверяем аккаунт
      final account = await _accountRepository.getById(accountId);
      if (account == null) {
        throw GameRepositoryException('аккаунт «$accountId» не найден');
      }

      // Проверяем категории
      final validCategoryIds = <String>[];
      for (final catId in categoryIds) {
        final cat = await _categoryRepository.getById(catId);
        if (cat == null) {
          throw GameRepositoryException('категория «$catId» не найдена');
        }
        validCategoryIds.add(catId);
      }

      final id = await _generateId();
      final now = DateTime.now();

      final game = GameProfile(
        id: id,
        accountId: accountId,
        title: normalizedTitle,
        platform: platform,
        region: region,
        status: status,
        playtimeMinutes: playtimeMinutes,
        startedAt: startedAt,
        completedAt: completedAt,
        coverAssetKey: coverAssetKey,
        categoryIds: validCategoryIds,
        note: note,
        createdAt: now,
        updatedAt: now,
      );

      await _write(game);
      return game;
    } on FormatException catch (e) {
      throw GameRepositoryException(e.message);
    }
  }

  /// Обновляет игровой профиль.
  ///
  /// При смене accountId проверяет существование нового аккаунта.
  /// При смене categoryIds проверяет существование всех категорий.
  /// Бросает на пустом названии, несуществующем id/аккаунте/категории.
  Future<GameProfile> update({
    required String id,
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
  }) async {
    try {
      final current = await getById(id);
      if (current == null) {
        throw GameRepositoryException('игра «$id» не найдена');
      }

      // Проверяем новый аккаунт, если меняется
      final targetAccountId = accountId ?? current.accountId;
      if (targetAccountId != current.accountId) {
        final account = await _accountRepository.getById(targetAccountId);
        if (account == null) {
          throw GameRepositoryException('аккаунт «$targetAccountId» не найден');
        }
      }

      // Проверяем категории, если меняются
      final targetCategoryIds = categoryIds ?? current.categoryIds;
      if (targetCategoryIds != current.categoryIds) {
        final validCategoryIds = <String>[];
        for (final catId in targetCategoryIds) {
          final cat = await _categoryRepository.getById(catId);
          if (cat == null) {
            throw GameRepositoryException('категория «$catId» не найдена');
          }
          validCategoryIds.add(catId);
        }
      }

      final updated = current.copyWith(
        accountId: targetAccountId,
        title: title != null ? GameProfile.normalizeTitle(title) : current.title,
        platform: platform ?? current.platform,
        region: identical(region, _notProvided) ? current.region : region,
        status: status ?? current.status,
        playtimeMinutes: playtimeMinutes ?? current.playtimeMinutes,
        startedAt: startedAt ?? current.startedAt,
        completedAt: completedAt ?? current.completedAt,
        coverAssetKey: coverAssetKey ?? current.coverAssetKey,
        categoryIds: targetCategoryIds,
        note: note ?? current.note,
        updatedAt: DateTime.now(),
      );

      await _write(updated);
      return updated;
    } on FormatException catch (e) {
      throw GameRepositoryException(e.message);
    }
  }

  /// Удаляет игру. Не затрагивает аккаунт и категории.
  ///
  /// Бросает, если игры нет.
  Future<void> delete(String id) async {
    final current = await getById(id);
    if (current == null) {
      throw GameRepositoryException('игра «$id» не найдена');
    }

    await _storage.remove(GameProfile.storageKey(id));
  }

  /// Удаляет все игры аккаунта (при удалении аккаунта).
  Future<void> deleteByAccount(String accountId) async {
    final games = await getByAccount(accountId);
    for (final game in games) {
      await _storage.remove(GameProfile.storageKey(game.id));
    }
  }

  /// Удаляет ссылку на категорию из всех игр (при удалении категории).
  Future<void> detachCategory(String categoryId) async {
    final games = await getByCategory(categoryId);
    for (final game in games) {
      final updatedIds = game.categoryIds.where((c) => c != categoryId).toList();
      await _write(game.copyWith(categoryIds: updatedIds));
    }
  }

  /// Количество игр (общее или по аккаунту).
  Future<int> count({String? accountId}) async {
    if (accountId != null) {
      final games = await getByAccount(accountId);
      return games.length;
    }
    final keys = await _storage.keys();
    return keys.where((k) => k.startsWith(keyPrefix)).length;
  }

  // --- Внутреннее ---

  Future<void> _write(GameProfile game) {
    return _storage.setString(
      GameProfile.storageKey(game.id),
      jsonEncode(game.toJson()),
    );
  }

  static GameProfile? _decode(String? raw, {required String? fallbackId}) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return GameProfile.fromJson(decoded, fallbackId: fallbackId);
    } on FormatException {
      return null;
    }
  }

  Future<String> _generateId() async {
    var candidate = _idGenerator();
    while (await _storage.getString(GameProfile.storageKey(candidate)) != null) {
      candidate = _idGenerator();
    }
    return candidate;
  }
}