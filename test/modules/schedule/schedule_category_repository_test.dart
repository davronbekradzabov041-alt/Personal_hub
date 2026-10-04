import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';

/// Хранилище в памяти — тот же double, что в schedule_module_test.dart.
///
/// Объявлен заново, а не вынесен в общий файл: каждый тест Schedule
/// закрыт своим набором подмен, и общий double сделал бы их зависимыми
/// друг от друга.
class _FakeModuleStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

/// ModuleStateStore в памяти — для проверки, что uninstall стирает
/// категории вместе с событиями.
class _FakeModuleStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};

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

/// Репозиторий с фиксированным генератором id: без него нельзя
/// детерминированно проверить, что create не занимает уже занятый ключ.
ScheduleCategoryRepository _repo(
  ModuleStorage storage, {
  int Function()? idGenerator,
}) {
  return ScheduleCategoryRepository(storage, idGenerator: idGenerator);
}

Future<Category> _create(
  ScheduleCategoryRepository repository, {
  required String name,
  int colorValue = 0xFF1F2438,
  String iconKey = 'work',
}) {
  return repository.create(
    name: name,
    colorValue: colorValue,
    iconKey: iconKey,
  );
}

void main() {
  late _FakeModuleStorage storage;
  late ScheduleCategoryRepository repository;

  setUp(() {
    ModuleRegistry.clear();
    storage = _FakeModuleStorage();
    repository = _repo(storage);
  });

  tearDown(ModuleRegistry.clear);

  group('Category — модель', () {
    test('normalizeColor приводит alpha к 0xFF и обрезает старшие биты', () {
      expect(Category.normalizeColor(0x00123456), 0xFF123456);
      expect(Category.normalizeColor(0x80123456), 0xFF123456);
      expect(Category.normalizeColor(0xFF123456), 0xFF123456);
      // Отрицательное значение (мусор из рукописного backup) обрезается
      // до RGB, а не превращается в мусор.
      expect(Category.normalizeColor(-1), 0xFFFFFFFF);
    });

    test('normalizeName обрезает края', () {
      expect(Category.normalizeName('  Работа \n'), 'Работа');
    });

    test('normalizeName отклоняет пустое имя', () {
      expect(() => Category.normalizeName('   '), throwsFormatException);
    });

    test('nameKey игнорирует регистр и края пробелов', () {
      expect(Category.nameKey('  Учёба '), Category.nameKey('учёба'));
    });

    test('storageKey и idFromStorageKey — обратные друг другу', () {
      expect(Category.storageKey('42'), 'category:42');
      expect(Category.idFromStorageKey('category:42'), '42');
      expect(Category.idFromStorageKey('event:42'), isNull);
      expect(Category.idFromStorageKey('category:'), isNull);
    });

    test('toJson/fromJson сохраняют все поля', () {
      const original = Category(
        id: '7',
        name: 'Работа',
        colorValue: 0xFFD97706,
        iconKey: 'briefcase',
        order: 3,
      );

      final restored = Category.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.colorValue, original.colorValue);
      expect(restored.iconKey, original.iconKey);
      expect(restored.order, original.order);
    });

    test('fromJson берёт id из запасного значения, когда в теле его нет', () {
      final category = Category.fromJson(
        <String, dynamic>{'name': 'Работа'},
        fallbackId: '99',
      );

      expect(category.id, '99');
      expect(category.name, 'Работа');
    });

    test('fromJson без какого-либо id — ошибка формата', () {
      expect(
        () => Category.fromJson(<String, dynamic>{'name': 'Работа'}),
        throwsFormatException,
      );
    });

    test('fromJson не падает на битых полях, а подставляет запасные', () {
      final category = Category.fromJson(<String, dynamic>{
        'id': '5',
        'name': 'Работа',
        'colorValue': 'не число',
        'iconKey': '   ',
        'order': 1.5,
      });

      expect(category.colorValue, Category.defaultColorValue);
      expect(category.iconKey, Category.defaultIconKey);
      expect(category.order, 0);
    });

    test('fromJson нормализует alpha и обрезает имя', () {
      final category = Category.fromJson(<String, dynamic>{
        'id': '5',
        'name': '  Работа  ',
        'colorValue': 0x00123456,
      });

      expect(category.name, 'Работа');
      expect(category.colorValue, 0xFF123456);
    });
  });

  group('ScheduleCategoryRepository — CRUD', () {
    test('создание пишет одну запись по ключу category:<id>', () async {
      final category = await _create(repository, name: 'Работа');

      expect(storage.data.keys, <String>{'category:${category.id}'});
      expect(await repository.getById(category.id), isNotNull);
    });

    test('созданная категория читается обратно с теми же полями', () async {
      final created =
          await _create(repository, name: 'Работа', colorValue: 0xFFD97706, iconKey: 'briefcase');

      final loaded = await repository.getById(created.id);

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Работа');
      expect(loaded.colorValue, 0xFFD97706);
      expect(loaded.iconKey, 'briefcase');
    });

    test('getById для несуществующего id возвращает null', () async {
      expect(await repository.getById('нет-такого'), isNull);
    });

    test('getAll возвращает созданные в порядке создания', () async {
      await _create(repository, name: 'Работа');
      await _create(repository, name: 'Учёба');
      await _create(repository, name: 'Дом');

      expect(
        (await repository.getAll()).map((c) => c.name),
        <String>['Работа', 'Учёба', 'Дом'],
      );
    });

    test('getAll игнорирует чужие ключи этого же модуля', () async {
      await _create(repository, name: 'Работа');
      await storage.setString('note', 'не категория');

      expect((await repository.getAll()).map((c) => c.name), <String>['Работа']);
    });

    test('обновление меняет поля и сохраняет id и порядок', () async {
      final created = await _create(repository, name: 'Работа');
      await _create(repository, name: 'Учёба');

      final updated = await repository.update(
        id: created.id,
        name: 'Работа (2026)',
        colorValue: 0xFF059669,
        iconKey: 'case',
      );

      expect(updated.id, created.id);
      expect(updated.name, 'Работа (2026)');
      expect(updated.colorValue, 0xFF059669);
      expect(updated.iconKey, 'case');
      expect(updated.order, 0, reason: 'переименование не двигает категорию');

      final reloaded = await repository.getById(created.id);
      expect(reloaded!.name, 'Работа (2026)');
      expect(reloaded.colorValue, 0xFF059669);
    });

    test('обновление не добавляет и не удаляет записи', () async {
      final created = await _create(repository, name: 'Работа');

      await repository.update(
        id: created.id,
        name: 'Работа 2',
        colorValue: 0xFF000000,
        iconKey: 'work',
      );

      expect(storage.data.keys, hasLength(1));
    });

    test('удаление убирает ключ', () async {
      final created = await _create(repository, name: 'Работа');

      await repository.delete(created.id);

      expect(storage.data, isEmpty);
      expect(await repository.getById(created.id), isNull);
    });

    test('удаление и обновление несуществующей категории — ошибка', () async {
      await expectLater(repository.delete('нет'), throwsA(isA<ScheduleCategoryException>()));
      await expectLater(
        repository.update(
          id: 'нет',
          name: 'Работа',
          colorValue: 0xFF000000,
          iconKey: 'work',
        ),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('findByName находит без учёта регистра и пробелов', () async {
      final created = await _create(repository, name: 'Работа');

      expect(await repository.findByName('  работа '), isNotNull);
      expect((await repository.findByName('РАБОТА'))!.id, created.id);
      expect(await repository.findByName('Дом'), isNull);
    });

    test('создание нормализует имя и цвет', () async {
      final created = await _create(
        repository,
        name: '  Работа  ',
        colorValue: 0x00123456,
        iconKey: '  work  ',
      );

      expect(created.name, 'Работа');
      expect(created.colorValue, 0xFF123456);
      expect(created.iconKey, 'work');
    });

    test('пустое имя при создании и обновлении — ошибка', () async {
      await expectLater(
        _create(repository, name: '   '),
        throwsA(isA<ScheduleCategoryException>()),
      );

      final created = await _create(repository, name: 'Работа');
      await expectLater(
        repository.update(
          id: created.id,
          name: '  ',
          colorValue: 0xFF000000,
          iconKey: 'work',
        ),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('пустая иконка — ошибка', () async {
      await expectLater(
        _create(repository, name: 'Работа', iconKey: '   '),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });
  });

  group('ScheduleCategoryRepository — уникальность имени', () {
    test('дубль имени запрещён', () async {
      await _create(repository, name: 'Работа');

      await expectLater(
        _create(repository, name: 'Работа'),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('дубль запрещён без учёта регистра', () async {
      await _create(repository, name: 'Работа');

      await expectLater(
        _create(repository, name: 'РАБОТА'),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('дубль запрещён с учётом краёв пробелов', () async {
      await _create(repository, name: 'Работа');

      await expectLater(
        _create(repository, name: '  работа  '),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('неудачное создание дубля не оставляет записей', () async {
      await _create(repository, name: 'Работа');

      await expectLater(
        _create(repository, name: 'работа'),
        throwsA(isA<ScheduleCategoryException>()),
      );

      expect(storage.data, hasLength(1));
    });

    test('переименование в имя другой категории запрещено', () async {
      final first = await _create(repository, name: 'Работа');
      await _create(repository, name: 'Учёба');

      await expectLater(
        repository.update(
          id: first.id,
          name: 'учёба',
          colorValue: 0xFF000000,
          iconKey: 'work',
        ),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('переименование в то же имя не считается конфликтом с собой', () async {
      final created = await _create(repository, name: 'Работа');

      final updated = await repository.update(
        id: created.id,
        name: 'Работа',
        colorValue: 0xFFD97706,
        iconKey: 'work',
      );

      expect(updated.name, 'Работа');
    });

    test('одноимённые категории можно снова создать после удаления', () async {
      await _create(repository, name: 'Работа');
      final first = await repository.findByName('работа');
      await repository.delete(first!.id);

      final second = await _create(repository, name: 'работа');

      // id не проверяем: он выводится из микросекундного счётчика, и
      // освободившийся ключ вполне может быть выдан снова. Это
      // безвредно — единственное требование к id здесь «не занимать
      // занятый ключ», и оно проверяется отдельно в группе «выдача id».
      expect(storage.data, hasLength(1));
      expect((await repository.getAll()).map((c) => c.name), <String>['работа']);
      expect((await repository.findByName('Работа'))!.id, second.id);
    });
  });

  group('ScheduleCategoryRepository — порядок', () {
    test('создание добавляет в конец плотного 0..n-1', () async {
      final first = await _create(repository, name: 'Работа');
      final second = await _create(repository, name: 'Учёба');
      final third = await _create(repository, name: 'Дом');

      expect(first.order, 0);
      expect(second.order, 1);
      expect(third.order, 2);
    });

    test('удаление из середины перенумеровывает без пропусков', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');
      final c = await _create(repository, name: 'C');
      final d = await _create(repository, name: 'D');

      await repository.delete(b.id);

      final remaining = await repository.getAll();
      expect(remaining.map((c) => c.name), <String>['A', 'C', 'D']);
      expect(remaining.map((c) => c.order), <int>[0, 1, 2]);
      // Записи ниже удалённой позиции не должны быть переписаны: их
      // order уже совпадает с новым индексом.
      expect((await repository.getById(c.id))!.order, 1);
      expect((await repository.getById(d.id))!.order, 2);
      expect(await repository.getById(a.id), isNotNull);
    });

    test('удаление последней оставляет плотный порядок', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      await repository.delete(b.id);

      expect((await repository.getAll()).map((c) => c.order), <int>[0]);
      expect((await repository.getById(a.id))!.order, 0);
    });

    test('reorder задаёт плотный 0..n-1 в заданном порядке', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');
      final c = await _create(repository, name: 'C');

      await repository.reorder(<String>[c.id, a.id, b.id]);

      final all = await repository.getAll();
      expect(all.map((x) => x.name), <String>['C', 'A', 'B']);
      expect(all.map((x) => x.order), <int>[0, 1, 2]);
    });

    test('reorder идемпотентен', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');
      final c = await _create(repository, name: 'C');

      await repository.reorder(<String>[c.id, a.id, b.id]);
      final first = Map<String, int>.fromEntries(
        (await repository.getAll()).map((x) => MapEntry(x.id, x.order)),
      );

      await repository.reorder(<String>[c.id, a.id, b.id]);
      final second = Map<String, int>.fromEntries(
        (await repository.getAll()).map((x) => MapEntry(x.id, x.order)),
      );

      expect(second, first);
      expect(first.values.toList()..sort(), <int>[0, 1, 2]);
    });

    test('reorder с текущим порядком ничего не ломает', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      await repository.reorder(<String>[a.id, b.id]);

      expect((await repository.getAll()).map((x) => x.order), <int>[0, 1]);
    });

    test('после reorder новая категория встаёт в конец', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');
      final c = await _create(repository, name: 'C');

      await repository.reorder(<String>[b.id, a.id, c.id]);
      final d = await _create(repository, name: 'D');

      expect(d.order, 3);
      expect(
        (await repository.getAll()).map((x) => x.name),
        <String>['B', 'A', 'C', 'D'],
      );
    });

    test('reorder с неполным списком — ошибка', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      await expectLater(
        repository.reorder(<String>[a.id]),
        throwsA(isA<ScheduleCategoryException>()),
      );
      expect(b.id, isNotEmpty);
    });

    test('reorder с неизвестным id — ошибка', () async {
      final a = await _create(repository, name: 'A');

      await expectLater(
        repository.reorder(<String>[a.id, 'нет-такого']),
        throwsA(isA<ScheduleCategoryException>()),
      );
    });

    test('reorder с повтором id — ошибка', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      await expectLater(
        repository.reorder(<String>[a.id, a.id]),
        throwsA(isA<ScheduleCategoryException>()),
      );
      expect(b.id, isNotEmpty);
    });

    test('неудачный reorder не меняет порядок', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      await expectLater(
        repository.reorder(<String>[b.id, 'нет-такого', a.id]),
        throwsA(isA<ScheduleCategoryException>()),
      );

      expect((await repository.getAll()).map((x) => x.name), <String>['A', 'B']);
    });

    test('повторяющиеся order читаются детерминированно по id', () async {
      final a = await _create(repository, name: 'A');
      final b = await _create(repository, name: 'B');

      // Сломанный порядок: обе категории с order 0.
      await storage.setString(
        Category.storageKey(a.id),
        jsonEncode(a.copyWith(order: 0).toJson()),
      );
      await storage.setString(
        Category.storageKey(b.id),
        jsonEncode(b.copyWith(order: 0).toJson()),
      );

      final all = await repository.getAll();
      expect(all.map((x) => x.order), <int>[0, 0]);
      expect(all.map((x) => x.id).toList(), all.map((x) => x.id).toList()..sort());
    });
  });

  group('ScheduleCategoryRepository — persistence', () {
    test('категории переживают «перезапуск»: тот же storage, новый репозиторий',
        () async {
      await _create(repository, name: 'Работа', colorValue: 0xFFD97706, iconKey: 'work');

      final reloaded = await _repo(storage).getAll();

      expect(reloaded, hasLength(1));
      expect(reloaded.single.name, 'Работа');
      expect(reloaded.single.colorValue, 0xFFD97706);
      expect(reloaded.single.iconKey, 'work');
    });

    test('включение и выключение модуля не теряют категории', () async {
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(ScheduleModule());
      addTearDown(ModuleRegistry.clear);

      await manager.install('schedule');
      await manager.enable('schedule');

      await _repo(manager.apiFor('schedule').storage)
          .create(name: 'Работа', colorValue: 0xFFD97706, iconKey: 'work');

      await manager.disable('schedule');
      await manager.enable('schedule');

      final categories = await _repo(storage).getAll();
      expect(categories.map((c) => c.name), <String>['Работа']);
    });

    test('uninstall стирает категории вместе с событиями', () async {
      final store = _FakeModuleStateStore();
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => storage,
      );
      final persistence = ModuleStatePersistence(
        manager,
        store,
        storageFactory: (_) => storage,
      );
      addTearDown(persistence.dispose);
      ModuleRegistry.register(ScheduleModule());
      addTearDown(ModuleRegistry.clear);

      await manager.install('schedule');
      await manager.enable('schedule');

      await _repo(storage).create(
        name: 'Работа',
        colorValue: 0xFFD97706,
        iconKey: 'work',
      );
      await ScheduleRepository(storage).add(
        ScheduleEvent(
          id: 'event-1',
          title: 'Встреча',
          category: '',
          priority: EventPriority.medium,
          date: DateTime(2026, 1, 15),
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          status: EventStatus.planned,
        ),
      );

      expect(storage.data.keys.any((k) => k.startsWith('category:')), isTrue);

      await manager.disable('schedule');
      await manager.uninstall('schedule');
      // ModuleStatePersistence реагирует на notifyListeners() асинхронно,
      // поэтому дожидаемся очереди записей.
      await persistence.flush();

      expect(storage.data, isEmpty, reason: 'категории и события стёрты вместе');
    });
  });

  group('ScheduleCategoryRepository — битые данные', () {
    test('нечитаемая запись пропускается, остальные читаются', () async {
      final good = await _create(repository, name: 'Работа');
      await storage.setString('category:битая', 'не json вовсе');

      final all = await repository.getAll();

      expect(all.map((c) => c.id), <String>[good.id]);
    });

    test('запись без object-тела пропускается', () async {
      final good = await _create(repository, name: 'Работа');
      await storage.setString('category:строка', '"просто строка"');

      expect((await repository.getAll()).map((c) => c.id), <String>[good.id]);
    });

    test('битые поля записи не роняют чтение', () async {
      final good = await _create(repository, name: 'Работа');
      await storage.setString(
        'category:битые-поля',
        '{"colorValue": "не число", "order": null, "iconKey": ""}',
      );

      final all = await repository.getAll();

      expect(all, hasLength(2));
      final broken = all.firstWhere((c) => c.id == 'битые-поля');
      expect(broken.colorValue, Category.defaultColorValue);
      expect(broken.iconKey, Category.defaultIconKey);
      expect(broken.order, 0);
      // Идентичность битой записи восстановлена из ключа хранения.
      expect(broken.name, 'битые-поля');
      expect(good.id, isNot(broken.id));
    });

    test('id из тела записи приоритетнее ключа хранения', () async {
      await _create(repository, name: 'Работа');
      await storage.setString(
        'category:ключ',
        '{"id": "из-тела", "name": "Работа", "order": 0}',
      );

      final all = await repository.getAll();

      expect(all.map((c) => c.id), contains('из-тела'));
      expect(all.map((c) => c.id), isNot(contains('ключ')));
    });

    test('повторяющийся id в разных ключах даёт две записи, читаются обе',
        () async {
      await storage.setString('category:один', '{"id": "x", "name": "A", "order": 0}');
      await storage.setString('category:два', '{"id": "x", "name": "B", "order": 1}');

      expect(await repository.getAll(), hasLength(2));
    });
  });

  group('ScheduleCategoryRepository — выдача id', () {
    test('занятый id не переиспользуется', () async {
      // Генератор всегда возвращает одно и то же значение — так же
      // поступают два категории, созданные в один и тот же тик.
      final fixed = _repo(storage, idGenerator: () => 100);

      final first = await _create(fixed, name: 'A');
      final second = await _create(fixed, name: 'B');

      expect(first.id, '100');
      expect(second.id, '101');
      expect(storage.data.keys, hasLength(2));
    });

    test('поиск свободного id продолжается через занятые значения', () async {
      var next = 10;
      final repo = _repo(storage, idGenerator: () => next++);

      await _create(repo, name: 'A');
      await _create(repo, name: 'B');
      final third = await _create(repo, name: 'C');

      expect(third.id, '12');
      expect((await repo.getAll()).map((c) => c.id), <String>['10', '11', '12']);
    });
  });

  group('ScheduleCategoryRepository — удаление разрывает ссылки', () {
    late ScheduleRepository events;

    setUp(() {
      events = ScheduleRepository(storage);
    });

    ScheduleEvent eventOf({
      required String id,
      String category = '',
      String? categoryId,
      String title = 'Событие',
    }) {
      return ScheduleEvent(
        id: id,
        title: title,
        category: category,
        categoryId: categoryId,
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        status: EventStatus.planned,
      );
    }

    test('удаление категории снимает ссылку с её событий', () async {
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'e1', categoryId: work.id, category: 'Работа'));
      await events.add(eventOf(id: 'e2', categoryId: work.id, category: 'Работа'));

      await repository.delete(work.id);

      final all = await events.getAll();
      expect(all, hasLength(2), reason: 'события не удаляются — теряются данные');
      for (final event in all) {
        expect(event.categoryId, isNull);
        // Устаревшая строка очищается вместе со ссылкой: иначе
        // миграция без маркера воскресила бы удалённую категорию.
        expect(event.category, isEmpty);
      }
    });

    test('очищается и устаревшее имя у события без ссылки', () async {
      // Такое состояние бывает на данных, ещё не прошедших миграцию:
      // строка есть, ссылки нет. Оставить её — значит вернуть
      // удалённую категорию при следующей миграции.
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'legacy', category: ' работа '));

      await repository.delete(work.id);

      final event = (await events.getAll()).single;
      expect(event.categoryId, isNull);
      expect(event.category, isEmpty);
    });

    test('чужое имя не трогается', () async {
      final work = await _create(repository, name: 'Работа');
      final study = await _create(repository, name: 'Учёба');
      await events.add(eventOf(id: 'other', category: 'Учёба'));
      await events.add(
        eventOf(id: 'linked', category: 'Учёба', categoryId: study.id),
      );

      await repository.delete(work.id);

      final all = await events.getAll();
      expect(all, hasLength(2));
      final byId = {for (final event in all) event.id: event};

      // Событие с чужой ссылкой сохраняет и её, и устаревшую строку.
      expect(byId['linked']!.categoryId, study.id);
      expect(byId['linked']!.category, 'Учёба');

      // Событие без ссылки сохраняет строку — удаление «Работы» не
      // имеет права трогать чужую категорию.
      expect(byId['other']!.categoryId, isNull);
      expect(byId['other']!.category, 'Учёба');
    });

    test('после удаления порядок остаётся плотным 0..n-1', () async {
      final a = await _create(repository, name: 'A');
      await _create(repository, name: 'B');
      await _create(repository, name: 'C');

      await repository.delete(a.id);

      final remaining = await repository.getAll();
      expect(remaining.map((c) => c.name), <String>['B', 'C']);
      expect(remaining.map((c) => c.order), <int>[0, 1]);
    });

    test('события очищаются ДО удаления самой категории', () async {
      // Порядок записи — часть контракта: оборванный процесс не должен
      // оставить событие, ссылающееся на уже несуществующую категорию.
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'e1', categoryId: work.id, category: 'Работа'));

      final torn = _TornEventStorage(storage)
        ..failAfterEventUpdate = true;
      final events2 = ScheduleRepository(torn);
      final repo2 = ScheduleCategoryRepository(
        torn,
        eventRepository: events2,
      );

      await expectLater(repo2.delete(work.id), throwsA(isA<StateError>()));

      // Категория на месте (удаление не дошло), ссылка уже снята.
      expect(await torn.getString('category:${work.id}'), isNotNull);
      expect((await events2.getAll()).single.categoryId, isNull);
    });

    test('удаление несуществующей категории — ошибка, данные не тронуты', () async {
      await _create(repository, name: 'Работа');

      await expectLater(
        repository.delete('999'),
        throwsA(isA<ScheduleCategoryException>()),
      );

      expect(await repository.getAll(), hasLength(1));
    });

    test('счётчик событий совпадает с тем, что удаление затронет',
        () async {
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'byId', categoryId: work.id));
      await events.add(eventOf(id: 'byLegacy', category: ' работа '));

      expect(await repository.countLinkedEvents(work.id), 2);
    });

    test('счётчик не считает чужие события', () async {
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'other', category: 'Учёба'));
      await events.add(eventOf(id: 'linked', category: 'Учёба', categoryId: 'другой'));

      expect(await repository.countLinkedEvents(work.id), 0);
    });

    test('счётчик снятой категории равен нулю, а не падает', () async {
      // Диалог удаления открыт по кнопке в строке: категорию могли удалить
      // с другого экрана, пока он был открыт.
      expect(await repository.countLinkedEvents('999'), 0);
    });

    test('после удаления счётчик обнуляется', () async {
      final work = await _create(repository, name: 'Работа');
      await events.add(eventOf(id: 'e1', categoryId: work.id, category: 'Работа'));
      expect(await repository.countLinkedEvents(work.id), 1);

      await repository.delete(work.id);

      expect(await repository.countLinkedEvents(work.id), 0);
    });
  });
}

/// Хранилище, которое рвёт запись события ПОСЛЕ успешной мутации.
class _TornEventStorage implements ModuleStorage {
  _TornEventStorage(this._inner);

  final ModuleStorage _inner;

  /// Рвать запись сразу после того, как значение события легло в
  /// хранилище (но до успешного возврата).
  bool failAfterEventUpdate = false;

  @override
  Future<String?> getString(String key) => _inner.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _inner.setString(key, value);
    if (failAfterEventUpdate && key.startsWith('event:')) {
      failAfterEventUpdate = false;
      throw StateError('имитация сбоя после записи события');
    }
  }

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<List<String>> keys() => _inner.keys();
}