import 'package:flutter/material.dart';
import 'global_search_service.dart';

/// Даёт доступ к единственному экземпляру GlobalSearchService
/// из любого места в дереве виджетов — по аналогии с
/// AppSettingsScope, но без Listenable: сервис сам не хранит
/// состояние, которое меняется во времени.
class SearchScope extends InheritedWidget {
  const SearchScope({
    super.key,
    required this.service,
    required super.child,
  });

  final GlobalSearchService service;

  static GlobalSearchService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SearchScope>();
    assert(scope != null, 'SearchScope не найден в дереве виджетов');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(SearchScope oldWidget) =>
      service != oldWidget.service;
}
