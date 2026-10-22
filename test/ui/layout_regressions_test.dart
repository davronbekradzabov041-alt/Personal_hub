/// Вёрстка экрана «Модули», нижней навигации и таймлайна.
///
/// Проверяют то, что нельзя убрать «на глаз»: отсутствие двойного
/// тулбара, зазоры между секциями и карточками, просвет под нижним
/// доком и подписи раздела, которые больше не переносятся по слогам.
library layout_regressions_test;

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
import 'package:personal_hub/core/navigation/app_shell.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_scope.dart';
import 'package:personal_hub/modules/accounts/accounts_module.dart';
import 'package:personal_hub/modules/accounts/ui/accounts_screen.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/ui/schedule_screen.dart';
import 'package:personal_hub/ui/screens/modules_screen.dart';
import 'package:personal_hub/ui/widgets/module_store/module_card.dart';

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

  Future<void> installBuiltins() async {
    ModuleRegistry.registerAll([
      ScheduleModule(),
      AccountsModule(),
    ]);
    await ensureBuiltinModulesInstalled(manager, store);
    await persistence.flush();
  }

  Widget scopes(Widget child) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: SearchScope(
          service: searchService,
          child: ModuleStatePersistenceScope(
            persistence: persistence,
            child: ModuleManagerScope(
              manager: manager,
              child: child,
            ),
          ),
        ),
      );

  group('Экран «Модули»', () {
    testWidgets('на телефоне нет второго AppBar — заголовок в контенте',
        (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      // Заголовок «Модули» присутствует, но панелей ровно ноль:
      // оболочка в тесте не подключена, а свой AppBar экран больше
      // не создаёт. В приложении панель даёт AppShell — значит две
      // подряд больше не встречаются.
      expect(find.text('Модули'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
      expect(find.byIcon(Icons.upgrade), findsOneWidget);
    });

    testWidgets('оба действия имеют tooltip и стоят через 8 dp',
        (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Импорт модуля'), findsOneWidget);
      expect(find.byTooltip('Обновить модуль из файла'), findsOneWidget);

      final import = tester.getRect(find.byTooltip('Импорт модуля'));
      final update = tester.getRect(find.byTooltip('Обновить модуль из файла'));
      expect(update.left - import.right, closeTo(8, 0.5));
    });

    testWidgets('три секции с заголовками на месте', (tester) async {
      await installBuiltins();
      // Высокий вьюпорт: ListView ленивый, и нижние секции просто не
      // строятся, пока до них не доскроллишь.
      tester.view.physicalSize = const Size(360, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Установленные'), findsOneWidget);
      expect(find.text('Доступные'), findsOneWidget);
      expect(find.text('Обновления'), findsOneWidget);
      // Оба реальных модуля в «Установленных».
      expect(find.text('Аккаунты'), findsOneWidget);
      expect(find.text('Расписание'), findsOneWidget);
    });

    testWidgets('между секциями 24 dp, под заголовком 12 dp', (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      // «Установленные»: заголовок -> первая карточка = 12 dp.
      final header = tester.getRect(find.text('Установленные'));
      final cards = find.byType(ModuleCard);
      expect(cards, findsWidgets);
      final firstCard = tester.getRect(cards.first);

      expect(firstCard.top - header.bottom, closeTo(12, 1),
          reason: 'под заголовком секции 12 dp');

      // ...последняя карточка секции -> заголовок «Доступные» = 24 dp.
      final nextHeader = tester.getRect(find.text('Доступные'));

      // Ищем последнюю карточку, которая лежит ВЫШЕ заголовка: порядок
      // карточек задаёт реестр (по order модуля), и опираться на
      // конкретное имя здесь значило бы зашить порядок в тест.
      final cardRects = tester
          .widgetList<ModuleCard>(find.byType(ModuleCard))
          .map((card) => tester.getRect(find.byWidget(card)))
          .where((rect) => rect.bottom <= nextHeader.top)
          .toList()
        ..sort((a, b) => b.bottom.compareTo(a.bottom));

      expect(cardRects, isNotEmpty);
      expect(nextHeader.top - cardRects.first.bottom, closeTo(24, 1),
          reason: 'между секциями 24 dp');
    });

    testWidgets('горизонтальный отступ контента — 16 dp', (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView).first);
      final padding = listView.padding as EdgeInsets;
      expect(padding.left, 16);
      expect(padding.right, 16);
      expect(padding.top, 0, reason: 'сверху отступа нет — его даёт панель');
    });

    testWidgets('нижний просвод учитывает высоту дока и системный inset',
        (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const ModulesScreen()));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView).first);
      final padding = listView.padding as EdgeInsets;

      // dock 64 + его нижний отступ 16 + системный inset (в тесте 0) + 16.
      expect(padding.bottom, greaterThanOrEqualTo(64 + 16 + 16));
    });
  });

  group('Нижняя навигация', () {
    testWidgets('подписи раздела не переносятся по слогам', (tester) async {
      await installBuiltins();
      // 360 dp и масштаб текста 1.3 — условия, на которых ломалось.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 3.0; // ~120 dp плотность
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const AppShell()));
      await tester.pumpAndSettle();

      // В компактном доке короткие подписи, а ключевое — одна строка.
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('График'), findsOneWidget);
      expect(find.text('Профили'), findsOneWidget);
      expect(find.text('Модули'), findsOneWidget);

      for (final label in ['Главная', 'График', 'Профили', 'Модули']) {
        final text = tester.widget<Text>(find.text(label).last);
        expect(text.maxLines, 1, reason: '$label должна быть одной строкой');
      }
    });

    testWidgets('в рельсе подписи остаются полными', (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const AppShell()));
      await tester.pumpAndSettle();

      // Ищем ВНУТРИ рельса: слово «Расписание» есть ещё и на карточке
      // модуля в списке «Установленные», и без областей поиска был бы
      // двойной матч.
      final rail = find.byType(NavigationRail);
      expect(
        find.descendant(of: rail, matching: find.text('Расписание')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('Аккаунты')),
        findsOneWidget,
      );
    });

    testWidgets('все разделы доступны для перехода', (tester) async {
      await installBuiltins();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(scopes(const AppShell()));
      await tester.pumpAndSettle();

      // Каждый раздел открывает СВОЙ экран, а не остаётся на Главной.
      await tester.tap(find.text('Профили'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(find.text('Игры'), findsWidgets);

      await tester.tap(find.text('График'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleScreen), findsOneWidget);

      await tester.tap(find.text('Модули'));
      await tester.pumpAndSettle();
      expect(find.text('Установленные'), findsOneWidget);

      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleScreen), findsNothing);
    });
  });
}
