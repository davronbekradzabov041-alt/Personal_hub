/// Тесты CategoryRepository.
library category_repository_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/category_repository.dart';
import 'test_storage.dart';

void main() {
  late InMemoryModuleStorage storage;
  late CategoryRepository repository;

  setUp(() {
    storage = InMemoryModuleStorage();
    repository = CategoryRepository(storage);
  });

  group('CategoryRepository CRUD', () {
    test('create → getById → getAll работает', () async {
      final category = await repository.create(
        name: 'Test Category',
        iconKey: 'folder',
        colorValue: 0xFFAABBCC,
      );

      expect(category.id, isNotEmpty);
      expect(category.name, 'Test Category');
      expect(category.iconKey, 'folder');
      expect(category.colorValue, 0xFFAABBCC);
      expect(category.order, 0);

      final byId = await repository.getById(category.id);
      expect(byId, isNotNull);
      expect(byId!.id, category.id);

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, category.id);
    });

    test('create назначает order в конце списка', () async {
      final c1 = await repository.create(
        name: 'First',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );
      final c2 = await repository.create(
        name: 'Second',
        iconKey: 'b',
        colorValue: 0xFF222222,
      );
      final c3 = await repository.create(
        name: 'Third',
        iconKey: 'c',
        colorValue: 0xFF333333,
      );

      expect(c1.order, 0);
      expect(c2.order, 1);
      expect(c3.order, 2);

      final all = await repository.getAll();
      expect(all[0].id, c1.id);
      expect(all[1].id, c2.id);
      expect(all[2].id, c3.id);
    });

    test('create выбрасывает на пустом имени', () async {
      await expectLater(
        repository.create(
          name: '',
          iconKey: 'folder',
          colorValue: 0xFF111111,
        ),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('create выбрасывает на пустом iconKey', () async {
      await expectLater(
        repository.create(
          name: 'Test',
          iconKey: '',
          colorValue: 0xFF111111,
        ),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('create выбрасывает на дубле имени (без учёта регистра)', () async {
      await repository.create(
        name: 'My Category',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );

      await expectLater(
        repository.create(
          name: 'my category',
          iconKey: 'b',
          colorValue: 0xFF222222,
        ),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('create генерирует уникальные id', () async {
      final c1 = await repository.create(
        name: 'Cat 1',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );
      final c2 = await repository.create(
        name: 'Cat 2',
        iconKey: 'b',
        colorValue: 0xFF222222,
      );
      expect(c1.id, isNot(equals(c2.id)));
    });

    test('update обновляет поля, order не меняется', () async {
      final category = await repository.create(
        name: 'Original',
        iconKey: 'star',
        colorValue: 0xFF111111,
      );

      final updated = await repository.update(
        id: category.id,
        name: 'Updated',
        iconKey: 'folder',
        colorValue: 0xFF222222,
      );

      expect(updated.id, category.id);
      expect(updated.name, 'Updated');
      expect(updated.iconKey, 'folder');
      expect(updated.colorValue, 0xFF222222);
      expect(updated.order, category.order); // order сохраняется
    });

    test('update выбрасывает на несуществующем id', () async {
      await expectLater(
        repository.update(
          id: 'non-existent',
          name: 'Test',
          iconKey: 'folder',
          colorValue: 0xFF111111,
        ),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('update выбрасывает на дубле имени', () async {
      await repository.create(
        name: 'Category 1',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );
      final c2 = await repository.create(
        name: 'Category 2',
        iconKey: 'b',
        colorValue: 0xFF222222,
      );

      await expectLater(
        repository.update(
          id: c2.id,
          name: 'Category 1',
          iconKey: 'b',
          colorValue: 0xFF222222,
        ),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('update не считает дублем своё текущее имя', () async {
      final category = await repository.create(
        name: 'Unique Name',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );

      final updated = await repository.update(
        id: category.id,
        name: 'Unique Name',
        iconKey: 'b',
        colorValue: 0xFF222222,
      );

      expect(updated.name, 'Unique Name');
      expect(updated.iconKey, 'b');
    });

    test('delete удаляет категорию и перенумеровывает остальные', () async {
      final c1 = await repository.create(name: 'First', iconKey: 'a', colorValue: 0xFF111111);
      final c2 = await repository.create(name: 'Second', iconKey: 'b', colorValue: 0xFF222222);
      final c3 = await repository.create(name: 'Third', iconKey: 'c', colorValue: 0xFF333333);

      await repository.delete(c2.id);

      final remaining = await repository.getAll();
      expect(remaining.length, 2);
      expect(remaining[0].id, c1.id);
      expect(remaining[0].order, 0);
      expect(remaining[1].id, c3.id);
      expect(remaining[1].order, 1); // перенумеровано
    });

    test('delete выбрасывает на несуществующем id', () async {
      await expectLater(
        repository.delete('non-existent'),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('findByName находит без учёта регистра и пробелов', () async {
      await repository.create(
        name: 'My Category',
        iconKey: 'a',
        colorValue: 0xFF111111,
      );

      var found = await repository.findByName('my category');
      expect(found, isNotNull);
      expect(found!.name, 'My Category');

      found = await repository.findByName('  MY CATEGORY  ');
      expect(found, isNotNull);

      found = await repository.findByName('Other');
      expect(found, null);
    });

    test('reorder переставляет категории', () async {
      final c1 = await repository.create(name: 'First', iconKey: 'a', colorValue: 0xFF111111);
      final c2 = await repository.create(name: 'Second', iconKey: 'b', colorValue: 0xFF222222);
      final c3 = await repository.create(name: 'Third', iconKey: 'c', colorValue: 0xFF333333);

      await repository.reorder([c3.id, c1.id, c2.id]);

      final reordered = await repository.getAll();
      expect(reordered[0].id, c3.id);
      expect(reordered[0].order, 0);
      expect(reordered[1].id, c1.id);
      expect(reordered[1].order, 1);
      expect(reordered[2].id, c2.id);
      expect(reordered[2].order, 2);
    });

    test('reorder выбрасывает на несовпадении количества', () async {
      await repository.create(name: 'A', iconKey: 'a', colorValue: 0xFF111111);
      await repository.create(name: 'B', iconKey: 'b', colorValue: 0xFF222222);

      await expectLater(
        repository.reorder(['some-id']),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('reorder выбрасывает на неизвестном id', () async {
      await repository.create(name: 'A', iconKey: 'a', colorValue: 0xFF111111);

      await expectLater(
        repository.reorder(['unknown-id']),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('reorder выбрасывает на дубле id', () async {
      final c1 = await repository.create(name: 'A', iconKey: 'a', colorValue: 0xFF111111);

      await expectLater(
        repository.reorder([c1.id, c1.id]),
        throwsA(isA<CategoryRepositoryException>()),
      );
    });

    test('count возвращает количество категорий', () async {
      expect(await repository.count(), 0);
      await repository.create(name: 'A', iconKey: 'a', colorValue: 0xFF111111);
      expect(await repository.count(), 1);
      await repository.create(name: 'B', iconKey: 'b', colorValue: 0xFF222222);
      expect(await repository.count(), 2);
    });
  });

  group('CategoryRepository изоляция', () {
    test('данные изолированы между storage', () async {
      final storage1 = InMemoryModuleStorage();
      final storage2 = InMemoryModuleStorage();
      final repo1 = CategoryRepository(storage1);
      final repo2 = CategoryRepository(storage2);

      await repo1.create(name: 'Cat 1', iconKey: 'a', colorValue: 0xFF111111);

      expect(await repo1.count(), 1);
      expect(await repo2.count(), 0);
    });
  });
}