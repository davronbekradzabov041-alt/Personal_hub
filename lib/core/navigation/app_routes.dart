import 'package:flutter/material.dart';
import '../../ui/screens/home_screen.dart';
import '../../ui/screens/settings_screen.dart';
import '../../ui/screens/search_screen.dart';
import '../../ui/screens/modules_screen.dart';
import '../../modules/schedule/ui/schedule_screen.dart';

/// Таблица именованных маршрутов ядра.
///
/// Пока приложение простое, поэтому используется обычная
/// именованная навигация (Navigator 1.0). На Этапе 3, когда
/// появится система модулей, сюда будет добавлена динамическая
/// регистрация маршрутов из каждого модуля (Module.routes),
/// без изменения структуры этого файла.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String settings = '/settings';
  static const String search = '/search';
  static const String modules = '/modules';
  static const String schedule = '/schedule';

  static Map<String, WidgetBuilder> get routes => {
        'home': (context) => const HomeScreen(),
        'settings': (context) => const SettingsScreen(),
        'search': (context) => const SearchScreen(),
        'modules': (context) => const ModulesScreen(),
        'schedule': (context) => const ScheduleScreen(moduleId: 'schedule'),
      };
}
