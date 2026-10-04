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
///
/// ## Две категории: `categoryId` и `category`
///
/// У события ДВА поля про категорию, и это не дублирование, а
/// совместимость на время перехода:
///
/// * [categoryId] — **авторитетное** поле: ссылка на категорию из
///   ScheduleCategoryRepository по её id. Nullable, и `null` означает
///   «событие без категории» — то же состояние, с которого начинается
///   любое новое событие. Отдельной системной категории «Без категории»
///   нет и не будет: отсутствие категории выражается её отсутствием.
/// * [category] — **устаревшее** название категории строкой, которое
///   пользователь раньше вводил вручную. Источником правды не является
///   и источником правды не станет; оно остаётся, чтобы (а) старые
///   backup'ы читались как раньше, и (б) сборка, где [categoryId] ещё
///   не появилась, не падала на отсутствующем ключе.
///
/// Поэтому в [toJson] ключ `category` пишется ВСЕГДА, а `categoryId`
/// — только когда он есть. При чтении приоритет у [categoryId], и
/// только если его нет — берётся [category]. Так запись, сделанная
/// любой версией приложения, читается любой версией: старый код видит
/// привычную строку, новый — ссылку.
///
/// Перенос старых названий в настоящие категории — отдельная задача
/// (Этап 7.2) и здесь НЕ выполняется: события, сохранённые до
/// появления категорий, просто читаются с `categoryId == null`.
class ScheduleEvent {
  final String id;
  final String title;

  /// Устаревшее название категории строкой — запасное значение для
  /// показа, а не ссылка. Не авторитетно, см. описание класса.
  ///
  /// Пустая строка означает «без категории» — так было и до появления
  /// [categoryId], поэтому прежние данные не требуют переписывания.
  final String category;

  /// Ссылка на категорию по id; `null` — событие без категории.
  ///
  /// Авторитетное поле. Неизвестный или отсутствующий в хранилище id
  /// читается как «без категории» (см. [fromJson]) — висячих ссылок
  /// не бывает, а такая трактовка совпадает с удалением категории,
  /// которое переводит её события в `null`.
  final String? categoryId;

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
    required this.priority,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.status,
    this.category = '',
    this.categoryId,
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

  /// Маркер «параметр не передан» для [copyWith].
  ///
  /// Отдельный объект вместо `null`, потому что `null` для [categoryId]
  /// — это РЕАЛЬНОЕ ЗНАЧЕНИЕ «без категории», и обычный `?? this.x`
  /// не смог бы отличить «оставить как было» от «очистить».
  static const Object _notProvided = Object();

  /// Копия события с изменёнными полями.
  ///
  /// [categoryId] намеренно имеет тип `Object?`, а не `String?`:
  ///   * `copyWith()`               — оставить как было;
  ///   * `copyWith(categoryId: '7')` — задать категорию;
  ///   * `copyWith(categoryId: null)` — снять категорию.
  ///
  /// Плата за это — потеря проверки типов на аргументе: значение не
  /// `String`/`null` уронит событие приведением. Это ровно тот случай,
  /// где `String? categoryId = _notProvided` невозможен, а отдельный
  /// `clearCategoryId` выглядел бы как обходной путь вокруг
  /// неудобства, которого на самом деле нет.
  ScheduleEvent copyWith({
    String? title,
    String? category,
    Object? categoryId = _notProvided,
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
      categoryId: identical(categoryId, _notProvided)
          ? this.categoryId
          : categoryId as String?,
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
        // category пишется ВСЕГДА: это то, что читает сборка без
        // categoryId, и пустая строка здесь означает то же, что
        // отсутствие categoryId, — «без категории».
        'category': category,
        // categoryId — только когда он есть. Отсутствующий ключ и явный
        // null читаются одинаково, поэтому различать их незачем, а
        // незаписываемые null'ы лишь раздувают хранилище.
        if (categoryId != null) 'categoryId': categoryId,
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
      // Раньше здесь стояло `json['category'] as String` — жёсткое
      // приведение, из-за которого ОДНА запись без этого ключа роняла
      // чтение всех событий модуля целиком (ScheduleRepository.getAll
      // не изолирует одну сбойную запись). Теперь отсутствие ключа —
      // это «без категории», а не ошибка.
      category: json['category'] as String? ?? '',
      categoryId: readCategoryId(json['categoryId']),
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

  /// Разбирает сохранённую ссылку на категорию.
  ///
  /// Возвращает `null` для всего, что не является непустой строкой:
  /// отсутствующего ключа, явного null, пустой строки и значения
  /// другого типа из испорченного хранилища. Все эти случаи означают
  /// одно и то же — «категории нет» — и ни один из них не должен
  /// приводить к падению чтения. Ссылка на несуществующую категорию
  /// разрешается в «без категории» позже, на уровне репозитория и UI,
  /// где список категорий известен.
  static String? readCategoryId(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
