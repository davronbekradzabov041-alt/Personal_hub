import 'package:flutter/material.dart';

import '../../database/repositories/core_test_item_repository.dart';
import '../search_provider.dart';
import '../search_result.dart';

/// Источник поиска по тестовым данным ядра (CoreTestItem).
///
/// Единственный зарегистрированный провайдер на Этапе 5.
/// Как и сам CoreTestItem, это временный источник — когда
/// появятся настоящие модули со своими данными, этот файл
/// можно будет убрать из регистрации без вреда для остальной
/// системы поиска.
class CoreTestItemSearchProvider implements SearchProvider {
  CoreTestItemSearchProvider(this._repository);

  final CoreTestItemRepository _repository;

  @override
  Future<List<SearchResult>> search(String query) async {
    final items = await _repository.searchByTitle(query);
    return items
        .map((item) => SearchResult(
              title: item.title,
              subtitle: item.description,
              icon: Icons.article_outlined,
            ))
        .toList();
  }
}
