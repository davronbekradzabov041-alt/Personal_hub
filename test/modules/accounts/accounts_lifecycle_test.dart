/// Интеграционные тесты lifecycle модуля Accounts.
library accounts_lifecycle_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/accounts/accounts_module.dart';
import 'package:personal_hub/modules/accounts/account_repository.dart';
import 'package:personal_hub/modules/accounts/category_repository.dart';
import 'package:personal_hub/modules/accounts/game_repository.dart';
import 'package:personal_hub/modules/accounts/models/account.dart';
import 'package:personal_hub/modules/accounts/models/game_profile.dart';
import 'test_storage.dart';

void main() {
  late ModuleManager manager;
  late GlobalSearchService searchService;
  late InMemoryModuleStorage storage;

  setUp(() {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
    storage = InMemoryModuleStorage();
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: (_) => storage,
    );
    ModuleRegistry.register(AccountsModule());
  });

  tearDown(() {
    manager.dispose();
    ModuleRegistry.clear();
  });

  group('AccountsModule lifecycle & search', () {
    test('install → enable регистрирует SearchProvider', () async {
      await manager.install('accounts');
      await manager.enable('accounts');

      expect(manager.stateOf('accounts'), ModuleState.enabled);
      expect(searchService.providerCount, 1);
    });

    test('disable отменяет регистрацию SearchProvider', () async {
      await manager.install('accounts');
      await manager.enable('accounts');
      expect(searchService.providerCount, 1);

      await manager.disable('accounts');

      expect(manager.stateOf('accounts'), ModuleState.disabled);
      expect(searchService.providerCount, 0);
    });

    test('повторное включение не создаёт дубликатов провайдера', () async {
      await manager.install('accounts');

      await manager.enable('accounts');
      expect(searchService.providerCount, 1);

      await manager.disable('accounts');
      expect(searchService.providerCount, 0);

      await manager.enable('accounts');
      expect(searchService.providerCount, 1);

      await manager.disable('accounts');
      await manager.enable('accounts');
      expect(searchService.providerCount, 1);
    });

    test('uninstall отменяет регистрацию (защитный дубль)', () async {
      await manager.install('accounts');
      await manager.enable('accounts');
      expect(searchService.providerCount, 1);

      await manager.disable('accounts');
      await manager.uninstall('accounts');

      expect(manager.stateOf('accounts'), ModuleState.uninstalled);
      expect(searchService.providerCount, 0);
    });

    test('поиск работает после enable и не работает после disable', () async {
      await manager.install('accounts');
      await manager.enable('accounts');

      // Создаём данные
      final accountRepo = AccountRepository(storage);
      final categoryRepo = CategoryRepository(storage);
      final gameRepo = GameRepository(storage, accountRepo, categoryRepo);

      final account = await accountRepo.create(
        name: 'Test Account',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF123456,
        note: '',
      );
      final cat = await categoryRepo.create(
        name: 'Action',
        iconKey: 'action',
        colorValue: 0xFFCC3333,
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Test Game',
        platform: GamePlatform.steam,
        status: GameStatus.playing,
        playtimeMinutes: 10,
        categoryIds: [cat.id],
        note: '',
      );

      // Поиск должен находить результаты
      var results = await searchService.search('test');
      expect(results, isNotEmpty);

      await manager.disable('accounts');

      // После disable поиск не должен находить результаты модуля
      results = await searchService.search('test');
      // Может быть пусто или только результаты других модулей (core test data)
      // Но провайдер Accounts удалён, поэтому результатов от него быть не должно
      final accountsResults = results.where((r) =>
        r.title == 'Test Account' || r.title == 'Test Game' || r.title == 'Action'
      ).toList();
      expect(accountsResults, isEmpty);
    });

    test('поиск через реальный ModuleManager интеграцию', () async {
      await manager.install('accounts');
      await manager.enable('accounts');

      final accountRepo = AccountRepository(storage);
      await accountRepo.create(
        name: 'Search Test Account',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF123456,
        note: 'Search note',
      );

      final results = await searchService.search('search test');
      expect(results.any((r) => r.title == 'Search Test Account'), isTrue);
      expect(results.any((r) => r.subtitle?.contains('Аккаунт') == true), isTrue);
    });
  });
}