import 'package:flutter/material.dart';

import '../../core/search/search_provider.dart';
import '../../core/search/search_result.dart';
import 'models/schedule_event.dart';
import 'schedule_repository.dart';

/// Источник поиска Schedule — по названию, категории и заметке.
///
/// Тот же паттерн, что и у ExampleModule (Этап 10): регистрируется в
/// onEnable, отписывается в onDisable, читает через уже существующий
/// репозиторий, а не напрямую через ModuleStorage.
class ScheduleSearchProvider implements SearchProvider {
  ScheduleSearchProvider(this._repository);
  final ScheduleRepository _repository;

  @override
  Future<List<SearchResult>> search(String query) async {
    final lowerQuery = query.toLowerCase();
    final events = await _repository.getAll();

    final matches = events.where((e) =>
        e.title.toLowerCase().contains(lowerQuery) ||
        e.category.toLowerCase().contains(lowerQuery) ||
        e.note.toLowerCase().contains(lowerQuery));

    return matches
        .map((e) => SearchResult(
              title: e.title,
              subtitle: '${e.category} · ${e.dateKey} '
                  '${ScheduleEvent.formatMinutes(e.startMinutes)}',
              icon: Icons.event_outlined,
            ))
        .toList();
  }
}
