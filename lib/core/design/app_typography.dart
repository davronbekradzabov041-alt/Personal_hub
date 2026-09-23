import 'package:flutter/material.dart';

/// Типографическая система Personal Hub.
///
/// Основана на Material 3 TextTheme с адаптацией под
/// потребности productivity-интерфейса и Focused Workspace.
class AppTypography {
  AppTypography._();

  // =========================================================================
  // Display Metrics — Ключевые метрики (Hero, Featured numbers)
  // =========================================================================
  static const TextStyle displayLarge = TextStyle(
    fontSize: 60,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.10,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.12,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.18,
  );

  // =========================================================================
  // Numeric Metrics — Для ключевых чисел в Feature блоках
  // =========================================================================
  static const TextStyle numericLarge = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.05,
  );

  static const TextStyle numericMedium = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.10,
  );

  static const TextStyle numericSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.20,
  );

  // =========================================================================
  // Headlines — Заголовки секций и крупных блоков
  // =========================================================================
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.20,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.25,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.30,
  );

  // =========================================================================
  // Titles — AppBar, ModuleCard name, Dialog titles
  // =========================================================================
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.27,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
    height: 1.35,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  // =========================================================================
  // Body — Основной текст
  // =========================================================================
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.50,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.3,
    height: 1.50,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.43,
  );

  // =========================================================================
  // Labels — Кнопки, чипы, табы, сегментированные кнопки
  // =========================================================================
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.45,
  );

  // =========================================================================
  // Responsive Display Sizes — Адаптивные размеры Display
  // =========================================================================
  /// Compact (<600dp): 52 / 40 / 28
  /// Medium (600-840dp): 56 / 44 / 32
  /// Expanded (840-1200dp): 60 / 48 / 36
  /// Large (>1200dp): 64 / 52 / 40
  static const Map<String, double> displayLargeResponsive = {
    'compact': 52,
    'medium': 56,
    'expanded': 60,
    'large': 64,
  };

  static const Map<String, double> displayMediumResponsive = {
    'compact': 40,
    'medium': 44,
    'expanded': 48,
    'large': 52,
  };

  static const Map<String, double> displaySmallResponsive = {
    'compact': 28,
    'medium': 32,
    'expanded': 36,
    'large': 40,
  };

  static const Map<String, double> headlineLargeResponsive = {
    'compact': 28,
    'medium': 30,
    'expanded': 32,
    'large': 34,
  };

  /// Получить размер displayLarge для брейкпоинта
  static double getDisplayLarge(String breakpoint) {
    return displayLargeResponsive[breakpoint] ?? 60;
  }

  /// Получить размер displayMedium для брейкпоинта
  static double getDisplayMedium(String breakpoint) {
    return displayMediumResponsive[breakpoint] ?? 48;
  }

  /// Получить размер displaySmall для брейкпоинта
  static double getDisplaySmall(String breakpoint) {
    return displaySmallResponsive[breakpoint] ?? 36;
  }

  /// Получить размер headlineLarge для брейкпоинта
  static double getHeadlineLarge(String breakpoint) {
    return headlineLargeResponsive[breakpoint] ?? 32;
  }

  // =========================================================================
  // TextTheme для Light Theme
  // =========================================================================
  static const TextTheme lightTextTheme = TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );

  // =========================================================================
  // TextTheme для Dark Theme (те же размеры)
  // =========================================================================
  static const TextTheme darkTextTheme = lightTextTheme;

  // =========================================================================
  // Custom Styles
  // =========================================================================
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.38,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static const TextStyle statLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle cardMetadata = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  static const TextStyle chipLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.45,
  );
}