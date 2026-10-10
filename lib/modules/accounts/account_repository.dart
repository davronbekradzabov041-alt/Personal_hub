import 'dart:convert';

import '../../core/modules/module_storage.dart';
import 'models/account.dart';
import 'uuid.dart';

/// Исключения репозитория аккаунтов.
class AccountRepositoryException implements Exception {
  AccountRepositoryException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Хранилище аккаунтов.
///
/// Поверх ModuleStorage — ключи `account:<uuid>`.
/// Не кэширует между вызовами, каждый запрос читает хранилище.
class AccountRepository {
  AccountRepository(
    this._storage, {
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? generateUuidV4;

  final ModuleStorage _storage;
  final String Function() _idGenerator;

  static const String keyPrefix = 'account:';

  /// Все аккаунты в порядке создания (createdAt).
  Future<List<Account>> getAll() async {
    final keys = await _storage.keys();
    final accountKeys = keys.where((k) => k.startsWith(keyPrefix));

    final accounts = <Account>[];
    for (final key in accountKeys) {
      final raw = await _storage.getString(key);
      if (raw == null) continue;
      final account = _decode(raw, fallbackId: Account.idFromStorageKey(key));
      if (account != null) accounts.add(account);
    }

    accounts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return accounts;
  }

  /// Аккаунт по id; null, если нет.
  Future<Account?> getById(String id) async {
    final raw = await _storage.getString(Account.storageKey(id));
    return _decode(raw, fallbackId: id);
  }

  /// Создаёт аккаунт.
  ///
  /// Бросает [AccountRepositoryException] на пустом имени.
  Future<Account> create({
    required String name,
    required AccountType type,
    required String iconKey,
    required int colorValue,
    required String note,
  }) async {
    try {
      final normalizedName = Account.normalizeName(name);
      final normalizedIcon = _requireIcon(iconKey);

      final existing = await getAll();
      _assertNameFree(normalizedName, excludingId: null, existing: existing);

      final id = await _generateId();
      final now = DateTime.now();

      final account = Account(
        id: id,
        name: normalizedName,
        type: type,
        iconKey: normalizedIcon,
        colorValue: Account.normalizeColor(colorValue),
        note: note,
        createdAt: now,
        updatedAt: now,
      );

      await _write(account);
      return account;
    } on FormatException catch (e) {
      throw AccountRepositoryException(e.message);
    }
  }

  /// Обновляет аккаунт.
  ///
  /// [createdAt] не меняется. Бросает на пустом имени, дубле имени, несуществующем id.
  Future<Account> update({
    required String id,
    required String name,
    required AccountType type,
    required String iconKey,
    required int colorValue,
    required String note,
  }) async {
    try {
      final current = await getById(id);
      if (current == null) {
        throw AccountRepositoryException('аккаунт «$id» не найден');
      }

      final normalizedName = Account.normalizeName(name);
      final normalizedIcon = _requireIcon(iconKey);

      final updated = current.copyWith(
        name: normalizedName,
        type: type,
        iconKey: normalizedIcon,
        colorValue: Account.normalizeColor(colorValue),
        note: note,
        updatedAt: DateTime.now(),
      );

      _assertNameFree(
        normalizedName,
        excludingId: current.id,
        existing: await getAll(),
      );

      await _write(updated);
      return updated;
    } on FormatException catch (e) {
      throw AccountRepositoryException(e.message);
    }
  }

  /// Удаляет аккаунт и все его игры.
  ///
  /// Порядок: сначала игры (разрываем ссылки), потом сам аккаунт.
  /// Бросает, если аккаунта нет.
  Future<void> delete(String id) async {
    final current = await getById(id);
    if (current == null) {
      throw AccountRepositoryException('аккаунт «$id» не найден');
    }

    await _storage.remove(Account.storageKey(id));
  }

  /// Количество аккаунтов.
  Future<int> count() async {
    final keys = await _storage.keys();
    return keys.where((k) => k.startsWith(keyPrefix)).length;
  }

  // --- Внутреннее ---

  Future<void> _write(Account account) {
    return _storage.setString(
      Account.storageKey(account.id),
      jsonEncode(account.toJson()),
    );
  }

  static Account? _decode(String? raw, {required String? fallbackId}) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return Account.fromJson(decoded, fallbackId: fallbackId);
    } on FormatException {
      return null;
    }
  }

  Future<String> _generateId() async {
    var candidate = _idGenerator();
    while (await _storage.getString(Account.storageKey(candidate)) != null) {
      candidate = _idGenerator();
    }
    return candidate;
  }

  static String _requireIcon(String iconKey) {
    final trimmed = iconKey.trim();
    if (trimmed.isEmpty) {
      throw AccountRepositoryException('иконка аккаунта не может быть пустой');
    }
    return trimmed;
  }

  static void _assertNameFree(
    String name, {
    required String? excludingId,
    required List<Account> existing,
  }) {
    final key = name.trim().toLowerCase();
    for (final account in existing) {
      if (account.id == excludingId) continue;
      if (account.name.trim().toLowerCase() != key) continue;
      throw AccountRepositoryException('аккаунт «${account.name}» уже существует');
    }
  }
}