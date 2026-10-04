import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/ui/category_visuals.dart';

/// Правило «что показать пользователю» — одно на плитки событий, форму,
/// поиск и Home. Тестируется отдельно от UI именно потому, что оно
/// общее: разойтись правилам нельзя, но можно не заметить, если не
/// проверить каждое состояние данных, которое реально встречается.
void main() {
  Category category(
    String id,
    String name, {
    int colorValue = 0xFFD97706,
    String iconKey = 'work',
  }) {
    return Category(
      id: id,
      name: name,
      colorValue: colorValue,
      iconKey: iconKey,
      order: 0,
    );
  }

  ScheduleEvent event({String? categoryId, String legacy = ''}) {
    return ScheduleEvent(
      id: 'e1',
      title: 'Событие',
      category: legacy,
      categoryId: categoryId,
      priority: EventPriority.medium,
      date: DateTime(2026, 1, 15),
      startMinutes: 540,
      endMinutes: 600,
      status: EventStatus.planned,
    );
  }

  group('CategoryResolver.resolve', () {
    test('ссылка ведёт к названию, цвету и иконке категории', () {
      final resolver = CategoryResolver.of(<Category>[
        category('7', 'Работа', colorValue: 0xFF112233, iconKey: 'work'),
      ]);

      final resolved = resolver.resolve(event(categoryId: '7'));

      expect(resolved.name, 'Работа');
      expect(resolved.colorValue, 0xFF112233);
      expect(resolved.iconKey, 'work');
      expect(resolved.hasAppearance, isTrue);
      expect(resolved.icon, categoryIcons['work']);
    });

    test('переименование категории меняет то, что видно', () {
      // Раньше UI читал устаревшую строку события: после переименования
      // на экране оставалось бы старое имя, которого у пользователя уже
      // нет.
      final resolver = CategoryResolver.of(<Category>[category('7', 'Дела')]);

      expect(resolver.resolve(event(categoryId: '7', legacy: 'Работа')).name,
          'Дела');
    });

    test('без ссылки и без строки — «Без категории» без оформления', () {
      final resolved = const CategoryResolver(<String, Category>{}).resolve(event());

      expect(resolved.name, 'Без категории');
      expect(resolved.hasAppearance, isFalse);
      expect(resolved.colorValue, isNull);
      expect(resolved.iconKey, isNull);
    });

    test('пустая строка и пробелы — тоже «без категории»', () {
      const resolver = CategoryResolver(<String, Category>{});

      expect(resolver.resolve(event(legacy: '   ')).name, 'Без категории');
    });

    test('висячая ссылка показывает устаревшее имя, а не пустоту', () {
      // Категорию удалили в обход репозитория (или восстановили старый
      // бэкап). Ссылка не разрешается, но имя у события есть — показать
      // его лучше, чем молча стереть категорию у пользователя.
      const resolver = CategoryResolver(<String, Category>{});

      final resolved = resolver.resolve(event(categoryId: 'нет-такой', legacy: 'Работа'));

      expect(resolved.name, 'Работа');
      expect(resolved.hasAppearance, isFalse,
          reason: 'взять цвет соседней категории значило бы соврать');
    });

    test('висячая ссылка без имени честно даёт «Без категории»', () {
      const resolver = CategoryResolver(<String, Category>{});

      expect(resolver.resolve(event(categoryId: 'нет-такой')).name,
          'Без категории');
    });

    test('устаревшая строка без ссылки показывается без оформления', () {
      // Данные до миграции: имя есть, категории в справочнике нет.
      final resolver = CategoryResolver.of(<Category>[category('7', 'Работа')]);

      final resolved = resolver.resolve(event(legacy: 'Учёба'));

      expect(resolved.name, 'Учёба');
      expect(resolved.hasAppearance, isFalse);
    });

    test('пустой id в ссылке читается как отсутствие ссылки', () {
      final resolver = CategoryResolver.of(<Category>[category('7', 'Работа')]);

      expect(resolver.resolve(event(categoryId: '  ', legacy: '')).name,
          'Без категории');
    });
  });

  group('Каталог иконок', () {
    test('известный ключ даёт свою иконку', () {
      expect(categoryIconOf('work'), categoryIcons['work']);
    });

    test('неизвестный ключ даёт запасную иконку, а не падение', () {
      // Такой ключ приходит из чужого бэкапа или после переименования
      // глифа в Material Icons.
      expect(
        categoryIconOf('не-существует'),
        categoryIcons[Category.defaultIconKey],
      );
    });

    test('null и пустая строка — запасная иконка', () {
      expect(categoryIconOf(null), categoryIcons[Category.defaultIconKey]);
      expect(categoryIconOf('  '), categoryIcons[Category.defaultIconKey]);
    });

    test('в каталоге есть запасной ключ модели', () {
      expect(categoryIcons.containsKey(Category.defaultIconKey), isTrue,
          reason: 'Category.defaultIconKey обязан быть в каталоге');
    });
  });

  group('Палитра', () {
    test('все цвета непрозрачные', () {
      for (final value in categoryPalette) {
        expect(Category.normalizeColor(value), value,
            reason: 'цвет $value должен уже иметь alpha 0xFF');
      }
    });

    test('цвета не повторяются', () {
      expect(categoryPalette.toSet(), hasLength(categoryPalette.length));
    });

    test('первый цвет — тот же, что у миграции', () {
      // Иначе категории из миграции выглядели бы «не из того набора».
      expect(categoryPalette.first, Category.defaultColorValue);
    });
  });

  group('ResolvedCategory', () {
    test('colorOr возвращает fallback, когда оформления нет', () {
      const fallback = Color(0xFF010203);

      expect(ResolvedCategory.none.colorOr(fallback), fallback);
      expect(
        ResolvedCategory.ofCategory(category('7', 'Работа')).colorOr(fallback),
        const Color(0xFFD97706),
      );
    });
  });
}