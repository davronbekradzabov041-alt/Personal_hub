import 'package:isar/isar.dart';

import '../isar_service.dart';
import '../models/core_test_item.dart';
import 'base_repository.dart';

/// Репозиторий тестовой коллекции ядра.
///
/// Служит образцом того, как будет выглядеть репозиторий
/// каждого модуля: тонкая обёртка над Isar, реализующая
/// BaseRepository. Модули на Этапе 3 будут копировать этот
/// паттерн для своих коллекций.
class CoreTestItemRepository implements BaseRepository<CoreTestItem> {
  Isar get _isar => IsarService.instance;

  @override
  Future<int> add(CoreTestItem item) async {
    return _isar.writeTxn(() => _isar.coreTestItems.put(item));
  }

  @override
  Future<void> update(CoreTestItem item) async {
    await _isar.writeTxn(() => _isar.coreTestItems.put(item));
  }

  @override
  Future<bool> delete(int id) async {
    return _isar.writeTxn(() => _isar.coreTestItems.delete(id));
  }

  @override
  Future<CoreTestItem?> getById(int id) async {
    return _isar.coreTestItems.get(id);
  }

  @override
  Future<List<CoreTestItem>> getAll() async {
    return _isar.coreTestItems.where().sortByCreatedAtDesc().findAll();
  }

  /// Поиск по заголовку без учёта регистра — заготовка,
  /// которую на Этапе 5 будет вызывать глобальный поиск.
  Future<List<CoreTestItem>> searchByTitle(String query) async {
    if (query.trim().isEmpty) return [];
    return _isar.coreTestItems
        .filter()
        .titleContains(query, caseSensitive: false)
        .findAll();
  }
}
