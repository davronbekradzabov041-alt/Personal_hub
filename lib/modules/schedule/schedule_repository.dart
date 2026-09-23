import 'dart:convert';

import '../../core/modules/module_storage.dart';
import 'models/schedule_event.dart';

/// Хранилище событий Schedule.
///
/// Поверх уже существующего ModuleStorage (Этап 9) — того же самого
/// generic key-value контракта, которым уже пользуется ExampleModule
/// для своей заметки. Отдельной типизированной Isar-коллекции под
/// Schedule НЕТ и не создаётся — прямое требование Этапа 14, и оно же
/// прямое следствие архитектуры, заложенной аудитом Этапа 6.
///
/// Каждое событие — одна запись `event:<id>` со значением-JSON.
/// Список id хранится не отдельно — просто фильтруются все ключи
/// хранилища по префиксу `event:` (ModuleStorage.keys() уже
/// возвращает только ключи ЭТОГО модуля, см. Этап 9/10).
class ScheduleRepository {
  ScheduleRepository(this._storage);

  final ModuleStorage _storage;

  static const _keyPrefix = 'event:';

  Future<List<ScheduleEvent>> getAll() async {
    final keys = await _storage.keys();
    final eventKeys = keys.where((k) => k.startsWith(_keyPrefix));

    final events = <ScheduleEvent>[];
    for (final key in eventKeys) {
      final raw = await _storage.getString(key);
      if (raw == null) continue;
      events.add(ScheduleEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }

    events.sort((a, b) {
      final byDate = a.dateKey.compareTo(b.dateKey);
      if (byDate != 0) return byDate;
      return a.startMinutes.compareTo(b.startMinutes);
    });
    return events;
  }

  Future<List<ScheduleEvent>> getForDate(DateTime date) async {
    final key = ScheduleEvent.formatDateKey(date);
    final all = await getAll();
    return all.where((e) => e.dateKey == key).toList();
  }

  Future<void> add(ScheduleEvent event) async {
    await _storage.setString(_keyPrefix + event.id, jsonEncode(event.toJson()));
  }

  Future<void> update(ScheduleEvent event) async {
    await _storage.setString(_keyPrefix + event.id, jsonEncode(event.toJson()));
  }

  Future<void> delete(String id) async {
    await _storage.remove(_keyPrefix + id);
  }
}

/// Сводка за день — суммарная занятость и свободное время.
///
/// Свободное время считается от суток (24 ч = 1440 мин) минус сумма
/// длительностей событий этого дня. Намеренно не учитывает пересечения
/// событий между собой (если два события наложились по времени,
/// свободное время может быть недооценено) — совмещение интервалов и
/// обнаружение конфликтов не входит в базовую версию Этапа 14
/// ("без автоматического распределения нагрузки").
class ScheduleDaySummary {
  final Duration totalBusy;
  final Duration totalFree;

  const ScheduleDaySummary({required this.totalBusy, required this.totalFree});

  factory ScheduleDaySummary.fromEvents(List<ScheduleEvent> events) {
    final busyMinutes = events.fold<int>(0, (sum, e) => sum + e.duration.inMinutes);
    final clampedBusy = busyMinutes.clamp(0, 1440);
    return ScheduleDaySummary(
      totalBusy: Duration(minutes: clampedBusy),
      totalFree: Duration(minutes: 1440 - clampedBusy),
    );
  }
}
