/// Design System Personal Hub — единый экспорт всех токенов и компонентов.
///
/// Используй:
/// import 'package:personal_hub/core/design/design_system.dart';
///
/// вместо отдельных импортов.
library design_system;

// Tokens
export 'app_colors.dart';
export 'app_typography.dart';
export 'app_spacing.dart';

// Theme
export 'app_theme.dart';

// Components
export 'app_components.dart';

// Animations
export 'app_animations.dart';

// Breakpoints / Responsive
export 'app_breakpoints.dart';

// Re-export commonly used types
export 'package:flutter/material.dart' show
  BuildContext,
  Widget,
  Color,
  TextStyle,
  EdgeInsets,
  BorderRadius,
  Curve,
  AxisDirection,
  MediaQuery,
  WidgetState,
  WidgetStateProperty,
  RoundedRectangleBorder,
  BorderSide,
  TargetPlatform,
  PageTransitionsBuilder,
  ZoomPageTransitionsBuilder;