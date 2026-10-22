import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/game_profile.dart';

/// Каталог иконок для аккаунтов.
///
/// Ключи — строки для сериализации в JSON. Не `IconData` напрямую.
const Map<String, IconData> accountIcons = <String, IconData>{
  Account.defaultIconKey: Icons.account_circle_outlined,
  'email': Icons.email_outlined,
  'steam': Icons.videogame_asset_outlined,
  'battleNet': Icons.shield_outlined,
  'epicGames': Icons.rocket_launch_outlined,
  'uplay': Icons.gamepad_outlined,
  'gog': Icons.store_outlined,
  'ea': Icons.sports_esports_outlined,
  'xbox': Icons.sports_outlined,
  'playstation': Icons.sports_handball_outlined,
  'nintendo': Icons.toys_outlined,
  'custom': Icons.settings_outlined,
};

/// Иконка для [iconKey]; неизвестный ключ даёт запасную иконку.
IconData accountIconOf(String? iconKey) {
  final key = iconKey?.trim();
  if (key == null || key.isEmpty) {
    return accountIcons[Account.defaultIconKey]!;
  }
  return accountIcons[key] ?? accountIcons[Account.defaultIconKey]!;
}

/// Палитра цветов для аккаунтов.
///
/// Все цвета непрозрачные (alpha 0xFF).
const List<int> accountPalette = <int>[
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

/// Каталог иконок категорий Accounts.
///
/// Совпадает с Schedule для согласованности, но может расширяться.
const Map<String, IconData> accountsCategoryIcons = <String, IconData>{
  Category.defaultIconKey: Icons.category_outlined,
  'action': Icons.flash_on_outlined,
  'rpg': Icons.auto_awesome_outlined,
  'strategy': Icons.psychology_outlined,
  'shooter': Icons.sports_outlined,
  'adventure': Icons.explore_outlined,
  'simulation': Icons.architecture_outlined,
  'sport': Icons.directions_run,
  'racing': Icons.directions_bike_outlined,
  'puzzle': Icons.extension_outlined,
  'horror': Icons.celebration_outlined,
  'indie': Icons.auto_fix_high_outlined,
  'multiplayer': Icons.people_outline,
  'singleplayer': Icons.person_outline,
  'coop': Icons.groups_outlined,
  'vr': Icons.devices_outlined,
  'retro': Icons.tv_outlined,
  'other': Icons.label_outline,
};

/// Иконка для [iconKey] категорий; неизвестный ключ даёт запасную.
IconData accountsCategoryIconOf(String? iconKey) {
  final key = iconKey?.trim();
  if (key == null || key.isEmpty) {
    return accountsCategoryIcons[Category.defaultIconKey]!;
  }
  return accountsCategoryIcons[key] ?? accountsCategoryIcons[Category.defaultIconKey]!;
}

/// Палитра цветов для категорий.
///
/// Совпадает с Schedule для согласованности.
const List<int> accountsCategoryPalette = <int>[
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

/// Что показать пользователю вместо категории игры.
class ResolvedGameCategory {
  const ResolvedGameCategory({
    required this.name,
    this.colorValue,
    this.iconKey,
  });

  static const ResolvedGameCategory none = ResolvedGameCategory(
    name: 'Без категории',
    iconKey: null,
  );

  final String name;
  final int? colorValue;
  final String? iconKey;

  factory ResolvedGameCategory.ofCategory(Category category) => ResolvedGameCategory(
        name: category.name,
        colorValue: category.colorValue,
        iconKey: category.iconKey,
      );

  bool get hasAppearance => colorValue != null;

  IconData get icon => iconKey == null
      ? accountsCategoryIcons['other']!
      : accountsCategoryIconOf(iconKey);

  Color colorOr(Color fallback) =>
      colorValue == null ? fallback : Color(colorValue!);
}

/// Разрешает категории игры для показа.
class GameCategoryResolver {
  const GameCategoryResolver(this.categoriesById);

  final Map<String, Category> categoriesById;

  factory GameCategoryResolver.of(List<Category> categories) => GameCategoryResolver(
        <String, Category>{
          for (final category in categories) category.id: category,
        },
      );

  ResolvedGameCategory resolve(GameProfile game) {
    for (final id in game.categoryIds) {
      final category = categoriesById[id];
      if (category != null) return ResolvedGameCategory.ofCategory(category);
    }
    return ResolvedGameCategory.none;
  }

  /// Разрешает все категории игры в список для отображения.
  List<ResolvedGameCategory> resolveAll(GameProfile game) {
    final resolved = <ResolvedGameCategory>[];
    for (final id in game.categoryIds) {
      final category = categoriesById[id];
      if (category != null) {
        resolved.add(ResolvedGameCategory.ofCategory(category));
      }
    }
    return resolved.isEmpty ? [ResolvedGameCategory.none] : resolved;
  }
}