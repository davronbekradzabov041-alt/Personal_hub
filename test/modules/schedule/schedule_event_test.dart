import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';

/// Тесты модели ScheduleEvent в части ссылки на категорию.
///
/// Отдельно от schedule_module_test.dart, где проверяется то же самое
/// через ScheduleRepository: там важно, что значение доехало до
/// хранилища, здесь — что модель сама по себе читает и пишет все формы
/// записи, которые вообще могут встретиться в хранилище.
ScheduleEvent _event({
  String id = 'e1',
  String title = 'Встреча',
  String category = 'Работа',
  String? categoryId,
}) {
  return ScheduleEvent(
    id: id,
    title: title,
    category: category,
    categoryId: categoryId,
    priority: EventPriority.medium,
    date: DateTime(2026, 1, 15),
    startMinutes: 9 * 60,
    endMinutes: 10 * 60,
    status: EventStatus.planned,
  );
}

/// Минимально валидное тело события — как его пишет toJson.
Map<String, dynamic> _json({
  String id = 'e1',
  String? category,
  String? categoryId,
  bool includeCategory = true,
}) {
  return <String, dynamic>{
    'id': id,
    'title': 'Встреча',
    if (includeCategory) 'category': category,
    if (categoryId != null) 'categoryId': categoryId,
    'priority': 'medium',
    'date': '2026-01-15',
    'startMinutes': 540,
    'endMinutes': 600,
    'status': 'planned',
    'note': '',
  };
}

void main() {
  group('ScheduleEvent — конструктор', () {
    test('category по умолчанию пустой, categoryId — null', () {
      final event = _event(category: '');

      expect(event.category, isEmpty);
      expect(event.categoryId, isNull);
    });

    test('category и categoryId можно не указывать', () {
      final event = ScheduleEvent(
        id: 'e1',
        title: 'Встреча',
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 540,
        endMinutes: 600,
        status: EventStatus.planned,
      );

      expect(event.category, isEmpty);
      expect(event.categoryId, isNull);
    });
  });

  group('ScheduleEvent — toJson', () {
    test('category пишется всегда, даже когда пустой', () {
      final json = _event(category: '').toJson();

      expect(json.containsKey('category'), isTrue);
      expect(json['category'], '');
    });

    test('categoryId пишется, когда он есть', () {
      final json = _event(categoryId: 'cat-7').toJson();

      expect(json['categoryId'], 'cat-7');
    });

    test('categoryId не пишется, когда его нет', () {
      final json = _event().toJson();

      expect(
        json.containsKey('categoryId'),
        isFalse,
        reason: 'у события без категории ссылка не нужна; отсутствующий '
            'ключ читается так же, как явный null',
      );
    });

    test('запись без категории остаётся читаемой старым кодом', () {
      // Ровно то, что читает сборка, где categoryId ещё не существует:
      // ключ category на месте, лишний ключ она просто не замечает.
      final json = _event(categoryId: 'cat-7').toJson();

      expect(json['category'], 'Работа');
    });

    test('тело проходит через JSON без потерь', () {
      final original = _event(category: '', categoryId: 'cat-7');

      final restored = ScheduleEvent.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.categoryId, 'cat-7');
      expect(restored.category, '');
      expect(restored.id, original.id);
      expect(restored.dateKey, original.dateKey);
      expect(restored.startMinutes, original.startMinutes);
      expect(restored.status, original.status);
    });
  });

  group('ScheduleEvent — fromJson: обратная совместимость', () {
    test('старая запись (есть category, нет categoryId) читается', () {
      final event = ScheduleEvent.fromJson(_json(category: 'Работа'));

      expect(event.categoryId, isNull);
      expect(event.category, 'Работа');
    });

    test('запись без ключа category читается как «без категории»', () {
      final event = ScheduleEvent.fromJson(_json(includeCategory: false));

      expect(event.categoryId, isNull);
      expect(event.category, isEmpty);
    });

    test('запись без обоих ключей читается', () {
      final event = ScheduleEvent.fromJson(_json(includeCategory: false));

      expect(event.categoryId, isNull);
      expect(event.category, isEmpty);
      expect(event.title, 'Встреча');
    });

    test('явный categoryId: null читается как null', () {
      final event = ScheduleEvent.fromJson(
        _json(category: 'Работа', categoryId: null)..['categoryId'] = null,
      );

      expect(event.categoryId, isNull);
    });

    test('categoryId важнее устаревшего category', () {
      // Расхождение возможно: category — это снимок имени на момент
      // записи, categoryId — ссылка. Поле, на которое ссылается
      // событие, и есть источник правды.
      final event = ScheduleEvent.fromJson(
        _json(category: 'Старое имя', categoryId: 'cat-7'),
      );

      expect(event.categoryId, 'cat-7');
      expect(event.category, 'Старое имя');
    });

    test('остальные поля старой записи не теряются', () {
      final event = ScheduleEvent.fromJson(_json(category: 'Работа'));

      expect(event.id, 'e1');
      expect(event.title, 'Встреча');
      expect(event.priority, EventPriority.medium);
      expect(event.dateKey, '2026-01-15');
      expect(event.startMinutes, 540);
      expect(event.endMinutes, 600);
      expect(event.status, EventStatus.planned);
      expect(event.note, '');
    });
  });

  group('ScheduleEvent — readCategoryId', () {
    test('непустая строка принимается', () {
      expect(ScheduleEvent.readCategoryId('cat-7'), 'cat-7');
    });

    test('края пробелов обрезаются', () {
      expect(ScheduleEvent.readCategoryId('  cat-7  '), 'cat-7');
    });

    test('null, пустая строка и пробелы — это «без категории»', () {
      expect(ScheduleEvent.readCategoryId(null), isNull);
      expect(ScheduleEvent.readCategoryId(''), isNull);
      expect(ScheduleEvent.readCategoryId('   '), isNull);
    });

    test('значение неправильного типа — это «без категории», а не ошибка',
        () {
      // Испорченный backup не должен ронять чтение всего модуля.
      expect(ScheduleEvent.readCategoryId(7), isNull);
      expect(ScheduleEvent.readCategoryId(<String>['a']), isNull);
      expect(ScheduleEvent.readCategoryId(<String, dynamic>{'a': 1}), isNull);
    });

    test('fromJson применяет те же правила к битому categoryId', () {
      final event = ScheduleEvent.fromJson(_json(category: 'Работа')
        ..['categoryId'] = 42);

      expect(event.categoryId, isNull);
    });
  });

  group('ScheduleEvent — copyWith и categoryId', () {
    test('без аргумента ссылка сохраняется', () {
      final event = _event(categoryId: 'cat-7');

      expect(event.copyWith(title: 'Другое').categoryId, 'cat-7');
      expect(event.copyWith().categoryId, 'cat-7');
    });

    test('ссылку можно задать', () {
      final event = _event();

      expect(event.copyWith(categoryId: 'cat-7').categoryId, 'cat-7');
    });

    test('заданную ссылку можно переопределить', () {
      final event = _event(categoryId: 'cat-7');

      expect(event.copyWith(categoryId: 'cat-9').categoryId, 'cat-9');
    });

    test('ссылку можно очистить, передав null', () {
      final event = _event(categoryId: 'cat-7');

      expect(event.copyWith(categoryId: null).categoryId, isNull);
    });

    test('очистка ссылки не трогает устаревшую строку', () {
      final event = _event(category: 'Работа', categoryId: 'cat-7');

      final cleared = event.copyWith(categoryId: null);

      expect(cleared.categoryId, isNull);
      expect(cleared.category, 'Работа');
    });

    test('copyWith не меняет исходное событие', () {
      final event = _event(categoryId: 'cat-7');

      event.copyWith(categoryId: null);

      expect(event.categoryId, 'cat-7');
    });

    test('остальные поля copyWith работают как раньше', () {
      final event = _event(categoryId: 'cat-7');

      final updated = event.copyWith(
        title: 'Новое',
        category: 'Другая',
        priority: EventPriority.high,
        note: 'заметка',
      );

      expect(updated.title, 'Новое');
      expect(updated.category, 'Другая');
      expect(updated.priority, EventPriority.high);
      expect(updated.note, 'заметка');
      expect(updated.categoryId, 'cat-7');
    });

    test('очищенная через copyWith ссылка переживает запись и чтение',
        () {
      final event = _event(categoryId: 'cat-7').copyWith(categoryId: null);

      final restored = ScheduleEvent.fromJson(event.toJson());

      expect(restored.categoryId, isNull);
      expect(restored.category, 'Работа');
    });
  });
}