import 'package:flutter/material.dart';
import 'app_spacing.dart';

/// Анимации и переходы Personal Hub.
class AppAnimations {
  AppAnimations._();

  // Page Transitions - use standard Material page transitions
  static final PageTransitionsBuilder fadeThroughBuilder = ZoomPageTransitionsBuilder();

  // Staggered list animation
  static Widget staggeredList({
    required List<Widget> children,
    Duration delay = AppSpacing.staggerDelay,
    Duration duration = AppSpacing.durationMedium,
    Curve curve = Curves.easeOutCubic,
    int maxStagger = AppSpacing.maxStaggerItems,
    AxisDirection direction = AxisDirection.down,
  }) {
    return Column(
      children: List.generate(children.length, (index) {
        final effectiveIndex = index < maxStagger ? index : maxStagger - 1;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: duration + (delay * effectiveIndex),
          curve: curve,
          builder: (context, value, child) {
            return Transform.translate(
              offset: _getOffset(direction, value),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: children[index],
        );
      }),
    );
  }

  static Offset _getOffset(AxisDirection direction, double value) {
    switch (direction) {
      case AxisDirection.up:
        return Offset(0, 20 * (1 - value));
      case AxisDirection.down:
        return Offset(0, -20 * (1 - value));
      case AxisDirection.left:
        return Offset(20 * (1 - value), 0);
      case AxisDirection.right:
        return Offset(-20 * (1 - value), 0);
    }
  }

  // Animated switch for module state
  static Widget animatedStateTransition({
    required Widget child,
    required bool isActive,
    Duration duration = AppSpacing.durationStandard,
    Curve curve = Curves.easeInOut,
  }) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: curve,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(isActive),
        child: child,
      ),
    );
  }

  // Reduced motion support
  static bool shouldReduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    // Check for disableAnimations (available in all versions)
    return mediaQuery.disableAnimations;
  }

  static Duration getDuration(BuildContext context, Duration base) {
    return shouldReduceMotion(context) ? Duration.zero : base;
  }

  // Page transition duration with reduced motion support
  static Duration pageTransitionDuration(BuildContext context) {
    return getDuration(context, AppSpacing.durationStandard);
  }
}