import 'package:flutter/material.dart';

/// Цветовая система Personal Hub v2.
///
/// Основана на спецификации v2:
/// - Light: тёплый минеральный холст (#F7F6F2), матовые поверхности (#FFFFFF),
///   тонкий контур (#E8E6DF) и глубокий чернильно-графитовый Brand Primary (#1F2438).
/// - Dark: обсидиановый холст (#111215), ступенчатая глубина поверхностей
///   (Base #18191E, Elevated #21232A) и фантомный 7% контур.
class AppColors {
  AppColors._();

  // =========================================================================
  // Brand Lead Color (v2 Deep Ink Indigo / Night Steel)
  // =========================================================================
  static const Color brandPrimary = Color(0xFF1F2438);      // Deep Ink
  static const Color brandPrimaryDark = Color(0xFFE6E8F0);  // Night Steel

  // =========================================================================
  // v2 Structural Tokens (Light & Dark)
  // =========================================================================
  static const Color canvasLight = Color(0xFFF7F6F2);
  static const Color canvasDark = Color(0xFF111215);

  static const Color surfaceBaseLight = Color(0xFFFFFFFF);
  static const Color surfaceBaseDark = Color(0xFF18191E);

  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedDark = Color(0xFF21232A);

  static const Color borderSubtleLight = Color(0xFFE8E6DF);
  static const Color borderSubtleDark = Color(0x12FFFFFF); // rgba(255, 255, 255, 0.07)

  static const Color borderStrongLight = Color(0xFF1C1D21);
  static const Color borderStrongDark = Color(0x40FFFFFF); // rgba(255, 255, 255, 0.25)

  static const Color textPrimaryLight = Color(0xFF16171A);
  static const Color textPrimaryDark = Color(0xFFEDEDF0);

  static const Color textSecondaryLight = Color(0xFF767982);
  static const Color textSecondaryDark = Color(0xFF9195A1);

  static const Color textTertiaryLight = Color(0xFFA4A7AF);
  static const Color textTertiaryDark = Color(0xFF585C66);

  // =========================================================================
  // Light ColorScheme (Personal Hub v2 Warm Mineral)
  // =========================================================================
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1F2438),           // Deep Ink
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF0EDE6),  // Warm subtle container
    onPrimaryContainer: Color(0xFF16171A),
    secondary: Color(0xFF686B73),         // Neutral Slate
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE8E6DF), // Subtle surface wash
    onSecondaryContainer: Color(0xFF16171A),
    tertiary: Color(0xFF1B7F5A),          // Success Jade / Pine
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE9F6F0),
    onTertiaryContainer: Color(0xFF00211A),
    error: Color(0xFFC93B3B),             // Matte Carmine
    onError: Colors.white,
    errorContainer: Color(0xFFFDF1F1),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFFFFF),           // Surface Base
    onSurface: Color(0xFF16171A),         // Text Primary
    surfaceContainerHighest: Color(0xFFE8E6DF), // Border Subtle / Dividers
    onSurfaceVariant: Color(0xFF767982),  // Text Secondary
    outline: Color(0xFF767982),
    outlineVariant: Color(0xFFE8E6DF),    // Border Subtle
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFF16171A),
    onInverseSurface: Color(0xFFEDEDF0),
    inversePrimary: Color(0xFFE6E8F0),
  );

  // =========================================================================
  // Dark ColorScheme (Personal Hub v2 Nocturnal Depth)
  // =========================================================================
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE6E8F0),           // High readability steel
    onPrimary: Color(0xFF111215),
    primaryContainer: Color(0xFF21232A),  // Surface Elevated
    onPrimaryContainer: Color(0xFFEDEDF0),
    secondary: Color(0xFF8E929C),         // Matte light slate
    onSecondary: Color(0xFF111215),
    secondaryContainer: Color(0xFF21232A),
    onSecondaryContainer: Color(0xFFEDEDF0),
    tertiary: Color(0xFF34D399),          // Soft Neon Jade
    onTertiary: Color(0xFF0A2E20),
    tertiaryContainer: Color(0x1F34D399),
    onTertiaryContainer: Color(0xFF34D399),
    error: Color(0xFFF87171),             // Pastel Coral
    onError: Color(0xFF450A0A),
    errorContainer: Color(0x1FF87171),
    onErrorContainer: Color(0xFFF87171),
    surface: Color(0xFF18191E),           // Surface Base
    onSurface: Color(0xFFEDEDF0),         // Text Primary
    surfaceContainerHighest: Color(0xFF21232A), // Surface Elevated
    onSurfaceVariant: Color(0xFF9195A1),  // Text Secondary
    outline: Color(0xFF585C66),           // Text Tertiary
    outlineVariant: Color(0x12FFFFFF),    // Border Subtle (7% white)
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFEDEDF0),
    onInverseSurface: Color(0xFF111215),
    inversePrimary: Color(0xFF1F2438),
  );

  // =========================================================================
  // Semantic Colors (Light)
  // =========================================================================
  static const Color semanticSuccess = Color(0xFF1B7F5A);
  static const Color semanticSuccessContainer = Color(0xFFE9F6F0);
  static const Color semanticWarning = Color(0xFFC27803);    // Warm Honey Amber
  static const Color semanticWarningContainer = Color(0xFFFEF7EC);
  static const Color semanticError = Color(0xFFC93B3B);
  static const Color semanticErrorContainer = Color(0xFFFDF1F1);

  // =========================================================================
  // Semantic Colors (Dark)
  // =========================================================================
  static const Color semanticSuccessDark = Color(0xFF34D399);
  static const Color semanticSuccessContainerDark = Color(0x1F34D399);
  static const Color semanticWarningDark = Color(0xFFFBBF24); // Warm Gold
  static const Color semanticWarningContainerDark = Color(0x1FFBBF24);
  static const Color semanticErrorDark = Color(0xFFF87171);
  static const Color semanticErrorContainerDark = Color(0x1FF87171);

  // =========================================================================
  // Module Accents (Curated Functional Pigments v2)
  // =========================================================================
  static const Color accentIndigo = Color(0xFF1F2438);   // Core Lead / System
  static const Color accentAmber = Color(0xFFD97706);    // Schedule / Time
  static const Color accentTeal = Color(0xFF0D9488);     // Files / Storage
  static const Color accentSlate = Color(0xFF475569);    // Accounts / Security
  static const Color accentEmerald = Color(0xFF059669);  // Finance
  static const Color accentRose = Color(0xFFE11D48);     // Personal
  static const Color accentViolet = Color(0xFF7C3AED);   // Catalog / Knowledge
  static const Color accentBlue = Color(0xFF2563EB);     // Wi-Fi / Network

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
    ModuleStatus.installed: Color(0xFFF0EDE6),
    ModuleStatus.enabled: Color(0xFFE9F6F0),
    ModuleStatus.disabled: Color(0xFFE8E6DF),
    ModuleStatus.uninstalled: Color(0xFFFDF1F1),
    ModuleStatus.updateAvailable: Color(0xFFFEF7EC),
  };

  static const Map<ModuleStatus, Color> statusOnColorsLight = {
    ModuleStatus.installed: Color(0xFF16171A),
    ModuleStatus.enabled: Color(0xFF1B7F5A),
    ModuleStatus.disabled: Color(0xFF767982),
    ModuleStatus.uninstalled: Color(0xFFC93B3B),
    ModuleStatus.updateAvailable: Color(0xFFC27803),
  };

  // =========================================================================
  // Module Status Colors (Dark)
  // =========================================================================
  static const Map<ModuleStatus, Color> statusColorsDark = {
    ModuleStatus.installed: Color(0xFF21232A),
    ModuleStatus.enabled: Color(0x1F34D399),
    ModuleStatus.disabled: Color(0xFF21232A),
    ModuleStatus.uninstalled: Color(0x1FF87171),
    ModuleStatus.updateAvailable: Color(0x1FFBBF24),
  };

  static const Map<ModuleStatus, Color> statusOnColorsDark = {
    ModuleStatus.installed: Color(0xFFEDEDF0),
    ModuleStatus.enabled: Color(0xFF34D399),
    ModuleStatus.disabled: Color(0xFF9195A1),
    ModuleStatus.uninstalled: Color(0xFFF87171),
    ModuleStatus.updateAvailable: Color(0xFFFBBF24),
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