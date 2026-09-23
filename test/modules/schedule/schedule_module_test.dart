import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/schedule_search_provider.dart';

class _FakeModuleStorage implements ModuleStorage {
  final Map<String, String> data = {};

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

ScheduleEvent _event({
  String id = 'e1',
  String title = 'Встреча',
  String category = 'Работа',
  EventPriority priority = EventPriority.medium,
  DateTime? date,
  int startMinutes = 9 * 60,
  int endMinutes = 10 * 60,
  EventStatus status = EventStatus.planned,
  String note = '',
}) {
  return ScheduleEvent(
    id: id,
    title: title,
    category: category,
    priority: priority,
    date: date ?? DateTime(2026, 1, 15),
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    status: status,
    note: note,
  );
}

void main() {
  group('ScheduleRepository — CRUD', () {
    late _FakeModuleStorage storage;
    late ScheduleRepository repository;

    setUp(() {
      storage = _FakeModuleStorage();
      repository = ScheduleRepository(storage);
    });

    test('создание события', () async {
      await repository.add(_event());
      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.first.title, 'Встреча');
    });

    test('редактирование события', () async {
      await repository.add(_event());
      final updated = _event(title: 'Встреча (перенесена)', startMinutes: 11 * 60, endMinutes: 12 * 60);
      await repository.update(updated);

      final all = await repository.getAll();
      expect(all, hasLength(1)); // тот же id — не дубликат
      expect(all.first.title, 'Встреча (перенесена)');
      expect(all.first.startMinutes, 11 * 60);
    });

    test('удаление события', () async {
      await repository.add(_event());
      await repository.delete('e1');
      expect(await repository.getAll(), isEmpty);
    });

    test('getForDate фильтрует по дате', () async {
      await repository.add(_event(id: 'a', date: DateTime(2026, 1, 15)));
      await repository.add(_event(id: 'b', date: DateTime(2026, 1, 16)));

      final forDay1 = await repository.getForDate(DateTime(2026, 1, 15));
      expect(forDay1.map((e) => e.id), ['a']);
    });

    test('события сортируются по дате и времени начала', () async {
      await repository.add(_event(id: 'late', date: DateTime(2026, 1, 15), startMinutes: 18 * 60));
      await repository.add(_event(id: 'early', date: DateTime(2026, 1, 15), startMinutes: 8 * 60));

      final all = await repository.getAll();
      expect(all.map((e) => e.id), ['early', 'late']);
    });
  });

  group('ScheduleDaySummary', () {
    test('считает занятое и свободное время', () {
      final events = [
        _event(id: 'a', startMinutes: 9 * 60, endMinutes: 10 * 60), // 60 мин
        _event(id: 'b', startMinutes: 14 * 60, endMinutes: 15 * 60 + 30), // 90 мин
      ];
      final summary = ScheduleDaySummary.fromEvents(events);

      expect(summary.totalBusy, const Duration(minutes: 150));
      expect(summary.totalFree, const Duration(minutes: 1440 - 150));
    });

    test('без событий — всё время свободно', () {
      final summary = ScheduleDaySummary.fromEvents(const []);
      expect(summary.totalBusy, Duration.zero);
      expect(summary.totalFree, const Duration(hours: 24));
    });
  });

  group('ScheduleSearchProvider', () {
    late _FakeModuleStorage storage;
    late ScheduleRepository repository;
    late ScheduleSearchProvider provider;

    setUp(() async {
      storage = _FakeModuleStorage();
      repository = ScheduleRepository(storage);
      provider = ScheduleSearchProvider(repository);
      await repository.add(_event(
        title: 'Встреча с клиентом',
        category: 'Работа',
        note: 'Обсудить контракт',
      ));
    });

    test('находит по названию', () async {
      final results = await provider.search('клиент');
      expect(results, hasLength(1));
    });

    test('находит по категории', () async {
      final results = await provider.search('работа');
      expect(results, hasLength(1));
    });

    test('находит по заметке', () async {
      final results = await provider.search('контракт');
      expect(results, hasLength(1));
    });

    test('не находит по нерелевантному запросу', () async {
      final results = await provider.search('отпуск');
      expect(results, isEmpty);
    });
  });

  group('Персистентность и жизненный цикл модуля', () {
    test('сохранение после "перезапуска" — тот же storage, новый репозиторий', () async {
      final storage = _FakeModuleStorage();
      await ScheduleRepository(storage).add(_event());

      // "Перезапуск": новый объект репозитория поверх ТОГО ЖЕ
      // хранилища — как это происходит в реальном приложении между
      // запусками (ModuleStorageIsar читает те же строки Isar).
      final reloaded = await ScheduleRepository(storage).getAll();
      expect(reloaded, hasLength(1));
      expect(reloaded.first.title, 'Встреча');
    });

    test('включение/отключение модуля не теряет данные', () async {
      ModuleRegistry.clear();
      final storage = _FakeModuleStorage();
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => storage,
      );
      ModuleRegistry.register(ScheduleModule());
      addTearDown(ModuleRegistry.clear);

      await manager.install('schedule');
      await manager.enable('schedule');

      final api = manager.apiFor('schedule');
      await ScheduleRepository(api.storage).add(_event(title: 'Не потеряется'));

      await manager.disable('schedule');
      expect(manager.stateOf('schedule'), ModuleState.disabled);

      await manager.enable('schedule');
      expect(manager.stateOf('schedule'), ModuleState.enabled);

      // Данные читаются через тот же storage (fake, но моделирует то,
      // что реальный ModuleStorageIsar не трогает Isar при enable/disable
      // — их стирает только uninstall, через ModuleStatePersistence, Этап 9).
      final events = await ScheduleRepository(storage).getAll();
      expect(events, hasLength(1));
      expect(events.first.title, 'Не потеряется');
    });
  });
}
