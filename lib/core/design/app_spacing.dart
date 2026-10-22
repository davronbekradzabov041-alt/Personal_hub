import 'package:flutter/material.dart';

// Импорт намеренный: AppInsets.screen(context) делегирует в
// AppBreakpoints, чтобы остаться единственной точкой входа для
// отступов экрана. Кольцевая зависимость между библиотеками одного
// пакета в Dart легальна — разрешается на уровне имён, а не файлов.
import 'app_breakpoints.dart';

/// Система отступов, радиусов, высот и границ Personal Hub.
///
/// Все значения основаны на 8px grid (Material 3 baseline).
class AppSpacing {
  AppSpacing._();

  // =========================================================================
  // Spacing Rhythm Scale (8px base)
  // =========================================================================
  static const double space0 = 0;      // Tight internal
  static const double space1 = 4;      // Micro: icon gaps, chip internal
  static const double space2 = 8;      // Small: button internal, chip gap
  static const double space3 = 12;     // Compact: card internal (small)
  static const double space4 = 16;     // Standard: item gap, card internal
  static const double space5 = 20;     // Comfortable: card internal (medium)
  static const double space6 = 24;     // Block internal, section internal
  static const double space7 = 32;     // Block gap, Hero internal
  static const double space8 = 40;     // Large block gap
  static const double space9 = 48;     // Major section gap, Hero vertical
  static const double space10 = 64;    // Screen-level, page margins (tablet+)

  // Legacy aliases for backward compatibility
  static const double xs = space1;
  static const double sm = space2;
  static const double md = space4;
  static const double lg = space6;
  static const double xl = space7;
  static const double xxl = space9;

  // =========================================================================
  // Component-specific dimensions
  // =========================================================================
  static const double listTileMinHeight = 56;  // Material 3 minimum touch target
  static const double buttonMinHeight = 44;    // Button minimum height (updated from 40)
  static const double fabSize = 56;            // FAB standard size
  static const double fabMiniSize = 40;        // Mini FAB
  static const double drawerWidth = 304;       // Standard navigation drawer width
  static const double railWidth = 80;          // Navigation rail width
  static const double appBarHeight = 64;       // Standard AppBar height

  // =========================================================================
  // Нижняя навигация — плавающий док (_FloatingIslandDock в AppShell)
  // =========================================================================
  //
  // Вынесены сюда, чтобы экраны не дублировали магические числа:
  // просвет снизу считается из тех же констант, что и сам док.
  static const double dockHeight = 64;        // высота панели дока
  static const double dockBottomMargin = 16;  // его отступ от нижней кромки

  // =========================================================================
  // Elevation (for backward compatibility with ThemeData)
  // =========================================================================
  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 3;
  static const double elevation3 = 6;
  static const double elevation4 = 12;
  static const double elevation5 = 24;

  // =========================================================================
  // Animation durations
  // =========================================================================
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationStandard = Duration(milliseconds: 200);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // Stagger delays for list animations
  static const Duration staggerDelay = Duration(milliseconds: 50);
  static const int maxStaggerItems = 10; // Limit stagger for performance
}

/// Удобные EdgeInsets helpers
class AppInsets {
  static const EdgeInsets space0 = EdgeInsets.all(AppSpacing.space0);
  static const EdgeInsets space1 = EdgeInsets.all(AppSpacing.space1);
  static const EdgeInsets space2 = EdgeInsets.all(AppSpacing.space2);
  static const EdgeInsets space3 = EdgeInsets.all(AppSpacing.space3);
  static const EdgeInsets space4 = EdgeInsets.all(AppSpacing.space4);
  static const EdgeInsets space5 = EdgeInsets.all(AppSpacing.space5);
  static const EdgeInsets space6 = EdgeInsets.all(AppSpacing.space6);
  static const EdgeInsets space7 = EdgeInsets.all(AppSpacing.space7);
  static const EdgeInsets space8 = EdgeInsets.all(AppSpacing.space8);
  static const EdgeInsets space9 = EdgeInsets.all(AppSpacing.space9);
  static const EdgeInsets space10 = EdgeInsets.all(AppSpacing.space10);

  // Legacy aliases for backward compatibility
  static const EdgeInsets xs = space1;
  static const EdgeInsets sm = space2;
  static const EdgeInsets md = space4;
  static const EdgeInsets lg = space6;
  static const EdgeInsets xl = space7;
  static const EdgeInsets xxl = space9;

  static const EdgeInsets horizontalSpace4 = EdgeInsets.symmetric(horizontal: AppSpacing.space4);
  static const EdgeInsets horizontalSpace6 = EdgeInsets.symmetric(horizontal: AppSpacing.space6);
  static const EdgeInsets horizontalSpace7 = EdgeInsets.symmetric(horizontal: AppSpacing.space7);

  static const EdgeInsets verticalSpace2 = EdgeInsets.symmetric(vertical: AppSpacing.space2);
  static const EdgeInsets verticalSpace3 = EdgeInsets.symmetric(vertical: AppSpacing.space3);
  static const EdgeInsets verticalSpace6 = EdgeInsets.symmetric(vertical: AppSpacing.space6);

  static const EdgeInsets cardPadding = EdgeInsets.all(AppSpacing.space4);
  static const EdgeInsets cardPaddingMedium = EdgeInsets.all(AppSpacing.space5);

  /// Единый стандарт отступов экрана (Stage 11).
  ///
  /// До Stage 11 каждый экран выбирал отступ сам: Home и секции
  /// модулей использовали `AppSpacing.space7` (32), «Модули» —
  /// `AppBreakpoints.screenPadding` (20/24/32/40), Настройки/Поиск/
  /// Бэкап и все экраны Schedule и Accounts — `AppInsets.md` (16), а
  /// StartupErrorScreen — литерал 24. На одном телефоне боковые
  /// отступы получались 16 и 32 одновременно.
  ///
  /// Теперь единственный источник — [AppBreakpoints.screenPadding]:
  /// адаптивный по ширине и общий для всех экранов и модулей.
  /// `screenPadding` ниже оставлен как константа 16 для внутренних
  /// контейнеров, где ширина экрана недоступна (диалоги, popup).
  static const EdgeInsets screenPadding = EdgeInsets.all(AppSpacing.space4);

  /// Единый стандарт отступов тела экрана (Stage 11).  ///
  /// Адаптивные БОКОВЫЕ отступы — общие для главной страницы, модулей,
  /// настроек, поиска, резервных копий, Schedule и Accounts — плюс
  /// прежняя вертикальная ритмика (16).
  ///
  /// Вертикальная часть намеренно НЕ адаптируется: непоследовательными
  /// были именно боковые отступы (аудит Stage 10: Home 32, «Модули» 20,
  /// остальные экраны 16). А вот высота прокручиваемого тела влияет на
  /// то, что попадает в первый экран: меняя её, мы сдвигаем содержимое
  /// относительно нижней грани viewport — этого делать незачем.
  ///
  /// Вызывать в корневом `padding:` прокручиваемого тела экрана и
  /// вкладок. Не const — зависит от `MediaQuery`.
  static EdgeInsets screenBody(BuildContext context) {
    final side = AppBreakpoints.screenPadding(context);
    return EdgeInsets.only(
      left: side.left,
      right: side.right,
      top: AppSpacing.space4,
      bottom: AppSpacing.space4,
    );
  }

  /// Отступ экрана, адаптивный по ширине (Stage 11).
  ///
  /// Вызывать вместо [screenPadding] во всех корневых `padding:`
  /// экранов и вкладок. Не const — зависит от `MediaQuery`.
  static EdgeInsets screen(BuildContext context) =>
      AppBreakpoints.screenPadding(context);

  /// Нижний просвет, который обязан оставить прокручиваемый экран,
  /// чтобы последний элемент не уезжал под плавающий док.
  ///
  /// Складывается из высоты дока + его нижнего отступа + системного
  /// нижнего inset + 16 dp. Системный inset учитывается ровно один раз:
  /// док получает его через собственный `SafeArea` и НЕ уменьшает
  /// область контента, поэтому просчитать его обязан сам экран.
  static EdgeInsets dockClearance(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.only(
      bottom: AppSpacing.dockHeight +
          AppSpacing.dockBottomMargin +
          inset +
          AppSpacing.space4,
    );
  }

  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.space4,
    vertical: AppSpacing.space2,
  );
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.space4,
    vertical: AppSpacing.space3,
  );
}

/// BorderRadius helpers
class AppRadii {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(Radius.circular(AppRadiiValues.xs));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(AppRadiiValues.sm));
  static const BorderRadius md = BorderRadius.all(Radius.circular(AppRadiiValues.md));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(AppRadiiValues.lg));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(AppRadiiValues.xl));
  static const BorderRadius xxl = BorderRadius.all(Radius.circular(AppRadiiValues.xxl));
  static const BorderRadius full = BorderRadius.all(Radius.circular(AppRadiiValues.full));

  // Top-only radius for bottom sheets and hero
  static const BorderRadius topLg = BorderRadius.vertical(top: Radius.circular(AppRadiiValues.lg));
  static const BorderRadius topXl = BorderRadius.vertical(top: Radius.circular(AppRadiiValues.xl));
  static const BorderRadius topXxl = BorderRadius.vertical(top: Radius.circular(AppRadiiValues.xxl));

  // Responsive radius getters
  static BorderRadius heroTop(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return topLg;           // compact: 16
    if (width < 840) return topXl;           // medium: 20
    if (width < 1200) return topXxl;         // expanded: 24
    return topXxl;                           // large: 24
  }

  static BorderRadius featureCard(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return BorderRadius.all(Radius.circular(AppRadiiValues.md));   // 12
    if (width < 840) return BorderRadius.all(Radius.circular(14));                  // 14
    return BorderRadius.all(Radius.circular(AppRadiiValues.lg));                    // 16
  }

  static BorderRadius buttonInput(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 840) return BorderRadius.all(Radius.circular(AppRadiiValues.sm));   // 8
    return BorderRadius.all(Radius.circular(10));                                   // 10
  }
}

/// Radius values for easy reference
class AppRadiiValues {
  static const double none = 0;
  static const double xs = 4;      // Tiny chips, avatar
  static const double sm = 8;      // Buttons, inputs, chips, small cards
  static const double md = 12;     // Feature cards (compact), inline panels
  static const double lg = 16;     // Feature cards (medium/expanded), dialogs, sheets
  static const double xl = 20;     // Hero top corners, modal, bottom sheet
  static const double xxl = 24;    // Large hero (tablet/desktop)
  static const double xxxl = 28;   // Extra large hero
  static const double full = 9999; // Pills, avatar, FAB
}

/// Elevation levels
class AppElevation {
  static const double level0 = 0;
  static const double level1 = 1;    // Feature Card (rest)
  static const double level2 = 2;    // Feature Card (hover/press)
  static const double level3 = 4;    // Modal, Dropdown, FAB
  static const double level4 = 8;    // Bottom Sheet, Popover
  static const double level5 = 16;   // Full-screen modal

  static double getLight(int level) {
    switch (level) {
      case 0: return level0;
      case 1: return level1;
      case 2: return level2;
      case 3: return level3;
      case 4: return level4;
      case 5: return level5;
      default: return level0;
    }
  }

  static double getDark(int level) {
    // 50% reduction for dark mode
    switch (level) {
      case 0: return 0;
      case 1: return 0.5;
      case 2: return 1;
      case 3: return 2;
      case 4: return 4;
      case 5: return 8;
      default: return 0;
    }
  }
}

/// Border widths
class AppBorders {
  static const double hairline = 0.5;  // Dividers, list separators
  static const double thin = 1;        // Input, outline surface, feature card
  static const double medium = 2;      // Focus ring, accent border
  static const double thick = 3;       // Selected feature card accent
}