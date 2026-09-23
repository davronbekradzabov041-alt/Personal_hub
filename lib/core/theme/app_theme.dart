import 'package:flutter/material.dart';
import '../design/app_theme.dart' as design_theme;

/// Централизованное определение темы приложения.
///
/// Все экраны и модули берут стили отсюда, а не задают
/// свои цвета вручную. Это позволяет на Этапе 4 добавить
/// переключение тем без изменения остального кода.
class AppTheme {
  AppTheme._();

  static ThemeData get light => design_theme.AppTheme.light;
  static ThemeData get dark => design_theme.AppTheme.dark;
}
