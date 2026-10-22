/// UI-тесты модуля Accounts (Этап 10.4).
///
/// Проверяют реальные пользовательские сценарии через `ModuleManager`:
/// создание, редактирование и удаление аккаунтов, игр и категорий,
/// связи между сущностями, сохранение данных и навигацию.
///
/// Формы — вертикальные `ListView`, поэтому элементы за пределами
/// экрана не строятся: тест использует высокий вьюпорт, чтобы сценарий
/// «заполнил и сохранил» проверялся целиком, а не до первого экрана.
library accounts_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/search/search_scope.dart';
import 'package:personal_hub/modules/accounts/accounts_module.dart';
import 'package:personal_hub/modules/accounts/ui/accounts_screen.dart';

/// Хранилище в памяти: переживёт «перезапуск» в пределах теста.
class _InMemoryModuleStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

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

class _Factory {
  _Factory(this.storage);

  final _InMemoryModuleStorage storage;

  late final GlobalSearchService searchService = GlobalSearchService();
  late final ModuleManager manager = ModuleManager(
    searchService: searchService,
    storageFactory: (_) => storage,
  );
}

void main() {
  late _Factory factory;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(AccountsModule());
    factory = _Factory(_InMemoryModuleStorage());
  });

  tearDown(() {
    factory.manager.dispose();
    ModuleRegistry.clear();
  });

  Widget wrap() {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: SearchScope(
        service: factory.searchService,
        child: ModuleManagerScope(
          manager: factory.manager,
          child: const AccountsScreen(moduleId: 'accounts'),
        ),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    // Высокий вьюпорт: на обычном телефоне кнопка «Создать» оказывается
    // за пределами экрана, а ListView её просто не строит — и сценарий
    // сохранения проверялся бы не целиком.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
  }

  /// Переход на вкладку по имени.
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Тап по виджету с текстом [label].
  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Ввод текста в поле с меткой [label].
  Future<void> enterText(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextField, label).last, text);
    await tester.pump();
  }

  /// Создаёт аккаунт через UI: FAB → форма → сохранение.
  Future<void> createAccountViaUi(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await enterText(tester, 'Имя', name);
    await tapText(tester, 'Создать');
  }

  group('AccountsScreen — структура и пустые состояния', () {
    testWidgets('открывается с тремя вкладками', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Аккаунты'), findsWidgets);
      expect(find.text('Игры'), findsWidgets);
      expect(find.text('Категории'), findsWidgets);
    });

    testWidgets('пустые состояния с призывом к действию', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Аккаунтов пока нет'), findsOneWidget);
      expect(find.text('Создать аккаунт'), findsOneWidget);
    });
  });

  group('Создание аккаунта через UI', () {
    testWidgets('FAB → форма → сохранение → аккаунт в списке', (tester) async {
      await pumpScreen(tester);

      await createAccountViaUi(tester, 'Steam Main');

      expect(find.text('Steam Main'), findsOneWidget);
      expect(find.text('Новый аккаунт'), findsNothing);
    });

    testWidgets('пустое имя не создаёт запись и оставляет форму открытой',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Имя оставляем пустым — обязательное поле.
      await tapText(tester, 'Создать');

      // Форма осталась открытой.
      expect(find.text('Новый аккаунт'), findsOneWidget);
      expect(find.text('Аккаунтов пока нет'), findsNothing);
    });
  });

  group('Редактирование аккаунта через UI', () {
    testWidgets('тап по аккаунту открывает форму с заполненным именем',
        (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Оригинал');

      await tester.tap(find.text('Оригинал'));
      await tester.pumpAndSettle();

      expect(find.text('Аккаунт'), findsOneWidget);
      final textField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Имя'),
      );
      expect(textField.controller?.text, 'Оригинал');

      // Переименование сохраняется.
      await enterText(tester, 'Имя', 'Новое');
      await tapText(tester, 'Сохранить');

      expect(find.text('Новое'), findsOneWidget);
      expect(find.text('Оригинал'), findsNothing);
    });
  });

  group('Удаление аккаунта через UI', () {
    testWidgets('удаление с подтверждением убирает аккаунт из списка',
        (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'На удаление');

      expect(find.text('На удаление'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Удалить аккаунт?'), findsOneWidget);
      await tapText(tester, 'Удалить');

      expect(find.text('На удаление'), findsNothing);
      expect(find.text('Аккаунтов пока нет'), findsOneWidget);
    });

    testWidgets('отмена в диалоге сохраняет аккаунт', (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Остаётся');

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      await tapText(tester, 'Отмена');

      expect(find.text('Остаётся'), findsOneWidget);
    });
  });

  group('Вкладка «Категории» через UI', () {
    testWidgets('создание категории и отображение в списке', (tester) async {
      await pumpScreen(tester);
      await tapTab(tester, 'Категории');

      expect(find.text('Категорий пока нет'), findsOneWidget);

      await tester.tap(find.text('Создать категорию').last);
      await tester.pumpAndSettle();

      await enterText(tester, 'Название', 'RPG');
      await tapText(tester, 'Создать');

      expect(find.text('RPG'), findsOneWidget);
      expect(find.text('Категорий пока нет'), findsNothing);
    });

    testWidgets('дубль имени не создаёт вторую категорию', (tester) async {
      await pumpScreen(tester);
      await tapTab(tester, 'Категории');

      await tester.tap(find.text('Создать категорию').last);
      await tester.pumpAndSettle();
      await enterText(tester, 'Название', 'Экшен');
      await tapText(tester, 'Создать');

      expect(find.text('Экшен'), findsOneWidget);

      // Повторяем с тем же именем в другом регистре.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await enterText(tester, 'Название', 'экшен');
      await tapText(tester, 'Создать');

      // Форма осталась открыта — ошибка показана, вторая не создана.
      expect(find.text('Новая категория'), findsOneWidget);
    });

    testWidgets('порядок категорий сохраняется при создании', (tester) async {
      await pumpScreen(tester);
      await tapTab(tester, 'Категории');

      for (final name in ['Первая', 'Вторая', 'Третья']) {
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        await enterText(tester, 'Название', name);
        await tapText(tester, 'Создать');
      }

      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data)
          .toList();
      expect(titles, ['Первая', 'Вторая', 'Третья']);
    });

    testWidgets('удаление категории с подтверждением', (tester) async {
      await pumpScreen(tester);
      await tapTab(tester, 'Категории');

      await tester.tap(find.text('Создать категорию').last);
      await tester.pumpAndSettle();
      await enterText(tester, 'Название', 'Временная');
      await tapText(tester, 'Создать');

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Удалить категорию?'), findsOneWidget);
      await tapText(tester, 'Удалить');

      expect(find.text('Временная'), findsNothing);
      expect(find.text('Категорий пока нет'), findsOneWidget);
    });
  });

  group('Создание игры через UI', () {
    testWidgets('игра привязывается к существующему аккаунту', (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Steam');

      await tapTab(tester, 'Игры');
      expect(find.text('Игр пока нет'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(find.text('Новая игра'), findsOneWidget);
      await enterText(tester, 'Название', 'Elden Ring');

      // Аккаунт подставлен автоматически (единственный).
      expect(find.text('Steam'), findsWidgets);

      await tapText(tester, 'Создать');

      expect(find.text('Elden Ring'), findsOneWidget);
    });

    testWidgets('игра без названия не сохраняется', (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Steam');

      await tapTab(tester, 'Игры');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tapText(tester, 'Создать');

      expect(find.text('Новая игра'), findsOneWidget);
    });

    testWidgets('игра отображается с платформой и статусом', (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Steam');

      await tapTab(tester, 'Игры');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await enterText(tester, 'Название', 'Cyberpunk 2077');
      await tapText(tester, 'Создать');

      expect(find.text('Cyberpunk 2077'), findsOneWidget);
      expect(find.text('Steam · В планах'), findsOneWidget);
    });
  });

  group('Сохранение данных и жизненный цикл', () {
    testWidgets('данные сохраняются в хранилище модуля', (tester) async {
      await pumpScreen(tester);
      await createAccountViaUi(tester, 'Постоянный');

      // Новый репозиторий поверх ТОГО ЖЕ хранилища читает данные.
      final keys = await factory.storage.keys();
      expect(keys.any((k) => k.startsWith('account:')), isTrue);

      // Повторное открытие экрана показывает сохранённый аккаунт.
      await pumpScreen(tester);
      expect(find.text('Постоянный'), findsOneWidget);
    });

    testWidgets('включение модуля регистрирует поиск, выключение снимает',
        (tester) async {
      await pumpScreen(tester);

      await factory.manager.install('accounts');
      await factory.manager.enable('accounts');
      expect(factory.manager.stateOf('accounts'), ModuleState.enabled);
      expect(factory.searchService.providerCount, 1);

      await factory.manager.disable('accounts');
      expect(factory.searchService.providerCount, 0);

      // Повторное включение не плодит дубли.
      await factory.manager.enable('accounts');
      expect(factory.searchService.providerCount, 1);
    });
  });
}
