import 'package:flutter/material.dart';
import 'app_spacing.dart';

/// Responsive breakpoints Personal Hub.
///
/// Основаны на Material 3 breakpoints с адаптацией под
/// потребности мобильного/планшетного/desktop UI.
class AppBreakpoints {
  AppBreakpoints._();

  // =========================================================================
  // Breakpoint values (width in dp)
  // =========================================================================
  static const double compact = 600;    // phones, small screens
  static const double medium = 840;     // large phones, small tablets (landscape)
  static const double expanded = 1200;  // tablets, small desktop
  static const double large = 1600;     // large desktop

  // =========================================================================
  // Layout types
  // =========================================================================
  static const String layoutCompact = 'compact';
  static const String layoutMedium = 'medium';
  static const String layoutExpanded = 'expanded';
  static const String layoutLarge = 'large';

  // =========================================================================
  // Breakpoint Detection
  // =========================================================================
  static String layoutType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compact) return layoutCompact;
    if (width < medium) return layoutMedium;
    if (width < expanded) return layoutExpanded;
    if (width < large) return layoutLarge;
    return layoutLarge;
  }

  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).width < compact;
  }

  static bool isMedium(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= compact && width < medium;
  }

  static bool isExpanded(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= medium && width < expanded;
  }

  static bool isLarge(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= expanded;
  }

  static bool isTabletOrDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= compact;
  }

  // =========================================================================
  // Grid Helpers
  // =========================================================================
  static int gridColumns(BuildContext context, {int maxColumns = 4}) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compact) return 1;
    if (width < medium) return 2;
    if (width < expanded) return 3;
    if (width < large) return 4;
    return maxColumns;
  }

  static int sliverGridCrossAxisCount(BuildContext context) {
    return gridColumns(context);
  }

  // =========================================================================
  // Screen Padding
  // =========================================================================
  static EdgeInsets screenPadding(BuildContext context) {
    if (isCompact(context)) {
      return const EdgeInsets.all(20);
    } else if (isMedium(context)) {
      return const EdgeInsets.all(24);
    } else if (isExpanded(context)) {
      return const EdgeInsets.all(32);
    } else {
      return const EdgeInsets.all(40);
    }
  }

  // =========================================================================
  // Content Max Width
  // =========================================================================
  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCompact(context)) return double.infinity;
    if (isMedium(context)) return 720;
    if (isExpanded(context)) return 1000;
    return 1200;
  }

  // =========================================================================
  // Drawer / Rail Width
  // =========================================================================
  static double drawerWidth(BuildContext context) {
    if (isCompact(context)) return 304;
    return 304 * 1.25; // wider on tablets
  }

  static double railWidth(BuildContext context) {
    if (isCompact(context)) return 0; // not used on compact
    if (isMedium(context)) return 80; // collapsible
    return 280; // permanent
  }

  // =========================================================================
  // Hero Layout Helper
  // =========================================================================
  static bool useHeroSplit(BuildContext context) {
    return !isCompact(context);
  }

  static double heroHeight(BuildContext context) {
    if (isCompact(context)) return 280;
    if (isMedium(context)) return 300;
    if (isExpanded(context)) return 320;
    return 360;
  }

  static BorderRadius heroBorderRadius(BuildContext context) {
    if (isCompact(context)) return const BorderRadius.vertical(top: Radius.circular(20));
    if (isMedium(context)) return const BorderRadius.vertical(top: Radius.circular(24));
    return const BorderRadius.vertical(top: Radius.circular(28));
  }

  static double heroSplitRatio(BuildContext context) {
    if (isCompact(context)) return 1.0; // stacked
    if (isMedium(context)) return 0.60; // 60/40
    if (isExpanded(context)) return 0.65; // 65/35
    return 0.70; // 70/30
  }

  static NavigationType navigationType(BuildContext context) {
    if (isCompact(context)) return NavigationType.drawer;
    if (isMedium(context)) return NavigationType.collapsibleRail;
    return NavigationType.permanentRail;
  }
}

/// Navigation Type (top-level, not inside class)
enum NavigationType {
  drawer,           // Compact: mobile drawer
  collapsibleRail,  // Medium: collapsible side rail
  permanentRail,    // Expanded/Large: permanent side rail
}

/// LayoutBuilder helper для responsive UI
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext, String) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layoutFromWidth(constraints.maxWidth);
        return builder(context, layout);
      },
    );
  }

  static String _layoutFromWidth(double width) {
    if (width < AppBreakpoints.compact) return AppBreakpoints.layoutCompact;
    if (width < AppBreakpoints.medium) return AppBreakpoints.layoutMedium;
    if (width < AppBreakpoints.expanded) return AppBreakpoints.layoutExpanded;
    return AppBreakpoints.layoutLarge;
  }
}

/// Удобный виджет для условного рендеринга по breakpoint
class BreakpointBuilder extends StatelessWidget {
  final Widget? compact;
  final Widget? medium;
  final Widget? expanded;
  final Widget? large;
  final Widget Function(BuildContext, String)? builder;

  const BreakpointBuilder({
    super.key,
    this.compact,
    this.medium,
    this.expanded,
    this.large,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppBreakpoints.layoutType(context);

    if (builder != null) {
      return builder!(context, layout);
    }

    switch (layout) {
      case AppBreakpoints.layoutCompact:
        return compact ?? const SizedBox.shrink();
      case AppBreakpoints.layoutMedium:
        return medium ?? compact ?? const SizedBox.shrink();
      case AppBreakpoints.layoutExpanded:
        return expanded ?? medium ?? compact ?? const SizedBox.shrink();
      case AppBreakpoints.layoutLarge:
        return large ?? expanded ?? medium ?? compact ?? const SizedBox.shrink();
      default:
        return compact ?? const SizedBox.shrink();
    }
  }
}