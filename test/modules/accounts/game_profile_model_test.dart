/// Тесты сериализации/десериализации GameProfile.
library game_profile_model_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/models/game_profile.dart';

void main() {
  group('GameProfile JSON serialization', () {
    test('toJson → fromJson сохраняет все поля', () {
      final now = DateTime.now().toUtc();
      final game = GameProfile(
        id: 'game-123',
        accountId: 'account-456',
        title: 'Test Game',
        platform: GamePlatform.steam,
        region: 'RU',
        status: GameStatus.playing,
        playtimeMinutes: 120,
        startedAt: now.subtract(const Duration(days: 10)),
        completedAt: now,
        coverAssetKey: 'cover.png',
        categoryIds: ['cat-1', 'cat-2'],
        note: 'Great game',
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now,
      );

      final json = game.toJson();
      final restored = GameProfile.fromJson(json);

      expect(restored.id, 'game-123');
      expect(restored.accountId, 'account-456');
      expect(restored.title, 'Test Game');
      expect(restored.platform, GamePlatform.steam);
      expect(restored.region, 'RU');
      expect(restored.status, GameStatus.playing);
      expect(restored.playtimeMinutes, 120);
      expect(restored.startedAt?.toIso8601String(), now.subtract(const Duration(days: 10)).toIso8601String());
      expect(restored.completedAt?.toIso8601String(), now.toIso8601String());
      expect(restored.coverAssetKey, 'cover.png');
      expect(restored.categoryIds, ['cat-1', 'cat-2']);
      expect(restored.note, 'Great game');
      expect(restored.createdAt.toIso8601String(), now.subtract(const Duration(days: 20)).toIso8601String());
      expect(restored.updatedAt.toIso8601String(), now.toIso8601String());
    });

    test('toJson не пишет null-поля (region, startedAt, completedAt, coverAssetKey)', () {
      final game = GameProfile(
        id: '1',
        accountId: 'acc-1',
        title: 'Test',
        platform: GamePlatform.pc,
        region: null,
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        startedAt: null,
        completedAt: null,
        coverAssetKey: null,
        categoryIds: [],
        note: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = game.toJson();
      expect(json.containsKey('region'), isFalse);
      expect(json.containsKey('startedAt'), isFalse);
      expect(json.containsKey('completedAt'), isFalse);
      expect(json.containsKey('coverAssetKey'), isFalse);
    });

    test('fromJson использует fallbackId при отсутствии id', () {
      final json = <String, dynamic>{'title': 'Test', 'accountId': 'acc-1'};
      final game = GameProfile.fromJson(json, fallbackId: 'fallback-123');
      expect(game.id, 'fallback-123');
    });

    test('fromJson выбрасывает FormatException при пустом id', () {
      final json = <String, dynamic>{'title': 'Test'};
      expect(() => GameProfile.fromJson(json), throwsFormatException);
    });

    test('fromJson нормализует title', () {
      final json = <String, dynamic>{'id': '1', 'title': '  Spaced Title  '};
      final game = GameProfile.fromJson(json);
      expect(game.title, 'Spaced Title');
    });

    test('fromJson подставляет title=id при пустом title', () {
      final json = <String, dynamic>{'id': 'xyz-789', 'title': ''};
      final game = GameProfile.fromJson(json);
      expect(game.title, 'xyz-789');
    });

    test('fromJson парсит platform из строки', () {
      final json = <String, dynamic>{'id': '1', 'platform': 'epicGames'};
      final game = GameProfile.fromJson(json);
      expect(game.platform, GamePlatform.epicGames);
    });

    test('fromJson подставляет other для неизвестного platform', () {
      final json = <String, dynamic>{'id': '1', 'platform': 'unknown'};
      final game = GameProfile.fromJson(json);
      expect(game.platform, GamePlatform.other);
    });

    test('fromJson парсит status из строки', () {
      final json = <String, dynamic>{'id': '1', 'status': 'completed'};
      final game = GameProfile.fromJson(json);
      expect(game.status, GameStatus.completed);
    });

    test('fromJson подставляет backlog для неизвестного status', () {
      final json = <String, dynamic>{'id': '1', 'status': 'unknown'};
      final game = GameProfile.fromJson(json);
      expect(game.status, GameStatus.backlog);
    });

    test('fromJson нормализует region (обрезает пробелы, null если пусто)', () {
      var json = <String, dynamic>{'id': '1', 'region': '  US  '};
      var game = GameProfile.fromJson(json);
      expect(game.region, 'US');

      json = <String, dynamic>{'id': '1', 'region': ''};
      game = GameProfile.fromJson(json);
      expect(game.region, null);

      json = <String, dynamic>{'id': '1'};
      game = GameProfile.fromJson(json);
      expect(game.region, null);
    });

    test('fromJson парсит playtimeMinutes', () {
      final json = <String, dynamic>{'id': '1', 'playtimeMinutes': 450};
      final game = GameProfile.fromJson(json);
      expect(game.playtimeMinutes, 450);
    });

    test('fromJson подставляет 0 при отсутствии playtimeMinutes', () {
      final json = <String, dynamic>{'id': '1'};
      final game = GameProfile.fromJson(json);
      expect(game.playtimeMinutes, GameProfile.defaultPlaytimeMinutes);
    });

    test('fromJson парсит даты ISO 8601', () {
      final now = DateTime.now().toUtc();
      final json = <String, dynamic>{
        'id': '1',
        'startedAt': now.toIso8601String(),
        'completedAt': now.add(const Duration(days: 5)).toIso8601String(),
      };
      final game = GameProfile.fromJson(json);
      expect(game.startedAt?.toIso8601String(), now.toIso8601String());
      expect(game.completedAt?.toIso8601String(), now.add(const Duration(days: 5)).toIso8601String());
    });

    test('fromJson игнорирует некорректные даты (ставит null)', () {
      final json = <String, dynamic>{
        'id': '1',
        'startedAt': 'invalid',
        'completedAt': 'also-invalid',
      };
      final game = GameProfile.fromJson(json);
      expect(game.startedAt, null);
      expect(game.completedAt, null);
    });

    test('fromJson парсит categoryIds как List<String>', () {
      final json = <String, dynamic>{
        'id': '1',
        'categoryIds': ['cat-1', 'cat-2', 'cat-3'],
      };
      final game = GameProfile.fromJson(json);
      expect(game.categoryIds, ['cat-1', 'cat-2', 'cat-3']);
    });

    test('fromJson игнорирует не-строки в categoryIds', () {
      final json = <String, dynamic>{
        'id': '1',
        'categoryIds': ['cat-1', 123, null, 'cat-2'],
      };
      final game = GameProfile.fromJson(json);
      expect(game.categoryIds, ['cat-1', 'cat-2']);
    });

    test('fromJson подставляет пустой список при отсутствии categoryIds', () {
      final json = <String, dynamic>{'id': '1'};
      final game = GameProfile.fromJson(json);
      expect(game.categoryIds, []);
    });

    test('copyWith обновляет только указанные поля', () {
      final original = GameProfile(
        id: '1',
        accountId: 'acc-1',
        title: 'Original',
        platform: GamePlatform.pc,
        region: 'US',
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        startedAt: null,
        completedAt: null,
        coverAssetKey: null,
        categoryIds: ['cat-1'],
        note: 'Old',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(
        title: 'Updated',
        status: GameStatus.playing,
        playtimeMinutes: 60,
        categoryIds: ['cat-1', 'cat-2'],
      );

      expect(updated.id, '1');
      expect(updated.accountId, 'acc-1');
      expect(updated.title, 'Updated');
      expect(updated.platform, GamePlatform.pc);
      expect(updated.region, 'US');
      expect(updated.status, GameStatus.playing);
      expect(updated.playtimeMinutes, 60);
      expect(updated.categoryIds, ['cat-1', 'cat-2']);
      expect(updated.note, 'Old');
      expect(updated.createdAt, DateTime(2024, 1, 1));
      expect(updated.updatedAt, original.updatedAt); // updatedAt не меняется по умолчанию
    });

    test('copyWith с region=null снимает регион', () {
      final original = GameProfile(
        id: '1',
        accountId: 'acc-1',
        title: 'Test',
        platform: GamePlatform.pc,
        region: 'EU',
        status: GameStatus.backlog,
        playtimeMinutes: 0,
        startedAt: null,
        completedAt: null,
        coverAssetKey: null,
        categoryIds: [],
        note: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = original.copyWith(region: null);
      expect(updated.region, null);
      expect(updated.updatedAt, original.updatedAt); // updatedAt не меняется
    });

    test('storageKey и idFromStorageKey — обратные операции', () {
      expect(GameProfile.storageKey('abc'), 'game:abc');
      expect(GameProfile.idFromStorageKey('game:abc'), 'abc');
      expect(GameProfile.idFromStorageKey('game:'), null);
      expect(GameProfile.idFromStorageKey('other:abc'), null);
    });

    test('normalizeTitle выбрасывает на пустой строке', () {
      expect(() => GameProfile.normalizeTitle(''), throwsFormatException);
      expect(() => GameProfile.normalizeTitle('   '), throwsFormatException);
    });
  });
}