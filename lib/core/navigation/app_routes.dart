import 'package:flutter/material.dart';
import '../../ui/screens/home_screen.dart';
import '../../ui/screens/settings_screen.dart';
import '../../ui/screens/search_screen.dart';
import '../../ui/screens/modules_screen.dart';
import '../../ui/screens/backup_screen.dart';
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
  static const String backup = '/backup';
  static const String schedule = '/schedule';

  /// Ключи таблицы — те же строки, что и константы выше.
  ///
  /// Раньше здесь были ключи без ведущего слэша ('home', 'settings'),
  /// а константы — с ним ('/', '/settings'). Из-за этого
  /// `pushNamed(AppRoutes.settings)` искал '/settings' и не находил
  /// ничего: имя маршрута и ключ таблицы обязаны совпадать.
  static Map<String, WidgetBuilder> get routes => <String, WidgetBuilder>{
        home: (context) => const HomeScreen(),
        settings: (context) => const SettingsScreen(),
        search: (context) => const SearchScreen(),
        modules: (context) => const ModulesScreen(),
        backup: (context) => const BackupScreen(),
        schedule: (context) => const ScheduleScreen(moduleId: 'schedule'),
      };

  /// Генератор маршрутов для MaterialApp.
  ///
  /// Подключается в app.dart. Именно он делает `pushNamed` рабочим:
  /// без него корневой Navigator не знает ни одного имени и
  /// pushNamed(AppRoutes.schedule) падает. Таблица передаётся
  /// onGenerateRoute, а не `routes:`, потому что `routes` не может
  /// содержать '/' одновременно с `home:` — а `home` у нас это
  /// AppShell, и '/' обязан вести в оболочку, а не в голый HomeScreen.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = routes[settings.name];
    if (builder == null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => _UnknownRouteScreen(routeName: settings.name),
      );
    }
    return MaterialPageRoute(settings: settings, builder: builder);
  }
}

/// Заглушка неизвестного маршрута.
///
/// Раньше неизвестное имя приводило к падению навигатора. Теперь
/// пользователь видит, куда он попал, вместо падения.
class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Страница не найдена')),
      body: Center(
        child: Text('Маршрут не найден: ${routeName ?? '<без имени >'}'),
      ),
    );
  }
}
