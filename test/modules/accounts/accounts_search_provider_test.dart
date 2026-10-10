/// Тесты AccountsSearchProvider.
library accounts_search_provider_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/account_repository.dart';
import 'package:personal_hub/modules/accounts/accounts_search_provider.dart';
import 'package:personal_hub/modules/accounts/category_repository.dart';
import 'package:personal_hub/modules/accounts/game_repository.dart';
import 'package:personal_hub/modules/accounts/models/account.dart';
import 'package:personal_hub/modules/accounts/models/game_profile.dart';
import 'test_storage.dart';

void main() {
  group('AccountsSearchProvider search', () {
    late InMemoryModuleStorage storage;
    late AccountRepository accountRepo;
    late CategoryRepository categoryRepo;
    late GameRepository gameRepo;
    late AccountsSearchProvider provider;

    setUp(() {
      storage = InMemoryModuleStorage();
      accountRepo = AccountRepository(storage);
      categoryRepo = CategoryRepository(storage);
      gameRepo = GameRepository(storage, accountRepo, categoryRepo);
      provider = AccountsSearchProvider(accountRepo, gameRepo, categoryRepo);
    });

    Future<void> setupData() async {
      // Создаём аккаунт
      final account = await accountRepo.create(
        name: 'My Steam Account',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF123456,
        note: 'Main gaming account',
      );

      // Создаём категории
      final cat1 = await categoryRepo.create(
        name: 'Action',
        iconKey: 'action',
        colorValue: 0xFFCC3333,
      );
      final cat2 = await categoryRepo.create(
        name: 'RPG',
        iconKey: 'rpg',
        colorValue: 0xFF33CC33,
      );

      // Создаём игры
      await gameRepo.create(
        accountId: account.id,
        title: 'Elden Ring',
        platform: GamePlatform.steam,
        region: 'RU',
        status: GameStatus.playing,
        playtimeMinutes: 120,
        categoryIds: [cat1.id, cat2.id],
        note: 'Great open world',
      );
      await gameRepo.create(
        accountId: account.id,
        title: 'Cyberpunk 2077',
        platform: GamePlatform.gog,
        region: 'US',
        status: GameStatus.completed,
        playtimeMinutes: 80,
        categoryIds: [cat1.id],
        note: 'Story rich',
      );
    }

    test('пустой запрос возвращает пустой список', () async {
      // Используем пустое хранилище без setupData
      final results = await provider.search('');
      expect(results, isEmpty);
    });

    test('пустой запрос возвращает пустой список даже с данными', () async {
      await setupData();
      final results = await provider.search('');
      expect(results, isEmpty);
    });

    test('поиск по имени аккаунта', () async {
      await setupData();
      final results = await provider.search('steam');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.title == 'My Steam Account'), isTrue);
      expect(results.any((r) => r.subtitle?.contains('Аккаунт') == true), isTrue);
    });

    test('поиск по типу аккаунта (label)', () async {
      await setupData();
      final results = await provider.search('steam');
      expect(results.any((r) => r.title == 'My Steam Account'), isTrue);
    });

    test('поиск по заметке аккаунта', () async {
      await setupData();
      final results = await provider.search('gaming');
      expect(results.any((r) => r.title == 'My Steam Account'), isTrue);
    });

    test('поиск по названию игры', () async {
      await setupData();
      final results = await provider.search('elden');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.title == 'Elden Ring'), isTrue);
      expect(results.any((r) => r.subtitle?.contains('Игра') == true), isTrue);
    });

    test('поиск по платформе игры', () async {
      await setupData();
      final results = await provider.search('gog');
      expect(results.any((r) => r.title == 'Cyberpunk 2077'), isTrue);
    });

    test('поиск по статусу игры', () async {
      await setupData();
      final results = await provider.search('пройден');
      expect(results.any((r) => r.title == 'Cyberpunk 2077'), isTrue);
    });

    test('поиск по заметке игры', () async {
      await setupData();
      final results = await provider.search('story');
      expect(results.any((r) => r.title == 'Cyberpunk 2077'), isTrue);
    });

    test('поиск по категории', () async {
      await setupData();
      final results = await provider.search('action');
      // Должно найти и аккаунт (нет), и игры с категорией Action
      expect(results.any((r) => r.title == 'Elden Ring'), isTrue);
      expect(results.any((r) => r.title == 'Cyberpunk 2077'), isTrue);
    });

    test('поиск по имени категории', () async {
      await setupData();
      final results = await provider.search('rpg');
      expect(results.any((r) => r.title == 'RPG'), isTrue);
      expect(results.any((r) => r.subtitle == 'Категория'), isTrue);
    });

    test('отсутствие совпадений возвращает пустой список', () async {
      await setupData();
      final results = await provider.search('nonexistent');
      expect(results, isEmpty);
    });

    test('регистр не важен', () async {
      await setupData();
      final results1 = await provider.search('ELDEN');
      final results2 = await provider.search('elden');
      final results3 = await provider.search('EldEn');
      expect(results1.length, results2.length);
      expect(results2.length, results3.length);
    });

    test('иконки результатов соответствуют типам', () async {
      await setupData();
      final accountResults = await provider.search('my steam');
      expect(accountResults.first.icon, Icons.account_circle_outlined);

      final gameResults = await provider.search('elden');
      expect(gameResults.first.icon, Icons.videogame_asset_outlined);

      final categoryResults = await provider.search('rpg');
      // Категория ищется после игр, но 'rpg' может найти и игру.
      // Проверяем, что в результатах есть хотя бы один с иконкой категории.
      expect(categoryResults.any((r) => r.icon == Icons.category_outlined), isTrue);
    });
  });
}