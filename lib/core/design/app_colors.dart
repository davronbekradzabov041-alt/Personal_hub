import 'package:flutter/material.dart';

/// Цветовая система Personal Hub.
///
/// Основана на Material 3 ColorScheme с семантическими расширениями
/// для статусов модулей, UI-состояний и модульных акцентов.
class AppColors {
  AppColors._();

  // =========================================================================
  // Brand Color
  // =========================================================================
  static const Color brandPrimary = Color(0xFF3B4FC7); // Deep Indigo

  // =========================================================================
  // Light ColorScheme
  // =========================================================================
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3B4FC7),           // Deep Indigo
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE8E9FF),  // Hero wash base
    onPrimaryContainer: Color(0xFF1A2380),
    secondary: Color(0xFF5C6BC0),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE3E6FF), // Module accent wash
    onSecondaryContainer: Color(0xFF1D2B7A),
    tertiary: Color(0xFF006E5C),           // Success/Teal
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFB4F7DE),  // Success wash
    onTertiaryContainer: Color(0xFF00211A),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFCFCFF),
    onSurface: Color(0xFF1A1C1E),
    surfaceContainerHighest: Color(0xFFE0E2E9),
    onSurfaceVariant: Color(0xFF44474E),
    outline: Color(0xFF74777F),
    outlineVariant: Color(0xFFC4C7CF),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFF2F3033),
    onInverseSurface: Color(0xFFF0F0F4),
    inversePrimary: Color(0xFFC5C9FF),
  );

  // =========================================================================
  // Dark ColorScheme — Independent Environment
  // =========================================================================
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFC5C9FF),           // Desaturated
    onPrimary: Color(0xFF0A156E),
    primaryContainer: Color(0xFF243292),  // Hero wash (15% opacity)
    onPrimaryContainer: Color(0xFFE8E9FF),
    secondary: Color(0xFFC5C9FF),
    onSecondary: Color(0xFF1A2380),
    secondaryContainer: Color(0xFF3E4BA0),
    onSecondaryContainer: Color(0xFFE3E6FF),
    tertiary: Color(0xFF97DBBE),          // Brighter success
    onTertiary: Color(0xFF00382E),
    tertiaryContainer: Color(0xFF005142),
    onTertiaryContainer: Color(0xFFB4F7DE),
    error: Color(0xFFFFB4AB),             // Softer red
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF1A1C1E),
    onSurface: Color(0xFFE0E2E9),
    surfaceContainerHighest: Color(0xFF44474E),
    onSurfaceVariant: Color(0xFFC4C7CF),
    outline: Color(0xFF8E9098),
    outlineVariant: Color(0xFF44474E),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFE0E2E9),
    onInverseSurface: Color(0xFF1A1C1E),
    inversePrimary: Color(0xFF3B4FC7),
  );

  // =========================================================================
  // Semantic Colors (Light)
  // =========================================================================
  static const Color semanticSuccess = Color(0xFF006E5C);
  static const Color semanticSuccessContainer = Color(0xFFB4F7DE);
  static const Color semanticWarning = Color(0xFFE8A000);    // Amber
  static const Color semanticWarningContainer = Color(0xFFFFF3E0);
  static const Color semanticError = Color(0xFFBA1A1A);
  static const Color semanticErrorContainer = Color(0xFFFFDAD6);

  // =========================================================================
  // Semantic Colors (Dark)
  // =========================================================================
  static const Color semanticSuccessDark = Color(0xFF97DBBE);
  static const Color semanticSuccessContainerDark = Color(0xFF005142);
  static const Color semanticWarningDark = Color(0xFFFFB74D);
  static const Color semanticWarningContainerDark = Color(0xFF3E2700);
  static const Color semanticErrorDark = Color(0xFFFFB4AB);
  static const Color semanticErrorContainerDark = Color(0xFF93000A);

  // =========================================================================
  // Module Accents (Curated Palette)
  // =========================================================================
  static const Color accentIndigo = Color(0xFF3B4FC7);   // Core, Schedule, WiFi, Tools
  static const Color accentTeal = Color(0xFF006E5C);     // Accounts, Files
  static const Color accentAmber = Color(0xFFE8A000);    // Schedule, Productivity
  static const Color accentRose = Color(0xFFC62868);     // Finance, Personal
  static const Color accentViolet = Color(0xFF7C4DFF);   // AI, Catalog, Creative
  static const Color accentSlate = Color(0xFF475569);    // Backups, Archive, System

  /// All curated accents for validation
  static const List<Color> curatedAccents = [
    accentIndigo,
    accentTeal,
    accentAmber,
    accentRose,
    accentViolet,
    accentSlate,
  ];

  /// Module -> Accent mapping (UI-only, no core changes)
  static const Map<String, Color> moduleAccents = {
    'schedule': accentAmber,
    'accounts': accentTeal,
    'files': accentTeal,
    'backups': accentSlate,
    'finance': accentRose,
    'catalog': accentViolet,
    'wifi_transfer': accentIndigo,
    'archive': accentSlate,
    'ai': accentViolet,
    'tools': accentIndigo,
    'example': accentIndigo,
  };

  /// Get accent for module (with fallback)
  static Color getModuleAccent(String moduleId) {
    return moduleAccents[moduleId] ?? accentIndigo;
  }

  // =========================================================================
  // Module Status Colors (Light)
  // =========================================================================
  static const Map<ModuleStatus, Color> statusColorsLight = {
    ModuleStatus.installed: Color(0xFFE3E6FF),      // secondaryContainer
    ModuleStatus.enabled: Color(0xFFB4F7DE),        // tertiaryContainer
    ModuleStatus.disabled: Color(0xFFE0E2E9),       // surfaceContainerHighest
    ModuleStatus.uninstalled: Color(0xFFFFDAD6),    // errorContainer
    ModuleStatus.updateAvailable: Color(0xFFE8E9FF), // primaryContainer
  };

  static const Map<ModuleStatus, Color> statusOnColorsLight = {
    ModuleStatus.installed: Color(0xFF1D2B7A),
    ModuleStatus.enabled: Color(0xFF00211A),
    ModuleStatus.disabled: Color(0xFF44474E),
    ModuleStatus.uninstalled: Color(0xFF410002),
    ModuleStatus.updateAvailable: Color(0xFF1A2380),
  };

  // =========================================================================
  // Module Status Colors (Dark)
  // =========================================================================
  static const Map<ModuleStatus, Color> statusColorsDark = {
    ModuleStatus.installed: Color(0xFF3E4BA0),
    ModuleStatus.enabled: Color(0xFF005142),
    ModuleStatus.disabled: Color(0xFF44474E),
    ModuleStatus.uninstalled: Color(0xFF93000A),
    ModuleStatus.updateAvailable: Color(0xFF243292),
  };

  static const Map<ModuleStatus, Color> statusOnColorsDark = {
    ModuleStatus.installed: Color(0xFFE3E6FF),
    ModuleStatus.enabled: Color(0xFFB4F7DE),
    ModuleStatus.disabled: Color(0xFFC4C7CF),
    ModuleStatus.uninstalled: Color(0xFFFFDAD6),
    ModuleStatus.updateAvailable: Color(0xFFE8E9FF),
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