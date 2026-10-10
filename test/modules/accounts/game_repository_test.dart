/// Тесты GameRepository.
library game_repository_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/account_repository.dart';
import 'package:personal_hub/modules/accounts/category_repository.dart';
import 'package:personal_hub/modules/accounts/game_repository.dart';
import 'package:personal_hub/modules/accounts/models/account.dart';
import 'package:personal_hub/modules/accounts/models/category.dart';
import 'package:personal_hub/modules/accounts/models/game_profile.dart';
import 'test_storage.dart';

void main() {
  late InMemoryModuleStorage storage;
  late AccountRepository accountRepo;
  late CategoryRepository categoryRepo;
  late GameRepository gameRepo;

  setUp(() {
    storage = InMemoryModuleStorage();
    accountRepo = AccountRepository(storage);
    categoryRepo = CategoryRepository(storage);
    gameRepo = GameRepository(storage, accountRepo, categoryRepo);
  });

  Future<Account> createAccount({String name = 'Test Account'}) async {
    return accountRepo.create(
      name: name,
      type: AccountType.steam,
      iconKey: 'steam',
      colorValue: 0xFF123456,
      note: '',
    );
  }

  Future<Category> createCategory({String name = 'Test Category'}) async {
    return categoryRepo.create(
      name: name,
      iconKey: 'folder',
      colorValue: 0xFFAABBCC,
    );
  }

  group('GameRepository CRUD', () {
    test('create → getById → getAll работает', () async {
      final account = await createAccount();
      final cat = await createCategory();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'Test Game',
        platform: GamePlatform.steam,
        region: 'RU',
        status: GameStatus.playing,
        playtimeMinutes: 120,
        categoryIds: [cat.id],
        note: 'Great game',
      );

      expect(game.id, isNotEmpty);
      expect(game.accountId, account.id);
      expect(game.title, 'Test Game');
      expect(game.platform, GamePlatform.steam);
      expect(game.region, 'RU');
      expect(game.status, GameStatus.playing);
      expect(game.playtimeMinutes, 120);
      expect(game.categoryIds, [cat.id]);
      expect(game.note, 'Great game');

      final byId = await gameRepo.getById(game.id);
      expect(byId, isNotNull);
      expect(byId!.id, game.id);

      final all = await gameRepo.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, game.id);
    });

    test('create проверяет существование аккаунта', () async {
      await createCategory();

      await expectLater(
        gameRepo.create(
          accountId: 'non-existent-account',
          title: 'Test Game',
          platform: GamePlatform.steam,
          status: GameStatus.backlog,
          playtimeMinutes: 0,
          categoryIds: [],
          note: '',
        ),
        throwsA(isA<GameRepositoryException>()),
      );
    });

    test('create проверяет существование категорий', () async {
      final account = await createAccount();

      await expectLater(
        gameRepo.create(
          accountId: account.id,
          title: 'Test Game',
          platform: GamePlatform.steam,
          status: GameStatus.backlog,
          playtimeMinutes: 0,
          categoryIds: ['non-existent-cat'],
          note: '',
        ),
        throwsA(isA<GameRepositoryException>()),
      );
    });

    test('create игнорирует null region', () async {
      final account = await createAccount();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'Test Game',
        platform: GamePlatform.steam,
        region: null,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      expect(game.region, null);
    });

    test('create с пустым categoryIds работает', () async {
      final account = await createAccount();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'No Category Game',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      expect(game.categoryIds, []);
    });

    test('update обновляет поля и проверяет ссылки', () async {
      final account1 = await createAccount(name: 'Account 1');
      final account2 = await createAccount(name: 'Account 2');
      final cat1 = await createCategory(name: 'Category 1');
      final cat2 = await createCategory(name: 'Category 2');

      final game = await gameRepo.create(
        accountId: account1.id,
        title: 'Original Game',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat1.id],
        note: 'Old note',
      );

      final updated = await gameRepo.update(
        id: game.id,
        accountId: account2.id,
        title: 'Updated Game',
        platform: GamePlatform.epicGames,
        region: 'US',
        status: GameStatus.playing,
        playtimeMinutes: 60,
        categoryIds: [cat2.id],
        note: 'New note',
      );

      expect(updated.id, game.id);
      expect(updated.accountId, account2.id);
      expect(updated.title, 'Updated Game');
      expect(updated.platform, GamePlatform.epicGames);
      expect(updated.region, 'US');
      expect(updated.status, GameStatus.playing);
      expect(updated.playtimeMinutes, 60);
      expect(updated.categoryIds, [cat2.id]);
      expect(updated.note, 'New note');
      expect(updated.createdAt, game.createdAt);
      expect(updated.updatedAt.isAfter(game.updatedAt), isTrue);
    });

    test('update проверяет новый accountId', () async {
      final account = await createAccount();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'Test',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      await expectLater(
        gameRepo.update(
          id: game.id,
          accountId: 'non-existent',
        ),
        throwsA(isA<GameRepositoryException>()),
      );
    });

    test('update проверяет новые categoryIds', () async {
      final account = await createAccount();
      final cat = await createCategory();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'Test',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat.id],
        note: '',
      );

      await expectLater(
        gameRepo.update(
          id: game.id,
          categoryIds: ['non-existent'],
        ),
        throwsA(isA<GameRepositoryException>()),
      );
    });

    test('update с region=null снимает регион', () async {
      final account = await createAccount();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'Test',
        platform: GamePlatform.steam,
        region: 'EU',
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      final updated = await gameRepo.update(id: game.id, region: null);
      expect(updated.region, null);
    });

    test('delete удаляет игру', () async {
      final account = await createAccount();

      final game = await gameRepo.create(
        accountId: account.id,
        title: 'To Delete',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      await gameRepo.delete(game.id);

      final byId = await gameRepo.getById(game.id);
      expect(byId, null);

      final all = await gameRepo.getAll();
      expect(all, isEmpty);
    });

    test('delete выбрасывает на несуществующем id', () async {
      await expectLater(
        gameRepo.delete('non-existent'),
        throwsA(isA<GameRepositoryException>()),
      );
    });

    test('getByAccount возвращает игры конкретного аккаунта', () async {
      final account1 = await createAccount(name: 'Account 1');
      final account2 = await createAccount(name: 'Account 2');

      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 1',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 2',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      await gameRepo.create(
        accountId: account2.id,
        title: 'Game 3',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      final games1 = await gameRepo.getByAccount(account1.id);
      expect(games1.length, 2);
      expect(games1.every((g) => g.accountId == account1.id), isTrue);

      final games2 = await gameRepo.getByAccount(account2.id);
      expect(games2.length, 1);
      expect(games2.first.accountId, account2.id);
    });

    test('getByCategory возвращает игры с категорией', () async {
      final account = await createAccount();
      final cat1 = await createCategory(name: 'Cat 1');
      final cat2 = await createCategory(name: 'Cat 2');

      await gameRepo.create(
        accountId: account.id,
        title: 'Game 1',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat1.id],
        note: '',
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Game 2',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat1.id, cat2.id],
        note: '',
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Game 3',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat2.id],
        note: '',
      );

      final games1 = await gameRepo.getByCategory(cat1.id);
      expect(games1.length, 2);

      final games2 = await gameRepo.getByCategory(cat2.id);
      expect(games2.length, 2);
    });

    test('deleteByAccount удаляет все игры аккаунта', () async {
      final account1 = await createAccount(name: 'Account 1');
      final account2 = await createAccount(name: 'Account 2');

      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 1',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 2',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      await gameRepo.create(
        accountId: account2.id,
        title: 'Game 3',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      await gameRepo.deleteByAccount(account1.id);

      final games1 = await gameRepo.getByAccount(account1.id);
      expect(games1, isEmpty);

      final games2 = await gameRepo.getByAccount(account2.id);
      expect(games2.length, 1);
    });

    test('detachCategory удаляет ссылку на категорию из всех игр', () async {
      final account = await createAccount();
      final cat1 = await createCategory(name: 'Cat 1');
      final cat2 = await createCategory(name: 'Cat 2');

      await gameRepo.create(
        accountId: account.id,
        title: 'Game 1',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat1.id, cat2.id],
        note: '',
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Game 2',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat1.id],
        note: '',
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Game 3',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat2.id],
        note: '',
      );

      await gameRepo.detachCategory(cat1.id);

      final games = await gameRepo.getAll();
      for (final game in games) {
        expect(game.categoryIds.contains(cat1.id), isFalse);
      }

      // cat2 должна остаться
      final game1 = await gameRepo.getById(games.firstWhere((g) => g.title == 'Game 1').id);
      expect(game1!.categoryIds, [cat2.id]);
    });

    test('count возвращает общее количество или по аккаунту', () async {
      final account1 = await createAccount(name: 'Account 1');
      final account2 = await createAccount(name: 'Account 2');

      expect(await gameRepo.count(), 0);
      expect(await gameRepo.count(accountId: account1.id), 0);

      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 1',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      expect(await gameRepo.count(), 1);
      expect(await gameRepo.count(accountId: account1.id), 1);
      expect(await gameRepo.count(accountId: account2.id), 0);

      await gameRepo.create(
        accountId: account1.id,
        title: 'Game 2',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      expect(await gameRepo.count(), 2);
      expect(await gameRepo.count(accountId: account1.id), 2);
    });

    test('getAll возвращает в порядке createdAt', () async {
      final account = await createAccount();

      final g1 = await gameRepo.create(
        accountId: account.id,
        title: 'First',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      final g2 = await gameRepo.create(
        accountId: account.id,
        title: 'Second',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [],
        note: '',
      );

      final all = await gameRepo.getAll();
      expect(all.length, 2);
      expect(all[0].id, g1.id);
      expect(all[1].id, g2.id);
    });
  });

  group('GameRepository изоляция', () {
    test('данные изолированы между storage', () async {
      final storage1 = InMemoryModuleStorage();
      final storage2 = InMemoryModuleStorage();
      final accountRepo1 = AccountRepository(storage1);
      final categoryRepo1 = CategoryRepository(storage1);
      final gameRepo1 = GameRepository(storage1, accountRepo1, categoryRepo1);
      final accountRepo2 = AccountRepository(storage2);
      final categoryRepo2 = CategoryRepository(storage2);
      final gameRepo2 = GameRepository(storage2, accountRepo2, categoryRepo2);

      final account = await accountRepo1.create(
        name: 'Test',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      final cat = await categoryRepo1.create(
        name: 'Cat',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );
      await gameRepo1.create(
        accountId: account.id,
        title: 'Game',
        platform: GamePlatform.steam,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        categoryIds: [cat.id],
        note: '',
      );

      expect(await gameRepo1.count(), 1);
      expect(await gameRepo2.count(), 0);
    });
  });
}