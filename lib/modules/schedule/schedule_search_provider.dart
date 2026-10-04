import 'package:flutter/material.dart';

import '../../core/search/search_provider.dart';
import '../../core/search/search_result.dart';
import 'models/schedule_event.dart';
import 'schedule_category_repository.dart';
import 'schedule_repository.dart';
import 'ui/category_visuals.dart';

/// Источник поиска Schedule — по названию, категории и заметке.
///
/// Тот же паттерн, что и у ExampleModule (Этап 10): регистрируется в
/// onEnable, отписывается в onDisable, читает через уже существующие
/// репозитории, а не напрямую через ModuleStorage.
///
/// Категория ищется по АКТУАЛЬНОМУ имени из справочника, а не по
/// устаревшей строке события. Разница видна сразу: переименование
/// категории обязано менять то, по чему её находят, иначе поиск продолжил
/// бы находить события по имени, которого у пользователя больше нет.
class ScheduleSearchProvider implements SearchProvider {
  ScheduleSearchProvider(this._repository, this._categoryRepository);

  final ScheduleRepository _repository;
  final ScheduleCategoryRepository _categoryRepository;

  @override
  Future<List<SearchResult>> search(String query) async {
    final lowerQuery = query.toLowerCase();

    // Категории читаются вместе с событиями: два последовательных
    // чтения одного хранилища дешевле, чем гонка двух Future, и дают
    // согласованный снимок.
    final events = await _repository.getAll();
    final resolver = CategoryResolver.of(await _categoryRepository.getAll());

    final matches = events.where((e) {
      final category = resolver.resolve(e);
      return e.title.toLowerCase().contains(lowerQuery) ||
          category.name.toLowerCase().contains(lowerQuery) ||
          e.note.toLowerCase().contains(lowerQuery);
    });

    return matches
        .map((e) {
          final category = resolver.resolve(e);
          return SearchResult(
            title: e.title,
            subtitle: '${category.name} · ${e.dateKey} '
                '${ScheduleEvent.formatMinutes(e.startMinutes)}',
            icon: category.hasAppearance
                ? category.icon
                : Icons.event_outlined,
          );
        })
        .toList();
  }
}