/// Регрессии AUD-02, AUD-06 и AUD-12.
///
/// AUD-02: HomeScreen присваивал `late final ScheduleRepository` в
/// didChangeDependencies, который вызывается и при смене темы —
/// экран падал с LateInitializationError.
///
/// AUD-06/AUD-12: именованные маршруты не были подключены к
/// MaterialApp, ключи таблицы не совпадали с константами, а
/// вложенный Navigator оболочки игнорировал settings.name.
library navigation_regression_test;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/database/repositories/app_settings_repository.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/navigation/app_routes.dart';
import 'package:personal_hub/core/navigation/app_shell.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_scope.dart';
import 'package:personal_hub/core/settings/app_settings_controller.dart';
import 'package:personal_hub/core/settings/app_settings_scope.dart';
import 'package:personal_hub/core/theme/app_theme.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/ui/schedule_screen.dart';
import 'package:personal_hub/ui/backup/backup_file_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/backup_services_scope.dart';
import 'package:personal_hub/ui/screens/backup_screen.dart';
import 'package:personal_hub/ui/screens/home_screen.dart';
import 'package:personal_hub/ui/screens/modules_screen.dart';
import 'package:personal_hub/ui/screens/search_screen.dart';
import 'package:personal_hub/ui/screens/settings_screen.dart';
import 'package:personal_hub/ui/screens/startup_error_screen.dart';

class _InMemoryModuleStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}

/// Типизированная заглушка gateway.
///
/// Раньше здесь был `dynamic noSuchMethod`, бросающий
/// UnimplementedError. Это скрывало настоящий контракт: подпись любого
/// метода [BackupGateway] можно было изменить, и компилятор молчал —
/// тест продолжал «проходить», упираясь в ошибку только в момент
/// вызова. Теперь заглушка реализует контракт явно: сигнатуры
/// проверяются компилятором, а «сюда не должны попадать» выражено
/// обычным исключением в конкретном методе.
///
/// Операции backup в этом файле не вызываются — нужен только факт
/// присутствия BackupServicesScope в дереве виджетов.
class _StubBackupGateway implements BackupGateway {
  @override
  Future<List<String>> installedModuleIds() async =>
      // BackupScreen запрашивает список модулей при открытии, поэтому
      // для навигационного теста нужен реальный (пустой) ответ.
      <String>[];

  @override
  String displayNameOf(String moduleId) =>
      throw UnsupportedError('backup в navigation-тестах не используется');

  @override
  Future<BackupArtifact> createGlobalBackup(GlobalBackupSelection selection) =>
      throw UnsupportedError('backup в navigation-тестах не используется');

  @override
  Future<BackupArtifact> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  ) =>
      throw UnsupportedError('backup в navigation-тестах не используется');

  @override
  Future<BackupPreview> inspectGlobalBackup(List<int> archiveBytes) =>
      throw UnsupportedError('backup в navigation-тестах не используется');

  @override
  Future<BackupPreview> inspectModuleBackup(List<int> archiveBytes) =>
      throw UnsupportedError('backup в navigation-тестах не используется');

  @override
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) =>
      throw UnsupportedError('backup в navigation-тестах не используется');
}

String _manifestJson(String id) => jsonEncode({
      'id': id,
      'name': 'Module $id',
      'version': '1.0.0',
      'apiVersion': 1,
      'author': 'Test',
      'description': 'Navigation regression module',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': 'assets/icon.png',
    });

void main() {
  late ModuleManager _manager;
  late GlobalSearchService _searchService;
  late AppSettingsController _settingsController;
  late GlobalKey<NavigatorState> _rootNavigatorKey;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson('schedule'))),
      ),
    );
    _searchService = GlobalSearchService();
    _manager = ModuleManager(
      searchService: _searchService,
      storageFactory: (moduleId) => _InMemoryModuleStorage(),
    );
    // Контроллер не загружает настройки: load() ходит в Isar, который
    // в widget-тестах недоступен. Само создание Isar не трогает.
    _settingsController = AppSettingsController(AppSettingsRepository());
    _rootNavigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    ModuleRegistry.clear();
  });

  Widget _scopes(Widget child) {
    return AppSettingsScope(
      controller: _settingsController,
      child: SearchScope(
        service: _searchService,
        child: ModuleManagerScope(
          manager: _manager,
          child: BackupServicesScope(
            gateway: _StubBackupGateway(),
            fileService: const PickerBackupFileService(),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _appShellApp() {
    return _scopes(
      MaterialApp(
        navigatorKey: _rootNavigatorKey,
        theme: AppTheme.light,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        home: const AppShell(),
      ),
    );
  }

  group('AUD-02: HomeScreen и didChangeDependencies', () {
    testWidgets('смена темы не роняет HomeScreen', (tester) async {
      await tester.pumpWidget(
        _scopes(
          MaterialApp(
            theme: AppTheme.light,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      // Смена темы — это смена InheritedWidget, из-за чего
      // didChangeDependencies вызывается повторно.
      await tester.pumpWidget(
        _scopes(
          MaterialApp(
            theme: AppTheme.dark,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('HomeScreen переживает смену MediaQuery', (tester) async {
      Widget app(Size size) {
        return MediaQuery(
          data: MediaQueryData(size: size),
          child: _scopes(
            MaterialApp(
              theme: AppTheme.light,
              home: const HomeScreen(),
            ),
          ),
        );
      }

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app(const Size(1200, 1600)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(app(const Size(500, 900)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('AUD-05: экран ошибки запуска', () {
    testWidgets('показывает понятное сообщение', (tester) async {
      await tester.pumpWidget(const StartupErrorScreen());
      await tester.pumpAndSettle();

      expect(find.text('Не удалось запустить приложение'), findsOneWidget);
      expect(find.byType(StartupErrorScreen), findsOneWidget);
    });

    testWidgets('не раскрывает технические детали', (tester) async {
      await tester.pumpWidget(const StartupErrorScreen());
      await tester.pumpAndSettle();

      // Ни стектрейса, ни имён классов ошибки на экране быть не должно.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('#0'), findsNothing);
    });

    testWidgets('повторная попытка вызывается по кнопке', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupErrorScreen(onRetry: () async => retries++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Повторить запуск'));
      await tester.pumpAndSettle();

      expect(retries, 1);
    });
  });

  group('AUD-06/AUD-12: именованная навигация', () {
    testWidgets('по умолчанию открыт Home', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ModulesScreen), findsNothing);
      expect(find.byType(ScheduleScreen), findsNothing);
    });

    testWidgets('пункт «Модули» открывает Modules', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Модули'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ModulesScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('пункт «Расписание» открывает Schedule', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Расписание'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('CTA «Открыть расписание» открывает Schedule', (tester) async {
      // CTA живёт в Home-секции модуля Schedule, а секция появляется
      // только у АКТИВНОГО модуля. Фикстура setUp регистрирует под id
      // 'schedule' внешний пакет (ExternalModuleAdapter), у которого
      // по определению нет своего UI, и состояния у него нет вовсе —
      // поэтому для этой проверки нужен настоящий встроенный
      // ScheduleModule, включённый через lifecycle.
      //
      // Проверяемое здесь свойство не изменилось: именованный переход
      // с главного экрана открывает Schedule.
      ModuleRegistry.clear();
      ModuleRegistry.register(ScheduleModule());
      await _manager.install('schedule');
      await _manager.enable('schedule');

      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      final cta = find.text('Открыть расписание');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleScreen), findsOneWidget);
    });

    testWidgets('pushNamed открывает Settings', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      _rootNavigatorKey.currentState!.pushNamed(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('pushNamed открывает Search', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      _rootNavigatorKey.currentState!.pushNamed(AppRoutes.search);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('pushNamed открывает Modules', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      _rootNavigatorKey.currentState!.pushNamed(AppRoutes.modules);
      await tester.pumpAndSettle();

      expect(find.byType(ModulesScreen), findsOneWidget);
    });

    testWidgets('back из Settings возвращает на Home', (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      _rootNavigatorKey.currentState!.pushNamed(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      _rootNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets(
        'Настройки → «Резервные копии» открывает BackupScreen по AppRoutes.backup',
        (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      // Settings открывается тем же корневым механизмом, что и в
      // AppShell._onSecondaryDestinationSelected.
      _rootNavigatorKey.currentState!.pushNamed(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Плитка живёт внизу списка настроек и строится лениво, поэтому
      // скроллим явно к Scrollable самого SettingsScreen: в дереве
      // одновременно лежит оболочка со своими скроллами.
      final tile = find.text('Резервные копии');
      await tester.scrollUntilVisible(
        tile,
        250,
        scrollable: find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(BackupScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);

      // Backup открыт маршрутом на том же корневом Navigator, поэтому
      // Back возвращает на Settings, а не выходит из приложения.
      _rootNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(BackupScreen), findsNothing);
    });

    test('ключи таблицы маршрутов совпадают с константами', () {
      for (final entry in AppRoutes.routes.entries) {
        expect(
          entry.key,
          anyOf(
            AppRoutes.home,
            AppRoutes.settings,
            AppRoutes.search,
            AppRoutes.modules,
            AppRoutes.backup,
            AppRoutes.schedule,
            AppRoutes.accounts,
          ),
          reason: 'ключ ${entry.key} не является именем маршрута ядра',
        );
      }
      expect(AppRoutes.routes.containsKey(AppRoutes.home), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.settings), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.search), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.modules), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.schedule), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.backup), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.accounts), isTrue);
    });
  });

  // UI-02: вложенный Navigator оболочки должен участвовать в
  // системном Back. Без NavigatorPopHandler Back уходил в корневой
  // Navigator и закрывал приложение, даже когда внутри оболочки был
  // собственный маршрут — то есть вернуться назад из вложенного
  // экрана было невозможно.
  group('UI-02: системный Back во вложенном Navigator', () {
    /// Вложенный Navigator оболочки: он лежит ПОД корневым, поэтому
    /// обычный find.byType(Navigator) даёт корневой. Берём последний
    /// Navigator в поддереве AppShell — это и есть вложенный.
    NavigatorState shellNavigatorState(WidgetTester tester) {
      final nested = find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(Navigator),
      );
      final element = tester.element(nested.last);
      return Navigator.of(element);
    }

    /// Кладёт простой экран поверх раздела внутри вложенного Navigator
    /// оболочки — как это делает, например, форма события в Schedule.
    Future<void> pushNestedRoute(WidgetTester tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      unawaited(
        shellNavigatorState(tester).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Вложенный экран')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Вложенный экран'), findsOneWidget);
    }

    testWidgets('Back закрывает вложенный маршрут, а не корневой',
        (tester) async {
      await pushNestedRoute(tester);

      // Системная кнопка «Назад».
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue,
          reason: 'Back обязан быть обработан вложенным Navigator');
      expect(find.text('Вложенный экран'), findsNothing,
          reason: 'Back обязан закрыть маршрут внутри оболочки');

      // Оболочка и её корневой маршрут раздела остались на месте —
      // приложение не закрылось и не потеряло раздел.
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('Back на корневом маршруте раздела не ломает выход',
        (tester) async {
      await tester.pumpWidget(_appShellApp());
      await tester.pumpAndSettle();

      // Вложенных маршрутов нет: Back должен дойти до корневого
      // Navigator и закрыть приложение, как и раньше.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isFalse,
          reason: 'на корневом маршруте раздела Back обязан дойти до корня');
    });

    testWidgets('Back закрывает верхний из нескольких вложенных маршрутов',
        (tester) async {
      await pushNestedRoute(tester);

      unawaited(
        shellNavigatorState(tester).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('Второй вложенный'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Второй вложенный'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Второй вложенный'), findsNothing);
      expect(find.text('Вложенный экран'), findsOneWidget,
          reason: 'Back обязан закрыть только верхний вложенный маршрут');
      expect(find.byType(AppShell), findsOneWidget);
    });
  });
}
