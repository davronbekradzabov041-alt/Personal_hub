import 'package:flutter/material.dart';

/// Один результат глобального поиска.
///
/// Не привязан к CoreTestItem или любой другой конкретной
/// модели — источник результата (core, позже модуль) сам
/// решает, как превратить свои данные в SearchResult. Так UI
/// поиска (search_screen.dart) не нужно знать про источники.
class SearchResult {
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Что делать при нажатии на результат. Пока просто закрывает
  /// поиск — реальная навигация к элементу появится, когда
  /// у core test данных будет экран просмотра/редактирования.
  final VoidCallback? onTap;

  const SearchResult({
    required this.title,
    this.subtitle,
    this.icon = Icons.search,
    this.onTap,
  });
}
