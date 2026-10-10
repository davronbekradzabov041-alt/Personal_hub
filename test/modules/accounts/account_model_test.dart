/// Тесты сериализации/десериализации Account.
library account_model_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/models/account.dart';

void main() {
  group('Account JSON serialization', () {
    test('toJson → fromJson сохраняет все поля', () {
      final now = DateTime.now().toUtc();
      final account = Account(
        id: 'test-123',
        name: 'Test Account',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF123456,
        note: 'Test note',
        createdAt: now,
        updatedAt: now,
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.id, 'test-123');
      expect(restored.name, 'Test Account');
      expect(restored.type, AccountType.steam);
      expect(restored.iconKey, 'steam');
      expect(restored.colorValue, 0xFF123456);
      expect(restored.note, 'Test note');
      expect(restored.createdAt.toIso8601String(), now.toIso8601String());
      expect(restored.updatedAt.toIso8601String(), now.toIso8601String());
    });

    test('fromJson использует fallbackId если id отсутствует в JSON', () {
      final json = <String, dynamic>{
        'name': 'Test',
        'type': 'email',
      };
      final account = Account.fromJson(json, fallbackId: 'fallback-123');
      expect(account.id, 'fallback-123');
    });

    test('fromJson выбрасывает FormatException при пустом id и отсутствии fallbackId', () {
      final json = <String, dynamic>{'name': 'Test'};
      expect(() => Account.fromJson(json), throwsFormatException);
    });

    test('fromJson нормализует имя (обрезает пробелы)', () {
      final json = <String, dynamic>{'id': '1', 'name': '  Spaced Name  '};
      final account = Account.fromJson(json);
      expect(account.name, 'Spaced Name');
    });

    test('fromJson подставляет имя=id при пустом имени', () {
      final json = <String, dynamic>{'id': 'abc-123', 'name': ''};
      final account = Account.fromJson(json);
      expect(account.name, 'abc-123');
    });

    test('fromJson парсит type из строки', () {
      final json = <String, dynamic>{'id': '1', 'type': 'battleNet'};
      final account = Account.fromJson(json);
      expect(account.type, AccountType.battleNet);
    });

    test('fromJson подставляет custom для неизвестного type', () {
      final json = <String, dynamic>{'id': '1', 'type': 'unknown'};
      final account = Account.fromJson(json);
      expect(account.type, AccountType.custom);
    });

    test('fromJson нормализует colorValue к ARGB с alpha=0xFF', () {
      final json = <String, dynamic>{'id': '1', 'colorValue': 0x123456};
      final account = Account.fromJson(json);
      expect(account.colorValue, 0xFF123456);
    });

    test('fromJson обрезает colorValue до 24 бит', () {
      final json = <String, dynamic>{'id': '1', 'colorValue': 0x11223344};
      final account = Account.fromJson(json);
      expect(account.colorValue, 0xFF223344);
    });

    test('fromJson подставляет defaultColorValue при отсутствии colorValue', () {
      final json = <String, dynamic>{'id': '1'};
      final account = Account.fromJson(json);
      expect(account.colorValue, Account.defaultColorValue);
    });

    test('fromJson подставляет defaultIconKey при пустом iconKey', () {
      final json = <String, dynamic>{'id': '1', 'iconKey': ''};
      final account = Account.fromJson(json);
      expect(account.iconKey, Account.defaultIconKey);
    });

    test('fromJson парсит даты ISO 8601', () {
      final now = DateTime.now().toUtc();
      final json = <String, dynamic>{
        'id': '1',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final account = Account.fromJson(json);
      expect(account.createdAt.toIso8601String(), now.toIso8601String());
      expect(account.updatedAt.toIso8601String(), now.toIso8601String());
    });

    test('fromJson подставляет DateTime.now() при некорректных датах', () {
      final before = DateTime.now();
      final json = <String, dynamic>{
        'id': '1',
        'createdAt': 'invalid',
        'updatedAt': 'invalid',
      };
      final account = Account.fromJson(json);
      final after = DateTime.now();
      expect(account.createdAt.isAfter(before) || account.createdAt.isAtSameMomentAs(before), isTrue);
      expect(account.createdAt.isBefore(after) || account.createdAt.isAtSameMomentAs(after), isTrue);
    });

    test('copyWith обновляет только указанные поля', () {
      final original = Account(
        id: '1',
        name: 'Original',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: 'Old note',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(
        name: 'Updated',
        type: AccountType.steam,
        note: 'New note',
      );

      expect(updated.id, '1');
      expect(updated.name, 'Updated');
      expect(updated.type, AccountType.steam);
      expect(updated.iconKey, 'email');
      expect(updated.colorValue, 0xFF111111);
      expect(updated.note, 'New note');
      expect(updated.createdAt, DateTime(2024, 1, 1));
      expect(updated.updatedAt, original.updatedAt); // updatedAt не меняется по умолчанию
    });

    test('storageKey и idFromStorageKey — обратные операции', () {
      expect(Account.storageKey('abc'), 'account:abc');
      expect(Account.idFromStorageKey('account:abc'), 'abc');
      expect(Account.idFromStorageKey('account:'), null);
      expect(Account.idFromStorageKey('other:abc'), null);
    });

    test('normalizeName выбрасывает на пустой строке', () {
      expect(() => Account.normalizeName(''), throwsFormatException);
      expect(() => Account.normalizeName('   '), throwsFormatException);
    });

    test('normalizeColor приводит к непрозрачному ARGB', () {
      expect(Account.normalizeColor(0x123456), 0xFF123456);
      expect(Account.normalizeColor(-1), 0xFFFFFFFF);
      expect(Account.normalizeColor(0x11223344), 0xFF223344);
    });
  });
}