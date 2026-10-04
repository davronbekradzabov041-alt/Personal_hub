import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_search_provider.dart';

/// Поиск показывает АКТУАЛЬНОЕ имя категории.
///
/// Именно это ломается в первую очередь: поиск читал устаревшую строку
/// события, поэтому после переименования категории он продолжал находить
/// события по имени, которого у пользователя больше нет.
class _InMemoryStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

void main() {
  late _InMemoryStorage storage;
  late ScheduleRepository events;
  late ScheduleCategoryRepository categories;
  late ScheduleSearchProvider provider;

  setUp(() {
    storage = _InMemoryStorage();
    events = ScheduleRepository(storage);
    categories = ScheduleCategoryRepository(storage);
    provider = ScheduleSearchProvider(events, categories);
  });

  Future<Category> seedCategory(String name) => categories.create(
        name: name,
        colorValue: 0xFFD97706,
        iconKey: 'work',
      );

  Future<void> seedEvent(
    String id, {
    String title = 'Событие',
    String? categoryId,
    String legacy = '',
    String note = '',
  }) async {
    await events.add(ScheduleEvent(
      id: id,
      title: title,
      category: legacy,
      categoryId: categoryId,
      priority: EventPriority.medium,
      date: DateTime(2026, 1, 15),
      startMinutes: 540,
      endMinutes: 600,
      status: EventStatus.planned,
      note: note,
    ));
  }

  test('находит событие по актуальному имени категории', () async {
    final work = await seedCategory('Работа');
    await seedEvent('e1', title: 'Планёрка', categoryId: work.id, legacy: 'Работа');

    final results = await provider.search('работа');

    expect(results, hasLength(1));
    expect(results.single.title, 'Планёрка');
    expect(results.single.subtitle, contains('Работа'));
  });

  test('после переименования старое имя больше не находится', () async {
    final work = await seedCategory('Работа');
    await seedEvent('e1', title: 'Планёрка', categoryId: work.id, legacy: 'Работа');

    await categories.update(
      id: work.id,
      name: 'Деловые',
      colorValue: 0xFFD97706,
      iconKey: work.iconKey,
    );

    expect(await provider.search('Работа'), isEmpty,
        reason: 'имени «Работа» у пользователя больше нет');
    final found = await provider.search('деловые');
    expect(found, hasLength(1));
    expect(found.single.subtitle, contains('Деловые'));
  });

  test('событие без категории показывает «Без категории», а не пустоту',
      () async {
    await seedEvent('e1', title: 'Прогулка');

    final results = await provider.search('прогулка');

    expect(results, hasLength(1));
    expect(results.single.subtitle, startsWith('Без категории · '));
    // Иконка события, а не иконка несуществующей категории.
    expect(results.single.icon, Icons.event_outlined);
  });

  test('висячая ссылка показывает устаревшее имя и не падает', () async {
    await seedCategory('Работа');
    await seedEvent('e1', title: 'Планёрка', categoryId: 'уже-нет', legacy: 'Работа');

    final results = await provider.search('планёрка');

    expect(results, hasLength(1));
    expect(results.single.subtitle, contains('Работа'));
    expect(results.single.icon, Icons.event_outlined,
        reason: 'оформления нет — иконка события');
  });

  test('поиск по заметке не зависит от категорий', () async {
    await seedEvent('e1', title: 'Планёрка', note: 'подготовить слайды');

    expect(await provider.search('слайды'), hasLength(1));
  });

  test('иконка результата берётся из иконки категории', () async {
    final study = await categories.create(
      name: 'Учёба',
      colorValue: 0xFF0D9488,
      iconKey: 'study',
    );
    await seedEvent('e1', title: 'Лекция', categoryId: study.id, legacy: 'Учёба');

    final results = await provider.search('учёба');

    expect(results.single.icon, Icons.school_outlined);
  });
}