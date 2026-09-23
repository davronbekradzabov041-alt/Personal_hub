/// Приоритет события.
enum EventPriority {
  low,
  medium,
  high;

  String get label {
    switch (this) {
      case EventPriority.low:
        return 'Низкий';
      case EventPriority.medium:
        return 'Средний';
      case EventPriority.high:
        return 'Высокий';
    }
  }
}

/// Статус события.
enum EventStatus {
  planned,
  done,
  skipped;

  String get label {
    switch (this) {
      case EventStatus.planned:
        return 'Запланировано';
      case EventStatus.done:
        return 'Выполнено';
      case EventStatus.skipped:
        return 'Пропущено';
    }
  }
}

/// Событие расписания.
///
/// Дата хранится без времени (только год/месяц/день) — время начала
/// и окончания хранятся отдельно, минутами от полуночи, а не как
/// DateTime с датой: так проще сериализовать и сравнивать без
/// путаницы с часовыми поясами (события — локальные, "в этот день").
class ScheduleEvent {
  final String id;
  final String title;
  final String category;
  final EventPriority priority;

  /// Только дата — время дня всегда 00:00 (год/месяц/день сравниваются
  /// через [dateKey], а не через сам DateTime, из-за возможной
  /// разницы во времени суток при создании объекта).
  final DateTime date;

  /// Минут от полуночи, 0..1439.
  final int startMinutes;
  final int endMinutes;

  final EventStatus status;
  final String note;

  const ScheduleEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.status,
    this.note = '',
  });

  Duration get duration => Duration(minutes: endMinutes - startMinutes);

  /// Ключ дня для сравнения/группировки — 'YYYY-MM-DD'.
  String get dateKey => formatDateKey(date);

  static String formatDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  ScheduleEvent copyWith({
    String? title,
    String? category,
    EventPriority? priority,
    DateTime? date,
    int? startMinutes,
    int? endMinutes,
    EventStatus? status,
    String? note,
  }) {
    return ScheduleEvent(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      date: date ?? this.date,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'priority': priority.name,
        'date': dateKey,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'status': status.name,
        'note': note,
      };

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) {
    final dateParts = (json['date'] as String).split('-');
    return ScheduleEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      priority: EventPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => EventPriority.medium,
      ),
      date: DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      ),
      startMinutes: json['startMinutes'] as int,
      endMinutes: json['endMinutes'] as int,
      status: EventStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => EventStatus.planned,
      ),
      note: json['note'] as String? ?? '',
    );
  }
}
