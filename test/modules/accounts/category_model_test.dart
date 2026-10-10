/// Тесты сериализации/десериализации Category.
library category_model_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/accounts/models/category.dart';

void main() {
  group('Category JSON serialization', () {
    test('toJson → fromJson сохраняет все поля', () {
      const category = Category(
        id: 'cat-123',
        name: 'Test Category',
        iconKey: 'folder',
        colorValue: 0xFFAABBCC,
        order: 5,
      );

      final json = category.toJson();
      final restored = Category.fromJson(json);

      expect(restored.id, 'cat-123');
      expect(restored.name, 'Test Category');
      expect(restored.iconKey, 'folder');
      expect(restored.colorValue, 0xFFAABBCC);
      expect(restored.order, 5);
    });

    test('fromJson использует fallbackId при отсутствии id', () {
      final json = <String, dynamic>{'name': 'Test'};
      final category = Category.fromJson(json, fallbackId: 'fallback-123');
      expect(category.id, 'fallback-123');
    });

    test('fromJson выбрасывает FormatException при пустом id', () {
      final json = <String, dynamic>{'name': 'Test'};
      expect(() => Category.fromJson(json), throwsFormatException);
    });

    test('fromJson нормализует имя', () {
      final json = <String, dynamic>{'id': '1', 'name': '  Spaced Name  '};
      final category = Category.fromJson(json);
      expect(category.name, 'Spaced Name');
    });

    test('fromJson подставляет имя=id при пустом имени', () {
      final json = <String, dynamic>{'id': 'cat-xyz', 'name': ''};
      final category = Category.fromJson(json);
      expect(category.name, 'cat-xyz');
    });

    test('fromJson нормализует colorValue к ARGB с alpha=0xFF', () {
      final json = <String, dynamic>{'id': '1', 'colorValue': 0xAABBCC};
      final category = Category.fromJson(json);
      expect(category.colorValue, 0xFFAABBCC);
    });

    test('fromJson обрезает colorValue до 24 бит', () {
      final json = <String, dynamic>{'id': '1', 'colorValue': 0x11223344};
      final category = Category.fromJson(json);
      expect(category.colorValue, 0xFF223344);
    });

    test('fromJson подставляет defaultColorValue при отсутствии', () {
      final json = <String, dynamic>{'id': '1'};
      final category = Category.fromJson(json);
      expect(category.colorValue, Category.defaultColorValue);
    });

    test('fromJson подставляет defaultIconKey при пустом', () {
      final json = <String, dynamic>{'id': '1', 'iconKey': ''};
      final category = Category.fromJson(json);
      expect(category.iconKey, Category.defaultIconKey);
    });

    test('fromJson парсит order', () {
      final json = <String, dynamic>{'id': '1', 'order': 42};
      final category = Category.fromJson(json);
      expect(category.order, 42);
    });

    test('fromJson подставляет 0 при отсутствии order', () {
      final json = <String, dynamic>{'id': '1'};
      final category = Category.fromJson(json);
      expect(category.order, 0);
    });

    test('copyWith обновляет только указанные поля', () {
      const original = Category(
        id: '1',
        name: 'Original',
        iconKey: 'star',
        colorValue: 0xFF111111,
        order: 10,
      );

      final updated = original.copyWith(
        name: 'Updated',
        colorValue: 0xFF222222,
        order: 20,
      );

      expect(updated.id, '1');
      expect(updated.name, 'Updated');
      expect(updated.iconKey, 'star');
      expect(updated.colorValue, 0xFF222222);
      expect(updated.order, 20);
    });

    test('storageKey и idFromStorageKey — обратные операции', () {
      expect(Category.storageKey('abc'), 'category:abc');
      expect(Category.idFromStorageKey('category:abc'), 'abc');
      expect(Category.idFromStorageKey('category:'), null);
      expect(Category.idFromStorageKey('other:abc'), null);
    });

    test('nameKey нормализует для сравнения (lowercase, trim)', () {
      expect(Category.nameKey('Test'), 'test');
      expect(Category.nameKey('  Test  '), 'test');
      expect(Category.nameKey('TEST'), 'test');
      expect(Category.nameKey('TeSt'), 'test');
    });

    test('normalizeName выбрасывает на пустой строке', () {
      expect(() => Category.normalizeName(''), throwsFormatException);
      expect(() => Category.normalizeName('   '), throwsFormatException);
    });

    test('normalizeColor приводит к непрозрачному ARGB', () {
      expect(Category.normalizeColor(0xAABBCC), 0xFFAABBCC);
      expect(Category.normalizeColor(-1), 0xFFFFFFFF);
      expect(Category.normalizeColor(0x11223344), 0xFF223344);
    });
  });
}