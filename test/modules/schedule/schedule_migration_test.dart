import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_migration_result.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_schema_marker.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_migrator.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';

/// Хранилище в памяти — тот же double, что в остальных тестах Schedule:
/// каждый тест закрыт своим набором подмен, общий double связал бы их.
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

/// Хранилище, рвущее запись КЛЮЧА ПОСЛЕ того, как значение легло на
/// место.
///
/// Именно такой сбой важен: если бы запись падала ДО мутации, данные
/// остались бы целы и тест ничего не доказывал бы.
class _TornStorage implements ModuleStorage {
  _TornStorage(this._inner);

  final ModuleStorage _inner;

  /// Префикс ключа, на первой записи которого хранилище сорвётся.
  ///
  /// Префикс, а не точный ключ: id категорий генерируется, и тест не
  /// должен зависеть от значения микросекундного счётчика.
  String? tearPrefix;

  bool _torn = false;

  @override
  Future<String?> getString(String key) => _inner.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _inner.setString(key, value);
    final prefix = tearPrefix;
    if (!_torn && prefix != null && key.startsWith(prefix)) {
      _torn = true;
      throw StateError('имитация сбоя после записи $key');
    }
  }

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<List<String>> keys() => _inner.keys();
}

/// Событие в состоянии «до Этапа 7.1»: строка категории есть, ссылки
/// нет — ровно то, что лежит в хранилище у реального пользователя.
ScheduleEvent _legacy(
  String id,
  String category, {
  DateTime? date,
  int startMinutes = 9 * 60,
}) {
  return ScheduleEvent(
    id: id,
    title: 'Событие $id',
    category: category,
    priority: EventPriority.medium,
    date: date ?? DateTime(2026, 1, 15),
    startMinutes: startMinutes,
    endMinutes: startMinutes + 60,
    status: EventStatus.planned,
  );
}

void main() {
  late _FakeModuleStorage storage;
  late ScheduleRepository events;
  late ScheduleCategoryRepository categories;

  setUp(() {
    ModuleRegistry.clear();
    storage = _FakeModuleStorage();
    events = ScheduleRepository(storage);
    categories = ScheduleCategoryRepository(storage);
  });

  tearDown(ModuleRegistry.clear);

  Future<void> seed(String key, Map<String, dynamic> json) =>
      storage.setString(key, jsonEncode(json));

  group('Миграция: перенос строковых категорий', () {
    test('старое имя становится категорией и ссылкой события', () async {
      await events.add(_legacy('e1', 'Работа'));

      final result = await ScheduleMigrator(storage).run();

      expect(result.ran, isTrue);
      // Отсутствие маркера с Этапа 9.1 означает исходную версию 1, а не
      // «неизвестно»: платформа разбирает маркер сама и молчаливого null
      // здесь быть не может — иначе «с какой версии переносить» зависело
      // бы от того, кто именно прочитал маркер.
      expect(result.previousVersion, '1', reason: 'маркера не было');
      expect(result.createdCategories, 1);
      expect(result.linkedEvents, 1);

      final all = await categories.getAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'Работа');
      expect(all.single.colorValue, Category.defaultColorValue);
      expect(all.single.iconKey, Category.defaultIconKey);

      final event = (await events.getAll()).single;
      expect(event.categoryId, all.single.id);
      // Строка сохраняется: это запасное значение для сборок без
      // categoryId и для чтения старых бэкапов.
      expect(event.category, 'Работа');
    });

    test('маркер версии записывается последним и в конце концов', () async {
      await events.add(_legacy('e1', 'Работа'));

      await ScheduleMigrator(storage).run();

      expect(
        await ModuleSchemaMarker.read(storage),
        ScheduleMigrator.currentSchemaVersion,
      );
    });

    test('одно имя на много событий — одна категория', () async {
      await events.add(_legacy('e1', 'Работа'));
      await events.add(_legacy('e2', 'Работа'));
      await events.add(_legacy('e3', 'Работа'));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 1);
      expect(result.linkedEvents, 3);
      expect(await categories.getAll(), hasLength(1));

      final id = (await categories.getAll()).single.id;
      for (final event in await events.getAll()) {
        expect(event.categoryId, id);
      }
    });

    test('имена, различающиеся регистром, сливаются в одну категорию',
        () async {
      await events.add(_legacy('e1', 'Учёба'));
      await events.add(_legacy('e2', '  УЧЁБА '));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 1);
      expect(await categories.getAll(), hasLength(1));
      expect(
        (await categories.getAll()).single.name,
        'Учёба',
        reason: 'сохраняется написание первого появления',
      );
      expect((await events.getAll()).map((e) => e.categoryId).toSet(),
          hasLength(1));
    });

    test('пустое имя категории не создаёт ничего', () async {
      await events.add(_legacy('e1', ''));
      await events.add(_legacy('e2', '   '));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 0);
      expect(result.linkedEvents, 0);
      expect(await categories.getAll(), isEmpty);
      for (final event in await events.getAll()) {
        expect(event.categoryId, isNull);
      }
    });

    test('порядок категорий — первое появление в хронологии событий',
        () async {
      // Вставлены вперемешку с будущего в прошлое: порядок хранилища
      // о порядке пользователя ничего не говорит.
      await events.add(_legacy('late', 'Третья', date: DateTime(2026, 1, 16)));
      await events.add(
        _legacy('noon', 'Вторая', startMinutes: 12 * 60),
      );
      await events.add(
        _legacy('morning', 'Первая', startMinutes: 7 * 60),
      );

      await ScheduleMigrator(storage).run();

      final all = await categories.getAll();
      expect(all.map((c) => c.name), <String>['Первая', 'Вторая', 'Третья']);
      expect(all.map((c) => c.order), <int>[0, 1, 2]);
    });

    test('порядок детерминирован при равных дате и времени', () async {
      // List.sort не стабилен, поэтому tie-break по id — не косметика:
      // два одинаковых хранилища обязаны дать один и тот же результат.
      Future<List<String>> migrate(List<String> idsInOrder) async {
        final local = _FakeModuleStorage();
        final localEvents = ScheduleRepository(local);
        for (final id in idsInOrder) {
          await localEvents.add(_legacy(
            id,
            id == 'z' ? 'Первая' : 'Вторая',
            startMinutes: 9 * 60,
          ));
        }
        await ScheduleMigrator(local).run();
        final localCategories = ScheduleCategoryRepository(local);
        return (await localCategories.getAll()).map((c) => c.name).toList();
      }

      expect(await migrate(<String>['z', 'a']), <String>['Вторая', 'Первая']);
      expect(await migrate(<String>['a', 'z']), <String>['Вторая', 'Первая']);
    });
  });

  group('Миграция: существующие категории не дублируются', () {
    test('совпадающее имя переиспользует существующую категорию',
        () async {
      final existing = await categories.create(
        name: 'Работа',
        colorValue: 0xFF112233,
        iconKey: 'briefcase',
      );
      await events.add(_legacy('e1', 'Работа'));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 0);
      expect(result.linkedEvents, 1);

      final all = await categories.getAll();
      expect(all, hasLength(1));
      // Оформление пользователя не перетирается дефолтом миграции.
      expect(all.single.id, existing.id);
      expect(all.single.colorValue, 0xFF112233);
      expect(all.single.iconKey, 'briefcase');
      expect((await events.getAll()).single.categoryId, existing.id);
    });

    test('регистр и пробелы при сопоставлении игнорируются', () async {
      final existing = await categories.create(
        name: 'Учёба',
        colorValue: 0xFF445566,
        iconKey: 'book',
      );
      await events.add(_legacy('e1', ' учёба '));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 0);
      expect((await events.getAll()).single.categoryId, existing.id);
      expect(await categories.getAll(), hasLength(1));
    });

    test('чужая категория остаётся на своём месте, новая добавляется в конец',
        () async {
      final first = await categories.create(
        name: 'Здоровье',
        colorValue: 0xFF445566,
        iconKey: 'health',
      );
      await events.add(_legacy('e1', 'Работа'));

      await ScheduleMigrator(storage).run();

      final all = await categories.getAll();
      expect(all.map((c) => c.name), <String>['Здоровье', 'Работа']);
      expect(all.first.id, first.id);
      expect(all.first.order, 0);
    });

    test('уже проставленная ссылка не переписывается', () async {
      final work = await categories.create(
        name: 'Работа',
        colorValue: 0xFF112233,
        iconKey: 'briefcase',
      );
      await categories.create(
        name: 'Учёба',
        colorValue: 0xFF445566,
        iconKey: 'book',
      );
      // Ссылка ведёт на «Работу», а устаревшая строка говорит «Учёба».
      // Авторитетна ссылка — миграция не имеет права её менять.
      await events.add(
        ScheduleEvent(
          id: 'e1',
          title: 'Событие',
          category: 'Учёба',
          categoryId: work.id,
          priority: EventPriority.medium,
          date: DateTime(2026, 1, 15),
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          status: EventStatus.planned,
        ),
      );

      final result = await ScheduleMigrator(storage).run();

      expect(result.linkedEvents, 0);
      expect(result.createdCategories, 0);
      expect((await events.getAll()).single.categoryId, work.id);
    });

    test('разрывы в порядке категорий закрываются', () async {
      // Так может выглядеть хранилище, собранное несколькими
      // прерванными операциями.
      await seed('category:1', <String, dynamic>{
        'id': '1',
        'name': 'Первая',
        'colorValue': 0xFF112233,
        'iconKey': 'work',
        'order': 0,
      });
      await seed('category:2', <String, dynamic>{
        'id': '2',
        'name': 'Вторая',
        'colorValue': 0xFF112233,
        'iconKey': 'work',
        'order': 5,
      });
      await events.add(_legacy('e1', 'Третья'));

      await ScheduleMigrator(storage).run();

      final all = await categories.getAll();
      expect(all.map((c) => c.name), <String>['Первая', 'Вторая', 'Третья']);
      expect(all.map((c) => c.order), <int>[0, 1, 2]);
    });
  });

  group('Миграция: идемпотентность', () {
    test('второй запуск не делает ничего', () async {
      await events.add(_legacy('e1', 'Работа'));
      final migrator = ScheduleMigrator(storage);
      await migrator.run();

      final before = Map<String, String>.from(storage.data);
      final result = await ScheduleMigrator(storage).run();

      expect(result.ran, isFalse);
      expect(result.createdCategories, 0);
      expect(result.linkedEvents, 0);
      expect(storage.data, before, reason: 'хранилище не должно меняться');
    });

    test('потеря маркера не приводит к дублям и новым id', () async {
      // Старый бэкап или ручное редактирование хранилища. Настоящая
      // проверка идемпотентности: не «маркер есть», а «повторный проход
      // по перенесённым данным ничего не меняет».
      await events.add(_legacy('e1', 'Работа'));
      await ScheduleMigrator(storage).run();

      final afterFirstRun = Map<String, String>.from(storage.data);
      await storage.remove(ScheduleMigrator.schemaVersionKey);

      final result = await ScheduleMigrator(storage).run();

      expect(result.ran, isTrue);
      expect(result.createdCategories, 0);
      expect(result.linkedEvents, 0);
      expect(result.detachedEvents, 0);

      final all = await categories.getAll();
      expect(all, hasLength(1));
      expect(storage.data['category:${all.single.id}'],
          afterFirstRun['category:${all.single.id}']);
      expect((await events.getAll()).single.categoryId, all.single.id);
      expect(
        await ModuleSchemaMarker.read(storage),
        ScheduleMigrator.currentSchemaVersion,
      );
    });
  });

  group('Миграция: висячие ссылки', () {
    test('ссылка на несуществующую категорию чинится по старому имени',
        () async {
      await events.add(ScheduleEvent(
        id: 'e1',
        title: 'Событие',
        category: 'Работа',
        categoryId: 'уже-нет',
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        status: EventStatus.planned,
      ));

      final result = await ScheduleMigrator(storage).run();

      expect(result.createdCategories, 1);
      expect(result.linkedEvents, 1);
      expect(result.detachedEvents, 0);
      expect((await events.getAll()).single.categoryId,
          (await categories.getAll()).single.id);
    });

    test('ссылку, которую нечем чинить, снимают', () async {
      // Висит ссылка, а имени нет: восстановить нечего. Оставить её
      // значило бы сохранить ссылку, которая не разрешится никогда.
      await events.add(ScheduleEvent(
        id: 'e1',
        title: 'Событие',
        categoryId: 'уже-нет',
        priority: EventPriority.medium,
        date: DateTime(2026, 1, 15),
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        status: EventStatus.planned,
      ));

      final result = await ScheduleMigrator(storage).run();

      expect(result.detachedEvents, 1);
      expect(result.createdCategories, 0);
      expect((await events.getAll()).single.categoryId, isNull);
    });
  });

  group('Миграция: сбой посередине', () {
    test('маркер не пишется, если запись оборвалась', () async {
      await events.add(_legacy('e1', 'Работа'));
      final torn = _TornStorage(storage)..tearPrefix = 'category:';

      await expectLater(
        ScheduleMigrator(torn).run(),
        throwsA(isA<ModuleMigrationException>()
            .having((e) => e.cause, 'cause', isA<StateError>())),
      );

      expect(
        await storage.getString(ScheduleMigrator.schemaVersionKey),
        isNull,
        reason: 'без маркера миграция считается незавершённой и повторится',
      );
      expect((await events.getAll()).single.categoryId, isNull);
    });

    test('повторный запуск после сбоя завершает перенос', () async {
      await events.add(_legacy('e1', 'Работа'));
      final torn = _TornStorage(storage)..tearPrefix = 'category:';
      await expectLater(
        ScheduleMigrator(torn).run(),
        throwsA(isA<ModuleMigrationException>()
            .having((e) => e.cause, 'cause', isA<StateError>())),
      );

      final result = await ScheduleMigrator(storage).run();

      expect(result.ran, isTrue);
      expect(result.createdCategories, 0,
          reason: 'категория создана до сбоя — второй раз не создаётся');
      expect(result.linkedEvents, 1);
      expect(await categories.getAll(), hasLength(1));
      expect((await events.getAll()).single.categoryId,
          (await categories.getAll()).single.id);
      expect(
        await ModuleSchemaMarker.read(storage),
        ScheduleMigrator.currentSchemaVersion,
      );
    });
  });

  group('Миграция: свежая установка', () {
    test('пустое хранилище получает только маркер', () async {
      final result = await ScheduleMigrator(storage).run();

      expect(result.ran, isTrue);
      expect(result.createdCategories, 0);
      expect(await categories.getAll(), isEmpty);
      expect(
        await ModuleSchemaMarker.read(storage),
        ScheduleMigrator.currentSchemaVersion,
      );
    });
  });

  group('Миграция вызывается из жизненного цикла модуля', () {
    Future<ModuleManager> makeManager(ModuleStorage storage) async {
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => storage,
      );
      // Холодный старт — это новый процесс: реестр модулей пуст, и
      // ScheduleModule регистрируется заново. Регистрация поверх
      // предыдущей падала бы как «id уже занят».
      ModuleRegistry.clear();
      ModuleRegistry.register(ScheduleModule());
      return manager;
    }

    test('install переносит старые категории', () async {
      final manager = await makeManager(storage);
      addTearDown(manager.dispose);

      await events.add(_legacy('e1', 'Работа'));
      await manager.install('schedule');

      expect(manager.stateOf('schedule'), ModuleState.installed);
      final all = await categories.getAll();
      expect(all, hasLength(1));
      expect((await events.getAll()).single.categoryId, all.single.id);
    });

    test('сбой миграции НЕ роняет install и НЕ стирает данные', () async {
      // ModuleManager на ошибке в onInstall откатывает установку и стирает
      // хранилище модуля целиком. Поэтому onInstall обязан глотать ошибку
      // миграции: иначе один сбой записи стоил бы пользователю всех
      // событий расписания.
      final broken = _TornStorage(storage)..tearPrefix = 'category:';
      final manager = await makeManager(broken);
      addTearDown(manager.dispose);

      await ScheduleRepository(broken).add(_legacy('e1', 'Работа'));

      await manager.install('schedule');

      expect(manager.stateOf('schedule'), ModuleState.installed,
          reason: 'установка не должна падать из-за миграции');
      expect(manager.isInstalled('schedule'), isTrue);
      final restored = await ScheduleRepository(broken).getAll();
      expect(restored, hasLength(1),
          reason: 'данные пользователя переживают сбой миграции');
      expect(restored.single.title, 'Событие e1');
      // И миграция будет повторена: маркера нет.
      expect(await broken.getString(ScheduleMigrator.schemaVersionKey), isNull);
    });

    test('холодный старт не плодит дубли', () async {
      // onInstall вызывается на каждом холодном старте (ModuleStateRestorer
      // повторяет install() для восстановленного состояния) — значит
      // миграция должна быть безопасна при повторе.
      await events.add(_legacy('e1', 'Работа'));

      final firstStart = await makeManager(storage);
      await firstStart.install('schedule');
      firstStart.dispose();

      final afterFirst = Map<String, String>.from(storage.data);

      final secondStart = await makeManager(storage);
      addTearDown(secondStart.dispose);
      await secondStart.install('schedule');

      expect(storage.data, afterFirst);
      expect(await categories.getAll(), hasLength(1));
    });
  });
}