import 'dart:convert';

import '../../core/modules/module_storage.dart';
import 'models/category.dart';
import 'uuid.dart';

/// Исключения репозитория категорий.
class CategoryRepositoryException implements Exception {
  CategoryRepositoryException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Хранилище категорий (общих для аккаунтов и игр).
///
/// Ключи: `category:<uuid>`. Порядок — плотный 0..n-1.
/// Не кэширует между вызовами.
class CategoryRepository {
  CategoryRepository(
    this._storage, {
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? generateUuidV4;

  final ModuleStorage _storage;
  final String Function() _idGenerator;

  static const String keyPrefix = 'category:';

  /// Все категории в пользовательском порядке (order, id).
  Future<List<Category>> getAll() async => _readSorted();

  /// Категория по id; null, если нет.
  Future<Category?> getById(String id) async {
    final raw = await _storage.getString(Category.storageKey(id));
    return _decode(raw, fallbackId: id);
  }

  /// Категория по имени (без учёта регистра и пробелов); null, если нет.
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
  /// Бросает [CategoryRepositoryException] на пустом имени и на дубле
  /// имени без учёта регистра.
  Future<Category> create({
    required String name,
    required String iconKey,
    required int colorValue,
  }) async {
    try {
      final normalizedName = Category.normalizeName(name);
      final normalizedIcon = _requireIcon(iconKey);

      final existing = await _readSorted();
      _assertNameFree(normalizedName, excludingId: null, existing: existing);

      final order = existing.isEmpty ? 0 : existing.last.order + 1;
      final id = await _generateId();

      final category = Category(
        id: id,
        name: normalizedName,
        iconKey: normalizedIcon,
        colorValue: Category.normalizeColor(colorValue),
        order: order,
      );

      await _write(category);
      return category;
    } on FormatException catch (e) {
      throw CategoryRepositoryException(e.message);
    }
  }

  /// Переименовывает/перекрашивает категорию. Порядок не меняется.
  ///
  /// Бросает на пустом имени, дубле имени, несуществующем id.
  Future<Category> update({
    required String id,
    required String name,
    required String iconKey,
    required int colorValue,
  }) async {
    try {
      final current = await getById(id);
      if (current == null) {
        throw CategoryRepositoryException('категория «$id» не найдена');
      }

      final normalizedName = Category.normalizeName(name);
      final normalizedIcon = _requireIcon(iconKey);

      final updated = current.copyWith(
        name: normalizedName,
        iconKey: normalizedIcon,
        colorValue: Category.normalizeColor(colorValue),
      );

      _assertNameFree(
        normalizedName,
        excludingId: current.id,
        existing: await _readSorted(),
      );

      await _write(updated);
      return updated;
    } on FormatException catch (e) {
      throw CategoryRepositoryException(e.message);
    }
  }

  /// Удаляет категорию и перенумеровывает оставшиеся в плотный 0..n-1.
  ///
  /// Не выбрасывает привязанные игры/аккаунты — их [categoryIds] очищаются
  /// внешним кодом (GameRepository/AccountRepository) перед вызовом.
  /// Здесь только чистим сам ключ категории и order.
  ///
  /// Бросает, если категории нет.
  Future<void> delete(String id) async {
    final current = await getById(id);
    if (current == null) {
      throw CategoryRepositoryException('категория «$id» не найдена');
    }

    await _storage.remove(Category.storageKey(id));

    final remaining = await _readSorted();
    for (var index = 0; index < remaining.length; index++) {
      final category = remaining[index];
      if (category.order == index) continue;
      await _write(category.copyWith(order: index));
    }
  }

  /// Переставляет категории в заданном порядке.
  ///
  /// [idsInOrder] — полный новый порядок: все категории ровно по одному разу.
  /// Бросает на несовпадении количества, неизвестном id или дубле.
  Future<void> reorder(List<String> idsInOrder) async {
    final existing = await _readSorted();
    final byId = <String, Category>{
      for (final category in existing) category.id: category,
    };

    if (idsInOrder.length != existing.length) {
      throw CategoryRepositoryException(
        'порядок должен перечислять все категории '
        '(ожидалось ${existing.length}, получено ${idsInOrder.length})',
      );
    }

    final seen = <String>{};
    for (final id in idsInOrder) {
      if (!byId.containsKey(id)) {
        throw CategoryRepositoryException('категория «$id» не найдена');
      }
      if (!seen.add(id)) {
        throw CategoryRepositoryException('категория «$id» указана дважды');
      }
    }

    for (var index = 0; index < idsInOrder.length; index++) {
      final category = byId[idsInOrder[index]]!;
      if (category.order == index) continue;
      await _write(category.copyWith(order: index));
    }
  }

  /// Количество категорий.
  Future<int> count() async {
    final keys = await _storage.keys();
    return keys.where((k) => k.startsWith(keyPrefix)).length;
  }

  // --- Внутреннее ---

  Future<void> _write(Category category) {
    return _storage.setString(
      Category.storageKey(category.id),
      jsonEncode(category.toJson()),
    );
  }

  static Category? _decode(String? raw, {required String? fallbackId}) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return Category.fromJson(decoded, fallbackId: fallbackId);
    } on FormatException {
      return null;
    }
  }

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

  static int _compareByOrderThenId(Category a, Category b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  }

  Future<String> _generateId() async {
    var candidate = _idGenerator();
    while (await _storage.getString(Category.storageKey(candidate)) != null) {
      candidate = _idGenerator();
    }
    return candidate;
  }

  static String _requireIcon(String iconKey) {
    final trimmed = iconKey.trim();
    if (trimmed.isEmpty) {
      throw CategoryRepositoryException('иконка категории не может быть пустой');
    }
    return trimmed;
  }

  static void _assertNameFree(
    String name, {
    required String? excludingId,
    required List<Category> existing,
  }) {
    final key = Category.nameKey(name);
    for (final category in existing) {
      if (category.id == excludingId) continue;
      if (Category.nameKey(category.name) != key) continue;
      throw CategoryRepositoryException('категория «${category.name}» уже существует');
    }
  }
}