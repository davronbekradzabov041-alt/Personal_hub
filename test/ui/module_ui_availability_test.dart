/// Доступность модулей и открытие их UI (Stage 11).
///
/// Проверяют, что зарегистрированные модули Schedule и Accounts
/// действительно РАБОТАЮТ и ОТКРЫВАЮТСЯ.
///
/// До Stage 11 в `AppShell` были жёстко заданные разделы, Accounts
/// достижим только через «Модули» → «Открыть», а именованный маршрут
/// `/accounts` не обрабатывался вложенным Navigator'ом и молча
/// показывал текущий раздел. Здесь фиксируется и обратное: раздел ведёт
/// на экран модуля, а каждый модуль строит свою страницу без исключений.
///
/// Демонстрационный ExampleModule удалён из поставки: настоящие модули
/// проверяют те же механизмы честнее, чем заглушка.
library module_ui_availability_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/builtin_module_installer.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_persistence_scope.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/navigation/app_routes.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_scope.dart';
import 'package:personal_hub/modules/accounts/accounts_module.dart';
import 'package:personal_hub/modules/accounts/ui/accounts_screen.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/ui/schedule_screen.dart';

class _InMemoryStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = {};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

/// Хранилище в памяти, общее на `moduleId`: повторное обращение к
/// одному модулю возвращает те же данные.
class _InMemoryStorage implements ModuleStorage {
  _InMemoryStorage(this._data);

  final Map<String, String> _data;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}

void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _InMemoryStateStore store;
  late ModuleStatePersistence persistence;

  setUp(() {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
    final buckets = <String, Map<String, String>>{};
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: (moduleId) =>
          _InMemoryStorage(buckets.putIfAbsent(moduleId, () => {})),
    );
    store = _InMemoryStateStore();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: (moduleId) =>
          _InMemoryStorage(buckets.putIfAbsent(moduleId, () => {})),
    );
  });

  tearDown(() {
    persistence.dispose();
    manager.dispose();
    ModuleRegistry.clear();
  });

  /// Регистрирует два реальных встроенных модуля и устанавливает их
  /// тем же путём, что и `main()` при первом запуске.
  Future<void> installBuiltins() async {
    ModuleRegistry.registerAll([
      ScheduleModule(),
      AccountsModule(),
    ]);
    await ensureBuiltinModulesInstalled(manager, store);
    await persistence.flush();
  }

  Widget wrap(Widget screen) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: SearchScope(
          service: searchService,
          child: ModuleStatePersistenceScope(
            persistence: persistence,
            child: ModuleManagerScope(
              manager: manager,
              child: screen,
            ),
          ),
        ),
      );

  group('Оба модуля регистрируются и включаются', () {
    test('регистрация: schedule, accounts', () {
      ModuleRegistry.registerAll([
        ScheduleModule(),
        AccountsModule(),
      ]);

      expect(ModuleRegistry.contains('schedule'), isTrue);
      expect(ModuleRegistry.contains('accounts'), isTrue);
    });

    test('установка и включение доводят оба до enabled', () async {
      await installBuiltins();

      expect(manager.stateOf('schedule'), ModuleState.enabled);
      expect(manager.stateOf('accounts'), ModuleState.enabled);
    });

    test('каждый модуль зарегистрирован в поиске ровно один раз', () async {
      await installBuiltins();
      // Два модуля, каждый со своим провайдером — дублей нет.
      expect(searchService.providerCount, 2);
    });
  });

  group('UI модулей открывается', () {
    testWidgets('ScheduleScreen строит экран с тремя вкладками', (tester) async {
      await installBuiltins();

      await tester.pumpWidget(
        wrap(const ScheduleScreen(moduleId: 'schedule')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Расписание'), findsOneWidget);
      expect(find.text('Сегодня'), findsWidgets);
      expect(find.text('Календарь'), findsWidgets);
      expect(find.text('Категории'), findsWidgets);
    });

    testWidgets('AccountsScreen строит экран с тремя вкладками', (tester) async {
      await installBuiltins();

      await tester.pumpWidget(
        wrap(const AccountsScreen(moduleId: 'accounts')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Аккаунты'), findsWidgets);
      expect(find.text('Игры'), findsWidgets);
      expect(find.text('Категории'), findsWidgets);
    });
  });

  group('Маршрут /accounts', () {
    test('зарегистрирован в таблице маршрутов', () {
      expect(AppRoutes.accounts, '/accounts');
      expect(AppRoutes.routes.containsKey(AppRoutes.accounts), isTrue);
    });

    testWidgets('onGenerateRoute строит AccountsScreen, а не экран ошибки',
        (tester) async {
      late BuildContext capturedContext;
      late Widget page;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: SearchScope(
            service: searchService,
            child: ModuleManagerScope(
              manager: manager,
              child: Builder(
                builder: (context) {
                  capturedContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final route = AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.accounts),
      );
      page = (route as MaterialPageRoute).builder(capturedContext);

      expect(route, isA<MaterialPageRoute>());
      expect(page, isA<AccountsScreen>());
      expect((page as AccountsScreen).moduleId, 'accounts');
    });

    testWidgets('onGenerateRoute для /schedule строит ScheduleScreen',
        (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: SearchScope(
            service: searchService,
            child: ModuleManagerScope(
              manager: manager,
              child: Builder(
                builder: (context) {
                  capturedContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final route = AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.schedule),
      );
      final page = (route as MaterialPageRoute).builder(capturedContext);

      expect(page, isA<ScheduleScreen>());
    });

    testWidgets('неизвестный маршрут ведёт на экран ошибки, не бросает',
        (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      final route = AppRoutes.onGenerateRoute(
        const RouteSettings(name: '/no-such-route'),
      );

      expect(route, isA<MaterialPageRoute>());
      expect(
        (route as MaterialPageRoute).builder(capturedContext),
        isNotNull,
      );
    });
  });
}
