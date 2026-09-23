import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Типографическая система Personal Hub v2.
///
/// Основной шрифт: Plus Jakarta Sans (Modern Editorial).
/// Поддержка FontFeature.tabularFigures() для времени, таймеров и счётчиков.
///
/// Все стили — runtime getters через GoogleFonts.plusJakartaSans().
/// Не используй AppTypography в const-контекстах.
class AppTypography {
  AppTypography._();

  // =========================================================================
  // Base Font Helper (Plus Jakarta Sans)
  // =========================================================================

  static TextStyle _font({
    required double fontSize,
    required double height,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 0.0,
    List<FontFeature>? fontFeatures,
    Color? color,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      fontFeatures: fontFeatures,
      color: color,
    );
  }

  // =========================================================================
  // v2 Typography Scale
  // =========================================================================

  /// Display Large — 36 / 41, weight 700, letter-spacing -0.8
  /// Используется исключительно для главного фокуса дня в Hero.
  static TextStyle get displayLarge => _font(
        fontSize: 36,
        height: 41 / 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      );

  /// Display Medium — 28 / 34, weight 700, letter-spacing -0.5
  /// Крупные таймеры / время ключевого блока / statValue.
  static TextStyle get displayMedium => _font(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );

  /// Display Small — 24 / 30, weight 700, letter-spacing -0.4
  static TextStyle get displaySmall => _font(
        fontSize: 24,
        height: 30 / 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      );

  /// Headline Large — 22 / 28, weight 700, letter-spacing -0.3
  /// Заголовки экранов и модульных страниц.
  static TextStyle get headlineLarge => _font(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  /// Headline Medium — 18 / 24, weight 600, letter-spacing -0.2
  /// Заголовки секций (Upcoming, Today Timeline).
  static TextStyle get headlineMedium => _font(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  /// Headline Small — 16 / 22, weight 600, letter-spacing 0.0
  static TextStyle get headlineSmall => _font(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.0,
      );

  /// Title Large — 20 / 26, weight 600, letter-spacing -0.2
  static TextStyle get titleLarge => _font(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  /// Title Medium — 16 / 22, weight 600, letter-spacing 0.0
  /// Название события, имя модуля в плитке.
  static TextStyle get titleMedium => _font(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.0,
      );

  /// Title Small — 14 / 20, weight 600, letter-spacing +0.1
  static TextStyle get titleSmall => _font(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  /// Body Large — 15 / 22, weight 400, letter-spacing 0.0
  /// Основной текст описаний, заметок.
  static TextStyle get bodyLarge => _font(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.0,
      );

  /// Body Medium — 14 / 20, weight 400, letter-spacing +0.1
  /// Вторичный текст, метаданные.
  static TextStyle get bodyMedium => _font(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      );

  /// Body Small — 12 / 16, weight 400, letter-spacing +0.2
  /// Пояснительные сноски, второстепенные подсказки.
  static TextStyle get bodySmall => _font(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      );

  /// Label Large — 14 / 20, weight 600, letter-spacing +0.1
  /// Кнопки, основные вкладки.
  static TextStyle get labelLarge => _font(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  /// Label Medium — 12 / 16, weight 600, letter-spacing +0.5
  static TextStyle get labelMedium => _font(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );

  /// Label Small / Small Caps — 11 / 14, weight 700, letter-spacing +0.8
  /// Метки категорий, статусы (UPPERCASE).
  static TextStyle get labelSmall => _font(
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      );

  // =========================================================================
  // Time Mono / Tabular — Время, таймеры, счётчики
  // =========================================================================

  /// Time Mono/Tabular — 13 / 16, weight 600, letter-spacing +0.2
  /// Использует FontFeature.tabularFigures() для предотвращения скачков ширины.
  static TextStyle get timeTabular => _font(
        fontSize: 13,
        height: 16 / 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Псевдоним для timeTabular.
  static TextStyle get timeMono => timeTabular;

  // =========================================================================
  // Numeric — Числовые метрики с табулярными цифрами
  // =========================================================================

  static TextStyle get numericLarge => _font(
        fontSize: 36,
        height: 41 / 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get numericMedium => _font(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get numericSmall => _font(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // =========================================================================
  // Semantic Aliases
  // =========================================================================

  /// Псевдоним для labelSmall (UPPERCASE метки, категории).
  static TextStyle get labelSmallCaps => labelSmall;

  /// Псевдоним для labelSmall (секционные метки).
  static TextStyle get sectionLabel => labelSmallCaps;

  /// Ключевое значение метрики (Schedule: event count, etc.).
  static TextStyle get statValue => _font(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Подпись под statValue.
  static TextStyle get statLabel => _font(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      );

  /// Метаданные карточки (дата, теги, вторичная информация).
  static TextStyle get cardMetadata => bodySmall;

  /// Лейбл чипа.
  static TextStyle get chipLabel => labelSmall;

  // =========================================================================
  // TextTheme Builder
  // =========================================================================

  static TextTheme get lightTextTheme => TextTheme(
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

  /// Dark TextTheme идентичен Light — цвета применяются через ColorScheme.
  static TextTheme get darkTextTheme => lightTextTheme;

  // =========================================================================
  // Responsive Display Sizes (v2 Calibrated)
  // =========================================================================
  // Compact (<600dp): 32 / 24 / 20
  // Medium (600-840dp): 36 / 28 / 22
  // Expanded (840-1200dp): 36 / 28 / 24
  // Large (>1200dp): 36 / 28 / 24

  static const Map<String, double> displayLargeResponsive = {
    'compact': 32,
    'medium': 36,
    'expanded': 36,
    'large': 36,
  };

  static const Map<String, double> displayMediumResponsive = {
    'compact': 24,
    'medium': 28,
    'expanded': 28,
    'large': 28,
  };

  static const Map<String, double> displaySmallResponsive = {
    'compact': 20,
    'medium': 24,
    'expanded': 24,
    'large': 24,
  };

  static const Map<String, double> headlineLargeResponsive = {
    'compact': 20,
    'medium': 22,
    'expanded': 22,
    'large': 22,
  };

  static double getDisplayLarge(String breakpoint) =>
      displayLargeResponsive[breakpoint] ?? 36;

  static double getDisplayMedium(String breakpoint) =>
      displayMediumResponsive[breakpoint] ?? 28;

  static double getDisplaySmall(String breakpoint) =>
      displaySmallResponsive[breakpoint] ?? 24;

  static double getHeadlineLarge(String breakpoint) =>
      headlineLargeResponsive[breakpoint] ?? 22;
}