/// Тесты AccountRepository.
library account_repository_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/account_repository.dart';
import 'package:personal_hub/modules/accounts/models/account.dart';
import 'test_storage.dart';

void main() {
  late InMemoryModuleStorage storage;
  late AccountRepository repository;

  setUp(() {
    storage = InMemoryModuleStorage();
    repository = AccountRepository(storage);
  });

  group('AccountRepository CRUD', () {
    test('create → getById → getAll работает', () async {
      final account = await repository.create(
        name: 'Test Account',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF123456,
        note: 'Test note',
      );

      expect(account.id, isNotEmpty);
      expect(account.name, 'Test Account');
      expect(account.type, AccountType.steam);
      expect(account.iconKey, 'steam');
      expect(account.colorValue, 0xFF123456);
      expect(account.note, 'Test note');
      expect(account.updatedAt.isAfter(account.createdAt) ||
          account.updatedAt.isAtSameMomentAs(account.createdAt), isTrue);

      final byId = await repository.getById(account.id);
      expect(byId, isNotNull);
      expect(byId!.id, account.id);
      expect(byId.name, 'Test Account');

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, account.id);
    });

    test('create генерирует уникальные id', () async {
      final a1 = await repository.create(
        name: 'Account 1',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      final a2 = await repository.create(
        name: 'Account 2',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: '',
      );
      expect(a1.id, isNot(equals(a2.id)));
    });

    test('create выбрасывает на пустом имени', () async {
      await expectLater(
        repository.create(
          name: '',
          type: AccountType.email,
          iconKey: 'email',
          colorValue: 0xFF111111,
          note: '',
        ),
        throwsA(isA<AccountRepositoryException>()),
      );
    });

    test('create выбрасывает на дубле имени (без учёта регистра)', () async {
      await repository.create(
        name: 'My Account',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );

      await expectLater(
        repository.create(
          name: 'my account',
          type: AccountType.steam,
          iconKey: 'steam',
          colorValue: 0xFF222222,
          note: '',
        ),
        throwsA(isA<AccountRepositoryException>()),
      );
    });

    test('update обновляет поля и updatedAt', () async {
      final account = await repository.create(
        name: 'Original',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: 'Old note',
      );

      final originalUpdatedAt = account.updatedAt;

      await Future.delayed(const Duration(milliseconds: 10));

      final updated = await repository.update(
        id: account.id,
        name: 'Updated',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: 'New note',
      );

      expect(updated.id, account.id);
      expect(updated.name, 'Updated');
      expect(updated.type, AccountType.steam);
      expect(updated.iconKey, 'steam');
      expect(updated.colorValue, 0xFF222222);
      expect(updated.note, 'New note');
      expect(updated.createdAt, account.createdAt); // createdAt не меняется
      expect(updated.updatedAt.isAfter(originalUpdatedAt), isTrue);

      final byId = await repository.getById(account.id);
      expect(byId!.name, 'Updated');
      expect(byId.type, AccountType.steam);
    });

    test('update выбрасывает на несуществующем id', () async {
      await expectLater(
        repository.update(
          id: 'non-existent',
          name: 'Test',
          type: AccountType.email,
          iconKey: 'email',
          colorValue: 0xFF111111,
          note: '',
        ),
        throwsA(isA<AccountRepositoryException>()),
      );
    });

    test('update выбрасывает на дубле имени', () async {
      final a1 = await repository.create(
        name: 'Account 1',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      await repository.create(
        name: 'Account 2',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: '',
      );

      await expectLater(
        repository.update(
          id: a1.id,
          name: 'Account 2',
          type: AccountType.email,
          iconKey: 'email',
          colorValue: 0xFF111111,
          note: '',
        ),
        throwsA(isA<AccountRepositoryException>()),
      );
    });

    test('update не считает дублем своё текущее имя', () async {
      final account = await repository.create(
        name: 'Unique Name',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );

      // Переименовываем в то же имя — должно пройти
      final updated = await repository.update(
        id: account.id,
        name: 'Unique Name',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: 'Updated note',
      );

      expect(updated.name, 'Unique Name');
      expect(updated.type, AccountType.steam);
    });

    test('delete удаляет аккаунт', () async {
      final account = await repository.create(
        name: 'To Delete',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );

      await repository.delete(account.id);

      final byId = await repository.getById(account.id);
      expect(byId, null);

      final all = await repository.getAll();
      expect(all, isEmpty);
    });

    test('delete выбрасывает на несуществующем id', () async {
      await expectLater(
        repository.delete('non-existent'),
        throwsA(isA<AccountRepositoryException>()),
      );
    });

    test('getAll возвращает в порядке createdAt', () async {
      final a1 = await repository.create(
        name: 'First',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      final a2 = await repository.create(
        name: 'Second',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: '',
      );

      final all = await repository.getAll();
      expect(all.length, 2);
      expect(all[0].id, a1.id);
      expect(all[1].id, a2.id);
    });

    test('count возвращает количество аккаунтов', () async {
      expect(await repository.count(), 0);
      await repository.create(
        name: 'A1',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      expect(await repository.count(), 1);
      await repository.create(
        name: 'A2',
        type: AccountType.steam,
        iconKey: 'steam',
        colorValue: 0xFF222222,
        note: '',
      );
      expect(await repository.count(), 2);
    });

    test('create нормализует имя (обрезает пробелы)', () async {
      final account = await repository.create(
        name: '  Spaced  ',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );
      expect(account.name, 'Spaced');
    });

    test('create нормализует iconKey', () async {
      final account = await repository.create(
        name: 'Test',
        type: AccountType.email,
        iconKey: '  email  ',
        colorValue: 0xFF111111,
        note: '',
      );
      expect(account.iconKey, 'email');
    });

    test('create нормализует colorValue', () async {
      final account = await repository.create(
        name: 'Test',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0x123456,
        note: '',
      );
      expect(account.colorValue, 0xFF123456);
    });
  });

  group('AccountRepository изоляция', () {
    test('данные одного репозитория не видны в другом экземпляре с другим storage', () async {
      final storage1 = InMemoryModuleStorage();
      final storage2 = InMemoryModuleStorage();
      final repo1 = AccountRepository(storage1);
      final repo2 = AccountRepository(storage2);

      await repo1.create(
        name: 'Account 1',
        type: AccountType.email,
        iconKey: 'email',
        colorValue: 0xFF111111,
        note: '',
      );

      expect(await repo1.count(), 1);
      expect(await repo2.count(), 0);
    });
  });
}