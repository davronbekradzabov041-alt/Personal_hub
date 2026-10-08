import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/backup/module_backup_reader.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_schema_marker.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/module_storage_serializer.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_category_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_migrator.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';

/// Хранилище в памяти. Объявлено локально, как и в остальных тестах
/// Schedule: общий double связал бы наборы подмен разных файлов.
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

/// Хранилище, рвущее ПЕРВУЮ запись ключа с указанным префиксом после
/// того, как значение легло на место.
///
/// Такой сбой проверяет откат по-настоящему: если бы запись падала до
/// мутации, прежние значения остались бы целы и тест ничего не
/// доказывал бы.
class _TornStorage implements ModuleStorage {
  _TornStorage(this._inner);

  final ModuleStorage _inner;

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

ScheduleEvent _event(String id, {String? categoryId, String category = ''}) {
  return ScheduleEvent(
    id: id,
    title: 'Событие $id',
    category: category,
    categoryId: categoryId,
    priority: EventPriority.medium,
    date: DateTime(2026, 1, 15),
    startMinutes: 9 * 60,
    endMinutes: 10 * 60,
    status: EventStatus.planned,
  );
}

ModuleStateSnapshot _snapshot() => ModuleStateSnapshot(
      moduleId: 'schedule',
      state: 'enabled',
      installedVersion: '0.1.0',
      enabled: true,
      installedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

void main() {
  late ModuleManager manager;
  late _FakeModuleStorage storage;
  late _FakeModuleStateStore stateStore;
  late Directory tempRoot;
  late Directory assetsDir;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(ScheduleModule());

    storage = _FakeModuleStorage();
    stateStore = _FakeModuleStateStore();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => storage,
    );
    // setStateForTesting: модуль помечается установленным БЕЗ вызова
    // onInstall, чтобы состояние миграции задавал сам тест.
    manager.setStateForTesting('schedule', ModuleState.enabled);

    tempRoot = Directory.systemTemp.createTempSync('schedule_pmb_');
    assetsDir = Directory('${tempRoot.path}/assets')..createSync(recursive: true);
  });

  tearDown(() {
    manager.dispose();
    ModuleRegistry.clear();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  ModuleBackupManager makeManager({ModuleStorage? target}) => ModuleBackupManager(
        moduleManager: target == null
            ? manager
            : ModuleManager(
                searchService: GlobalSearchService(),
                storageFactory: (_) => target,
              )..setStateForTesting('schedule', ModuleState.enabled),
        stateStore: stateStore,
        assetsDirectoryResolver: (_) async => assetsDir,
      );

  Future<List<int>> backup(
    ModuleStorage from, {
    ModuleBackupOptions options = const ModuleBackupOptions(),
  }) async {
    if (!identical(from, storage)) {
      // Отдельный менеджер нужен, чтобы архив снимался с того хранилища,
      // которое тест подготовил, а не с дефолтного.
      final alt = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => from,
      );
      addTearDown(alt.dispose);
      alt.setStateForTesting('schedule', ModuleState.enabled);
      final outDir = Directory('${tempRoot.path}/out')..createSync(recursive: true);
      final result = await ModuleBackupManager(
        moduleManager: alt,
        stateStore: stateStore,
        assetsDirectoryResolver: (_) async => assetsDir,
      ).createBackup(moduleId: 'schedule', outputDirectory: outDir, options: options);
      return File(result.outputPath).readAsBytes();
    }

    final outDir = Directory('${tempRoot.path}/out')..createSync(recursive: true);
    final result = await makeManager().createBackup(
      moduleId: 'schedule',
      outputDirectory: outDir,
      options: options,
    );
    return File(result.outputPath).readAsBytes();
  }

  /// Заполняет хранилище перенесёнными данными: категория + связанное
  /// событие + маркер версии.
  Future<List<String>> seedMigrated() async {
    final categories = ScheduleCategoryRepository(storage);
    final events = ScheduleRepository(storage);
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
    await events.add(_event('e1', categoryId: work.id, category: 'Работа'));
    await events.add(_event('e2', category: 'Учёба'));
    // Маркер пишется платформенным API, а не литералом: начиная с
    // Этапа 9.1 формат записи принадлежит ModuleSchemaMarker, и тест,
    // пишущий его вручную, проверял бы уже не тот формат, который
    // читает приложение.
    await ModuleSchemaMarker.write(
      storage,
      ScheduleMigrator.currentSchemaVersion,
    );
    return <String>[work.id];
  }

  group('.pmb модуля: категории и события', () {
    test('архив содержит и категории, и события, и маркер версии', () async {
      final workIds = await seedMigrated();
      await stateStore.save(_snapshot());

      final archive = await ModuleBackupReader.readModuleBackup(
        await backup(storage),
      );

      expect(archive.moduleId, 'schedule');
      expect(archive.dataJson, isNotNull);
      expect(archive.dataJson, contains('category:${workIds.single}'));
      expect(archive.dataJson, contains('event:e1'));
      expect(archive.dataJson, contains(ScheduleMigrator.schemaVersionKey));
      // Значения записей лежат внутри JSON-строки, поэтому и имя
      // категории, и её оформление должны быть видны в архиве.
      expect(archive.dataJson, contains(r'\"name\":\"Работа\"'));
      expect(archive.dataJson, contains(r'\"iconKey\":\"briefcase\"'));
      expect(archive.dataJson, contains(r'\"categoryId\"'));
    });

    test('полный round-trip возвращает категории и ссылки событий', () async {
      await seedMigrated();
      await stateStore.save(_snapshot());
      final bytes = await backup(storage);

      // Портим модуль после backup: удаляем категории, ломаем событие.
      await storage.remove('category:${(await ScheduleCategoryRepository(storage).getAll()).first.id}');
      await ScheduleRepository(storage).delete('e1');

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'schedule',
      );

      expect(result.isSuccess, isTrue, reason: 'ошибка: ${result.error}');
      final categories = await ScheduleCategoryRepository(storage).getAll();
      expect(categories.map((c) => c.name), containsAll(<String>['Работа', 'Учёба']));
      final work = categories.firstWhere((c) => c.name == 'Работа');
      final events = await ScheduleRepository(storage).getAll();
      expect(events, hasLength(2));
      expect(events.firstWhere((e) => e.id == 'e1').categoryId, work.id);
      expect(
        await ModuleSchemaMarker.read(storage),
        ScheduleMigrator.currentSchemaVersion,
      );
    });

    test('restore удаляет ключи, которых не было в архиве', () async {
      await seedMigrated();
      final bytes = await backup(storage);

      final categories = ScheduleCategoryRepository(storage);
      final extra = await categories.create(
        name: 'Создано после backup',
        colorValue: 0xFF778899,
        iconKey: 'star',
      );
      expect(await categories.getById(extra.id), isNotNull);

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'schedule',
      );

      expect(result.isSuccess, isTrue, reason: 'ошибка: ${result.error}');
      expect(await categories.getById(extra.id), isNull);
    });

    test('dataOnly возвращает категории, не трогая state', () async {
      await seedMigrated();
      await stateStore.save(_snapshot());
      final bytes = await backup(storage);
      await storage.remove('category:${(await ScheduleCategoryRepository(storage).getAll()).first.id}');
      await stateStore.save(ModuleStateSnapshot(
        moduleId: 'schedule',
        state: 'disabled',
        installedVersion: '0.1.0',
        enabled: false,
        installedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 3),
      ));

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'schedule',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(result.isSuccess, isTrue, reason: 'ошибка: ${result.error}');
      expect(result.appliedComponents, ['data']);
      expect(await ScheduleCategoryRepository(storage).getAll(), hasLength(2));
      expect((await stateStore.load('schedule'))!.state, 'disabled');
    });
  });

  group('.pmb модуля: неудачный restore откатывается', () {
    test('частичный сбой возвращает ПРЕЖНИЕ категории, а не пустое хранилище',
        () async {
      await seedMigrated();
      final bytes = await backup(storage);

      final categories = ScheduleCategoryRepository(storage);
      final before = {
        for (final category in await categories.getAll())
          Category.storageKey(category.id):
              jsonEncode(category.toJson()),
      };
      await categories.delete(before.keys.first.split(':').last);
      final afterDelete = {
        for (final category in await categories.getAll())
          Category.storageKey(category.id):
              jsonEncode(category.toJson()),
      };
      expect(afterDelete.length, lessThan(before.length));

      final torn = _TornStorage(storage)..tearPrefix = 'category:';
      final result = await makeManager(target: torn).restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'schedule',
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(result.rolledBackComponents, contains('data'));

      // Хранилище вернулось к состоянию ДО restore, а не к пустому.
      final restored = {
        for (final category in await categories.getAll())
          Category.storageKey(category.id):
              jsonEncode(category.toJson()),
      };
      expect(restored, afterDelete);
      expect((await ScheduleRepository(storage).getAll()), isNotEmpty);
    });
  });

  group('Данные модуля в глобальном архиве', () {
    test('тот же сериализатор уносит и категории, и маркер версии', () async {
      // Глобальный .pbk кладёт данные модуля в modules/<id>/data.json
      // через ModuleStorageSerializer — тот же класс, что и .pmb. Сам
      // writer собирается на Isar, поэтому проверяется ровно та часть,
      // которая принадлежит модулю: ничего не теряется и не появляется
      // в сериализованном виде.
      await seedMigrated();

      final json = await ModuleStorageSerializer.serialize(
        storage: storage,
        moduleId: 'schedule',
      );

      final entries = (jsonDecode(json) as Map<String, dynamic>)['entries']
          as Map<String, dynamic>;
      expect(
        entries.keys.where((k) => k.startsWith('category:')),
        hasLength(2),
      );
      expect(entries.keys, contains('event:e1'));
      // В архиве маркер лежит строкой — ModuleStorage хранит строки.
      // Проверяется ровно то, что читает restore, а не то, что вернул
      // бы int-константа: формат на диске задаёт ModuleSchemaMarker.
      expect(entries[ScheduleMigrator.schemaVersionKey],
          '${ScheduleMigrator.currentSchemaVersion}');

      final restored = _FakeModuleStorage();
      await ModuleStorageSerializer.deserialize(
        jsonString: json,
        storage: restored,
        expectedModuleId: 'schedule',
      );
      expect(restored.data, storage.data);
    });

    test('backup до миграции после restore доходит до того же состояния',
        () async {
      // Архив, снятый ДО Этапа 7.2: ни категорий, ни маркера, только
      // строки в событиях. Restore возвращает ровно эти данные, а
      // следующая миграция приводит их к тому же состоянию, что и у
      // данных, мигрированных на месте.
      await storage.setString(
        'event:legacy',
        jsonEncode(<String, dynamic>{
          'id': 'legacy',
          'title': 'Старое событие',
          'category': 'Работа',
          'priority': 'medium',
          'date': '2026-01-15',
          'startMinutes': 540,
          'endMinutes': 600,
          'status': 'planned',
          'note': '',
        }),
      );
      final bytes = await backup(storage, options: const ModuleBackupOptions.dataOnly());
      expect(
        (await ModuleBackupReader.readModuleBackup(bytes)).dataJson,
        isNot(contains('category:')),
      );

      // Restore в чистое хранилище и миграция после него.
      final clean = _FakeModuleStorage();
      final alt = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => clean,
      );
      addTearDown(alt.dispose);
      alt.setStateForTesting('schedule', ModuleState.enabled);
      final restored = await ModuleBackupManager(
        moduleManager: alt,
        stateStore: stateStore,
        assetsDirectoryResolver: (_) async => assetsDir,
      ).restoreBackup(archiveBytes: bytes, targetModuleId: 'schedule');
      expect(restored.isSuccess, isTrue, reason: 'ошибка: ${restored.error}');

      final result = await ScheduleMigrator(clean).run();

      expect(result.createdCategories, 1);
      expect(result.linkedEvents, 1);
      final categories = await ScheduleCategoryRepository(clean).getAll();
      expect(categories.single.name, 'Работа');
      expect((await ScheduleRepository(clean).getAll()).single.categoryId,
          categories.single.id);
    });
  });
}