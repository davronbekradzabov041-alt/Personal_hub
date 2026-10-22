import 'package:flutter/material.dart';

/// Цветовая система Personal Hub — Warm Bronze / Raw Tactile.
///
/// Основана на согласованной спецификации (Stage 11):
/// - тёмная тема — основная: фон `#0E0E0E`, базовая поверхность
///   `#181716`, приподнятая `#21201D`, текст `#F4F2ED`;
/// - акцент — тёплая бронза `#D89B51`, без неона и «стекла»;
/// - светлая тема построена на том же бронзовом акценте, но с
///   затемнённым primary, чтобы белый текст на кнопках читался.
class AppColors {
  AppColors._();

  // =========================================================================
  // Brand Lead Color (Warm Bronze)
  // =========================================================================
  static const Color brandPrimary = Color(0xFFD89B51);      // Warm Bronze (тёмная тема)
  static const Color brandPrimaryDark = Color(0xFF9A6626);  // Затемнённая бронза (светлая)

  // =========================================================================
  // Тёмная тема: фон и поверхности (Raw Tactile)
  // =========================================================================
  static const Color canvasDark = Color(0xFF0E0E0E);        // Фон
  static const Color surfaceBaseDark = Color(0xFF181716);   // Базовая поверхность
  static const Color surfaceElevatedDark = Color(0xFF21201D); // Приподнятая поверхность
  static const Color surfaceSunkenDark = Color(0xFF141312);  // Утопленная (поля ввода)

  // =========================================================================
  // Светлая тема: тёплый холст и поверхности
  // =========================================================================
  static const Color canvasLight = Color(0xFFF5F1E8);       // Тёплый холст
  static const Color surfaceBaseLight = Color(0xFFFFFDF8);
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color surfaceSunkenLight = Color(0xFFEDE7DA);

  static const Color borderSubtleLight = Color(0xFFDDD5C6);
  static const Color borderSubtleDark = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  static const Color borderStrongLight = Color(0xFF1C1D21);
  static const Color borderStrongDark = Color(0x33FFFFFF);

  // =========================================================================
  // Текст
  // =========================================================================
  static const Color textPrimaryLight = Color(0xFF1B1815);
  static const Color textPrimaryDark = Color(0xFFF4F2ED);   // Основной (тёмная)

  static const Color textSecondaryLight = Color(0xFF6B6459);
  static const Color textSecondaryDark = Color(0xFFB7AE9E); // Вторичный (тёмная)

  static const Color textTertiaryLight = Color(0xFF9A927F);
  static const Color textTertiaryDark = Color(0xFF7D7466);

  // =========================================================================
  // Light ColorScheme (Warm Canvas + Bronze)
  // =========================================================================
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    // Затемнённая бронза: белый текст на ней даёт контраст 4.9:1
    // (WCAG AA для обычного текста). Ярче — и белый перестаёт читаться.
    primary: Color(0xFF9A6626),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF3E4CC),  // Тёплый контейнер
    onPrimaryContainer: Color(0xFF3A2708),
    secondary: Color(0xFF7A6A52),         // Тёплый нейтральный
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFEBE1D0),
    onSecondaryContainer: Color(0xFF1B1815),
    tertiary: Color(0xFF4C6B4A),          // Тёплый зелёный
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE7EFE1),
    onTertiaryContainer: Color(0xFF11200F),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFFBE9E7),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFFFDF8),
    onSurface: Color(0xFF1B1815),
    surfaceContainerHighest: Color(0xFFEBE1D0),
    onSurfaceVariant: Color(0xFF6B6459),
    outline: Color(0xFF6B6459),
    outlineVariant: Color(0xFFDDD5C6),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFF312C24),
    onInverseSurface: Color(0xFFF5F1E8),
    inversePrimary: Color(0xFFD89B51),
  );

  // =========================================================================
  // Dark ColorScheme (Warm Bronze / Raw Tactile)
  // =========================================================================
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFD89B51),           // Warm Bronze
    onPrimary: Color(0xFF201703),         // Тёмный текст на бронзе
    primaryContainer: Color(0xFF3A2A16),  // Приглушённый бронзовый контейнер
    onPrimaryContainer: Color(0xFFF0C98A),
    secondary: Color(0xFFB7AE9E),
    onSecondary: Color(0xFF221D16),
    secondaryContainer: Color(0xFF2A2620),
    onSecondaryContainer: Color(0xFFF4F2ED),
    tertiary: Color(0xFFA3C79B),
    onTertiary: Color(0xFF12200F),
    tertiaryContainer: Color(0xFF22331F),
    onTertiaryContainer: Color(0xFFBCE0B3),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF3B1512),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF181716),           // Базовая поверхность
    onSurface: Color(0xFFF4F2ED),         // Основной текст
    surfaceContainerHighest: Color(0xFF21201D), // Приподнятая поверхность
    onSurfaceVariant: Color(0xFFB7AE9E),
    outline: Color(0xFF7D7466),
    outlineVariant: Color(0x14FFFFFF),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFF4F2ED),
    onInverseSurface: Color(0xFF312C24),
    inversePrimary: Color(0xFFA9712C),
  );

  // =========================================================================
  // Semantic Colors (Light)
  // =========================================================================
  static const Color semanticSuccess = Color(0xFF4C6B4A);
  static const Color semanticSuccessContainer = Color(0xFFE7EFE1);
  static const Color semanticWarning = Color(0xFF8A6212);
  static const Color semanticWarningContainer = Color(0xFFFBF0DC);
  static const Color semanticError = Color(0xFFB3261E);
  static const Color semanticErrorContainer = Color(0xFFFBE9E7);

  // =========================================================================
  // Semantic Colors (Dark)
  // =========================================================================
  static const Color semanticSuccessDark = Color(0xFFA3C79B);
  static const Color semanticSuccessContainerDark = Color(0x2233331F);
  static const Color semanticWarningDark = Color(0xFFD89B51); // Тот же бронз
  static const Color semanticWarningContainerDark = Color(0x33D89B51);
  static const Color semanticErrorDark = Color(0xFFF2B8B5);
  static const Color semanticErrorContainerDark = Color(0x33F2B8B5);

  // =========================================================================
  // Module Accents (Curated Functional Pigments — Warm Bronze)
  // =========================================================================
  static const Color accentIndigo = Color(0xFFD89B51);   // Core Lead / Bronze
  static const Color accentAmber = Color(0xFFD89B51);    // Schedule / Bronze
  static const Color accentTeal = Color(0xFFC08A4E);     // Files / Warm Bronze
  static const Color accentSlate = Color(0xFFB7AE9E);    // Accounts / Warm Neutral
  static const Color accentEmerald = Color(0xFF8FA07F);  // Finance / Warm Olive
  static const Color accentRose = Color(0xFFB5705F);     // Personal / Terracotta
  static const Color accentViolet = Color(0xFF9C7BB8);   // Catalog / Warm Plum
  static const Color accentBlue = Color(0xFF6E8CA8);     // Network / Slate Bronze

  /// All curated accents for validation
  static const List<Color> curatedAccents = [
    accentIndigo,
    accentAmber,
    accentTeal,
    accentSlate,
    accentEmerald,
    accentRose,
    accentViolet,
    accentBlue,
  ];

  /// Module -> Accent mapping (Functional Pigments)
  ///
  /// Все акценты — тёплые: единая палитра Warm Bronze / Raw Tactile
  /// (Stage 11), без посторонних цветов. Пока реализованы Schedule и
  /// Accounts; остальные id зарезервированы под будущие модули.
  static const Map<String, Color> moduleAccents = {
    'schedule': accentAmber,
    'finance': accentEmerald,
    'accounts': accentSlate,
    'files': accentTeal,
    'backups': accentIndigo,
    'catalog': accentViolet,
    'wifi_transfer': accentBlue,
    'archive': accentSlate,
    'ai': accentViolet,
    'tools': accentSlate,
  };

  /// Get accent for module (with fallback)
  static Color getModuleAccent(String moduleId) {
    return moduleAccents[moduleId] ?? accentIndigo;
  }

  // =========================================================================
  // Module Status Colors (Light)
  // =========================================================================
  static const Map<ModuleStatus, Color> statusColorsLight = {
    ModuleStatus.installed: Color(0xFFEBE1D0),
    ModuleStatus.enabled: Color(0xFFE7EFE1),
    ModuleStatus.disabled: Color(0xFFE5E0D6),
    ModuleStatus.uninstalled: Color(0xFFFBE9E7),
    ModuleStatus.updateAvailable: Color(0xFFFBF0DC),
  };

  static const Map<ModuleStatus, Color> statusOnColorsLight = {
    ModuleStatus.installed: Color(0xFF1B1815),
    ModuleStatus.enabled: Color(0xFF4C6B4A),
    ModuleStatus.disabled: Color(0xFF6B6459),
    ModuleStatus.uninstalled: Color(0xFFB3261E),
    ModuleStatus.updateAvailable: Color(0xFF8A6212),
  };

  // =========================================================================
  // Module Status Colors (Dark)
  // =========================================================================
  static const Map<ModuleStatus, Color> statusColorsDark = {
    ModuleStatus.installed: Color(0xFF2A2620),
    ModuleStatus.enabled: Color(0x2233331F),
    ModuleStatus.disabled: Color(0xFF2A2620),
    ModuleStatus.uninstalled: Color(0x33F2B8B5),
    ModuleStatus.updateAvailable: Color(0x33D89B51),
  };

  static const Map<ModuleStatus, Color> statusOnColorsDark = {
    ModuleStatus.installed: Color(0xFFF4F2ED),
    ModuleStatus.enabled: Color(0xFFA3C79B),
    ModuleStatus.disabled: Color(0xFFB7AE9E),
    ModuleStatus.uninstalled: Color(0xFFF2B8B5),
    ModuleStatus.updateAvailable: Color(0xFFD89B51),
  };

  // =========================================================================
  // Helpers
  // =========================================================================
  static Color statusColor(BuildContext context, ModuleStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? statusColorsDark : statusColorsLight)[status]!;
  }

  static Color statusOnColor(BuildContext context, ModuleStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? statusOnColorsDark : statusOnColorsLight)[status]!;
  }

  static Color warningColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? semanticWarningDark
        : semanticWarning;
  }

  static Color warningContainerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? semanticWarningContainerDark
        : semanticWarningContainer;
  }
}

/// Статусы модулей для семантической цветовой системы
enum ModuleStatus {
  installed,
  enabled,
  disabled,
  uninstalled,
  updateAvailable,
}