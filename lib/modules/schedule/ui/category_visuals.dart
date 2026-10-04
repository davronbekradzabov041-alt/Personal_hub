import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/schedule_event.dart';

/// Каталог иконок категорий Schedule.
///
/// Ключи — строки, а не `IconData`: `IconData` не сериализуется в JSON,
/// а code point привязывает хранилище к версии шрифта Material Icons и к
/// tree-shaking (переименованный глиф дал бы неотличимое от нуля
/// значение). Ровно тот же приём, что в `ModuleManifest.icon`.
///
/// Каталог закрытый и принадлежит модулю: внешние пакеты (Этап 11) не
/// исполняют Dart-код, поэтому новые иконки добавляются только сюда и
/// только релизом приложения.
const Map<String, IconData> categoryIcons = <String, IconData>{
  Category.defaultIconKey: Icons.category_outlined,
  'work': Icons.work_outline,
  'study': Icons.school_outlined,
  'home': Icons.home_outlined,
  'health': Icons.favorite_outline,
  'sport': Icons.directions_run,
  'personal': Icons.person_outline,
  'family': Icons.people_outline,
  'meeting': Icons.groups_outlined,
  'call': Icons.call_outlined,
  'travel': Icons.flight_outlined,
  'money': Icons.payments_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'food': Icons.restaurant_outlined,
  'other': Icons.label_outline,
};

/// Иконка для [iconKey]; неизвестный ключ даёт запасную иконку.
///
/// Подстановка обязательна: ключ приходит из хранилища, которое могло
/// прийти из чужого бэкапа или пережить переименование глифа в
/// Material Icons. Упасть на этом нельзя — иначе один незнакомый ключ
/// уронил бы весь экран событий.
IconData categoryIconOf(String? iconKey) {
  final key = iconKey?.trim();
  if (key == null || key.isEmpty) {
    return categoryIcons[Category.defaultIconKey]!;
  }
  return categoryIcons[key] ?? categoryIcons[Category.defaultIconKey]!;
}

/// Палитра для выбора цвета категории.
///
/// Не enum, а набор целых: цвет хранится в `Category.colorValue` и
/// принадлежит пользователю, а перенумерация enum молча испортила бы все
/// сохранённые значения. Все цвета непрозрачные (alpha `0xFF`), иначе
/// сравнение цветов теряет смысл.
///
/// Первый цвет — [Category.defaultColorValue]: категории, созданные
/// миграцией, выглядят так же, как выбранные вручную, и не выделяются
/// из общего ряда.
const List<int> categoryPalette = <int>[
  0xFF1F2438, // Deep Ink — базовый
  0xFFD97706, // Amber
  0xFF0D9488, // Teal
  0xFF475569, // Slate
  0xFF059669, // Emerald
  0xFFE11D48, // Rose
  0xFF7C3AED, // Violet
  0xFF2563EB, // Blue
  0xFFDB2777, // Pink
  0xFFCA8A04, // Gold
  0xFF15803D, // Forest
  0xFFB45309, // Burnt Orange
];

/// Что показать пользователю вместо категории события.
///
/// Существует отдельно от `Category` и `ScheduleEvent` потому, что
/// «категория события» — это результат разрешения двух независимых
/// полей, а не сам объект категории: событие может ссылаться на
/// несуществующую категорию или не ссылаться вовсе, и оба случая
/// обязаны выглядеть осмысленно, а не падать.
class ResolvedCategory {
  const ResolvedCategory({
    required this.name,
    this.colorValue,
    this.iconKey,
  });

  /// Категории нет. Единственное место, где живёт эта подпись:
  /// отдельной системной категории в хранилище по-прежнему нет, и
  /// отсутствие категории выражается её отсутствием.
  static const ResolvedCategory none = ResolvedCategory(
    name: 'Без категории',
    iconKey: null,
  );

  /// Подпись, всегда непустая.
  final String name;

  /// 32-битный ARGB; null, когда оформления нет (нет категории или
  /// видно только устаревшее имя).
  final int? colorValue;

  /// Ключ иконки; null — нейтральная иконка.
  final String? iconKey;

  factory ResolvedCategory.ofCategory(Category category) => ResolvedCategory(
        name: category.name,
        colorValue: category.colorValue,
        iconKey: category.iconKey,
      );

  /// Есть ли оформление для отрисовки.
  bool get hasAppearance => colorValue != null;

  IconData get icon => iconKey == null
      ? categoryIcons['other']!
      : categoryIconOf(iconKey);

  /// Цвет для рисования; при отсутствии оформления — переданный
  /// запасной (цвет по умолчанию из темы), а не чёрный и не белый:
  /// тема может быть любой, и «правильный» чёрный в тёмной теме
  /// сделал бы подпись невидимой.
  Color colorOr(Color fallback) =>
      colorValue == null ? fallback : Color(colorValue!);
}

/// Разрешает категорию события для показа.
///
/// Единственное место в UI, где решается, что именно видно пользователю.
/// Держать это правило в одном классе обязательно: плитки событий,
/// форма, поиск и Home-секция показывают одну и ту же категорию, и если
/// каждая решит по-своему, «у одной плитки категория есть, у другой
/// нет» станет возможным состоянием приложения.
class CategoryResolver {
  const CategoryResolver(this.categoriesById);

  /// Индекс по id. Строится один раз на загрузку, чтобы каждый экран
  /// не перебирал список категорий для каждого события.
  final Map<String, Category> categoriesById;

  factory CategoryResolver.of(List<Category> categories) => CategoryResolver(
        <String, Category>{
          for (final category in categories) category.id: category,
        },
      );

  ResolvedCategory resolve(ScheduleEvent event) {
    final id = ScheduleEvent.readCategoryId(event.categoryId);
    if (id != null) {
      final category = categoriesById[id];
      if (category != null) return ResolvedCategory.ofCategory(category);
      // Висячая ссылка: id есть, категории нет. Молча показывать
      // «Без категории» значило бы стереть у пользователя её категорию,
      // поэтому показывается устаревшее имя — если оно ещё есть.
    }

    final legacy = event.category.trim();
    if (legacy.isEmpty) return ResolvedCategory.none;

    // Устаревшая строка без ссылки: данных о цвете и иконке нет, и
    // выдумывать их нельзя — подставился бы цвет чужой категории.
    return ResolvedCategory(name: legacy);
  }
}