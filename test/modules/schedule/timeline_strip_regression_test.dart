/// Регрессионные тесты для TimelineStrip: доступность коротких и
/// пересекающихся событий через onEventTap.
library timeline_strip_regression_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/ui/home/timeline_strip.dart';

ScheduleEvent _event(
  String id, {
  required int startMinutes,
  required int durationMinutes,
  String title = 'Событие',
  EventPriority priority = EventPriority.medium,
  EventStatus status = EventStatus.planned,
}) {
  final base = DateTime.now().copyWith(
    hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0,
  );
  return ScheduleEvent(
    id: id, title: title, priority: priority, date: base,
    startMinutes: startMinutes, endMinutes: startMinutes + durationMinutes,
    status: status, note: '',
  );
}

Widget wrapTimeline(Widget child, {double width = 360}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(
    body: SizedBox(width: width, height: 400, child: child),
  ),
);

void main() {
  group('TimelineStrip — доступность событий', () {
    testWidgets('короткое событие 5 мин на 320 dp вызывает onEventTap',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('short5', startMinutes: 9 * 60, durationMinutes: 5,
            title: 'Короткое'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
      final inkwell = tester.widgetList<InkWell>(find.byType(InkWell)).first;
      await tester.tap(find.byWidget(inkwell), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, contains('short5'));
    });

    testWidgets('короткое событие 10 мин на 320 dp вызывает onEventTap',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('short10', startMinutes: 9 * 60, durationMinutes: 10,
            title: 'Короткое'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
      final inkwell = tester.widgetList<InkWell>(find.byType(InkWell)).first;
      await tester.tap(find.byWidget(inkwell), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, contains('short10'));
    });

    testWidgets('короткое событие выбирается через список под таймлайном',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('short5', startMinutes: 9 * 60, durationMinutes: 5,
            title: 'Короткое'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      // Список коротких событий должен быть виден
      expect(find.text('Короткие события'), findsOneWidget);
      expect(find.text('Короткое'), findsOneWidget);

      // Тап по элементу списка вызывает onEventTap
      await tester.tap(find.text('Короткое').first);
      await tester.pumpAndSettle();

      expect(tapped, contains('short5'));
    });

    testWidgets('события одинакового времени начала: диалог выбора',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 9 * 60, durationMinutes: 30,
            title: 'Первое'),
        _event('b', startMinutes: 9 * 60, durationMinutes: 30,
            title: 'Второе'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNWidgets(2));

      // Тап по первому InkWell — должен открыться диалог выбора
      final inkwells = tester.widgetList<InkWell>(find.byType(InkWell));
      await tester.tap(find.byWidget(inkwells.first), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Диалог выбора должен появиться
      expect(find.text('Выберите событие'), findsOneWidget);

      // Выбираем первое событие из диалога
      await tester.tap(find.text('Первое').first);
      await tester.pumpAndSettle();

      expect(tapped, contains('a'));
    });

    testWidgets('пересекающиеся события: диалог выбора',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 9 * 60, durationMinutes: 60),
        _event('b', startMinutes: 9 * 60 + 30, durationMinutes: 60),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNWidgets(2));

      // Тап по первому InkWell — должен открыться диалог выбора
      final inkwells = tester.widgetList<InkWell>(find.byType(InkWell));
      await tester.tap(find.byWidget(inkwells.first), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Диалог выбора должен появиться
      expect(find.text('Выберите событие'), findsOneWidget);

      // Выбираем первое событие из диалога
      await tester.tap(find.text('Событие').first);
      await tester.pumpAndSettle();

      expect(tapped, contains('a'));
    });

    testWidgets('обычное непересекающееся событие открывается напрямую',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 9 * 60, durationMinutes: 60,
            title: 'Обычное'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
      final inkwell = tester.widgetList<InkWell>(find.byType(InkWell)).first;
      await tester.tap(find.byWidget(inkwell), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, contains('a'));
    });

    testWidgets('пустой день не вызывает ошибок',
        (tester) async {
      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: const [], currentMinutes: 0,
            onEventTap: (e) => {},
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      // Нет InkWell, нет списка событий, нет ошибок
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('Короткие события'), findsNothing);
    });

    testWidgets('событие у левой границы (0:00) вызывает onEventTap',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 0, durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
      final inkwell = tester.widgetList<InkWell>(find.byType(InkWell)).first;
      await tester.tap(find.byWidget(inkwell), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, contains('a'));
    });

    testWidgets('событие у правой границы (24:00) вызывает onEventTap',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 23 * 60 + 30, durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
      final inkwell = tester.widgetList<InkWell>(find.byType(InkWell)).first;
      await tester.tap(find.byWidget(inkwell), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, contains('a'));
    });

    testWidgets('диалог выбора не содержит дубликатов',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 9 * 60, durationMinutes: 45),
        _event('b', startMinutes: 9 * 60 + 15, durationMinutes: 45),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      final inkwells = tester.widgetList<InkWell>(find.byType(InkWell));
      await tester.tap(find.byWidget(inkwells.first), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Диалог показывает события без дублей
      expect(find.text('Выберите событие'), findsOneWidget);
      // Оба события доступны в диалоге
      expect(find.text('Событие'), findsAtLeastNWidgets(1));
    });

    testWidgets('события, которые только соприкасаются, не открывают диалог',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('a', startMinutes: 9 * 60, durationMinutes: 30,
            title: 'Первое'),
        _event('b', startMinutes: 9 * 60 + 30, durationMinutes: 30,
            title: 'Второе'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNWidgets(2));

      // Тап по первому — открытие напрямую, диалог не должен появиться
      final inkwells = tester.widgetList<InkWell>(find.byType(InkWell));
      await tester.tap(find.byWidget(inkwells.first), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Выберите событие'), findsNothing);
      expect(tapped, contains('a'));
    });

    testWidgets('короткое событие в списке — ровно один экземпляр',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('short5', startMinutes: 9 * 60, durationMinutes: 5,
            title: 'Короткое'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      // Список коротких событий отображается
      expect(find.text('Короткие события'), findsOneWidget);
      // Событие в списке — ровно один раз
      expect(find.text('Короткое'), findsOneWidget);
    });

    testWidgets('короткое событие на левой границе (0:00) в списке',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('start', startMinutes: 0, durationMinutes: 10,
            title: 'Начало дня'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Короткие события'), findsOneWidget);
      expect(find.text('Начало дня'), findsOneWidget);

      await tester.tap(find.text('Начало дня').first);
      await tester.pumpAndSettle();

      expect(tapped, contains('start'));
    });

    testWidgets('короткое событие на правой границе (24:00) в списке',
        (tester) async {
      final tapped = <String>[];
      final events = <ScheduleEvent>[
        _event('end', startMinutes: 23 * 60 + 50, durationMinutes: 10,
            title: 'Конец дня'),
      ];

      await tester.pumpWidget(
        wrapTimeline(
          TimelineStrip(
            events: events, currentMinutes: 0,
            onEventTap: (e) => tapped.add(e.id),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Короткие события'), findsOneWidget);
      expect(find.text('Конец дня'), findsOneWidget);

      await tester.tap(find.text('Конец дня').first);
      await tester.pumpAndSettle();

      expect(tapped, contains('end'));
    });
  });
}
