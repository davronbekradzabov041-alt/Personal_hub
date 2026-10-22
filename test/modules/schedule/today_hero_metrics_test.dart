/// Вёрстка трёх карточек статистики на «Главной» (Этап 11).
///
/// Было `Wrap`: на узком экране карточки переносились и имели разную
/// ширину. Требование — один горизонтальный `Row`, равные `Expanded`,
/// равная высота, зазор 10 dp, центрированный текст, перенос без
/// обрезки и отсутствие `RenderFlex overflow`.
library today_hero_metrics_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/design/design_system.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/ui/home/today_hero.dart';

ScheduleEvent _event(String id, int startMinutes, int durationMinutes) {
  final base = DateTime.now().copyWith(
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
  return ScheduleEvent(
    id: id,
    title: 'Событие $id',
    priority: EventPriority.medium,
    date: base,
    startMinutes: startMinutes,
    endMinutes: startMinutes + durationMinutes,
    status: EventStatus.planned,
    note: '',
  );
}

ScheduleDaySummary _summary(List<ScheduleEvent> events) =>
    ScheduleDaySummary.fromEvents(events);

TodayHero _hero(List<ScheduleEvent> events) => TodayHero(
      events: events,
      daySummary: _summary(events),
      onNavigateToSchedule: () {},
    );

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: child),
      );

  group('Метрики дня на «Главной»', () {
    testWidgets('все три карточки в одном Row с равной шириной',
        (tester) async {
      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      await tester.pumpWidget(wrap(ListView(children: [_hero(events)])));
      await tester.pumpAndSettle();

      expect(find.text('Занято'), findsOneWidget);
      expect(find.text('Свободно'), findsOneWidget);
      expect(find.text('Событий'), findsOneWidget);

      final metricRow = find.ancestor(
        of: find.text('Занято'),
        matching: find.byType(Row),
      );

      final row = tester.widget<Row>(metricRow.first);
      expect(row.children.length, 5,
          reason: 'карточка + зазор + карточка + зазор + карточка');
      expect(
        row.children.whereType<Expanded>().length,
        3,
        reason: 'каждая метрика в Expanded — ширину делят поровну',
      );
      expect(
        row.children.whereType<SizedBox>().length,
        2,
        reason: 'два зазора по 10 dp между тремя карточками',
      );
    });

    testWidgets('карточки равной ширины и равной высоты', (tester) async {
      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      await tester.pumpWidget(wrap(ListView(children: [_hero(events)])));
      await tester.pumpAndSettle();

      final rowFinder = find
          .ancestor(of: find.text('Занято'), matching: find.byType(Row))
          .first;
      final expanded = find.descendant(
        of: rowFinder,
        matching: find.byType(Expanded),
      );
      expect(expanded, findsNWidgets(3));

      final sizes = <Size>[];
      for (final element in expanded.evaluate()) {
        final box = element.renderObject as RenderBox;
        sizes.add(box.size);
      }

      expect(sizes[0].width, closeTo(sizes[1].width, 0.5),
          reason: 'Expanded делит ширину поровну');
      expect(sizes[1].width, closeTo(sizes[2].width, 0.5));
      expect(sizes[0].height, closeTo(sizes[1].height, 0.5),
          reason: 'stretch выравнивает высоту');
      expect(sizes[1].height, closeTo(sizes[2].height, 0.5));
    });

    testWidgets('на узком экране нет RenderFlex overflow', (tester) async {
      // 320 dp — минимальная ширина, на которой раньше был overflow.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      await tester.pumpWidget(wrap(ListView(children: [_hero(events)])));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'overflow/некорректные constraints — это исключение');
      expect(find.text('Занято'), findsOneWidget);
      expect(find.text('Свободно'), findsOneWidget);
      expect(find.text('Событий'), findsOneWidget);
    });

    testWidgets('текст центрирован и переносится без обрезки',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      await tester.pumpWidget(wrap(ListView(children: [_hero(events)])));
      await tester.pumpAndSettle();

      // Значение сверзу полужирным (headlineSmall), подпись снизу
      // (labelMedium); обе одной строкой.
      for (final label in ['Занято', 'Свободно', 'Событий']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.textAlign, TextAlign.center);
      }
      // Занято = 90 + 30 мин = 2 ч (считает репозиторий, не UI).
      final valueText = tester.widget<Text>(find.text('2 ч'));
      expect(valueText.style?.fontWeight, FontWeight.bold,
          reason: 'значение вынесено наверх полужирным');
      expect(valueText.maxLines, 1);
    });

    // --- Регрессия Stage 11 -------------------------------------------------
    //
    // Подписи метрик исчезали с экрана «Главной»: `_MetricChip` передавал
    // в `AppComponents.featureCard` собственный `Padding(16)` В ДОБАВОК к
    // тем 20, что карточка и так кладет сама. Итого 52 dp пустоты вокруг
    // двух строк — на карточке шириной ~100 dp под текст оставалось ~28 dp,
    // и «Занято»/«Свободно»/«Событий» схлопывались в ширину 0.
    //
    // Поиск по тексту такое не ловит: виджет существует, просто нулевой
    // ширины. Поэтому проверяется фактическая ширина render-объекта.
    testWidgets('подписи и значения действительно видимы на телефоне',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      await tester.pumpWidget(wrap(ListView(children: [_hero(events)])));
      await tester.pumpAndSettle();

      for (final label in ['Занято', 'Свободно', 'Событий']) {
        final box = tester.renderObject<RenderBox>(find.text(label));
        expect(box.size.width, greaterThan(0),
            reason: '"$label" имеет нулевую ширину — текст невидим');
      }
      for (final value in ['2 ч', '22 ч', '2']) {
        final box = tester.renderObject<RenderBox>(find.text(value));
        expect(box.size.width, greaterThan(0),
            reason: '"$value" имеет нулевую ширину — текст невидим');
      }
    });

    testWidgets('подписи видимы при масштабе текста 1.3', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final events = <ScheduleEvent>[
        _event('1', 9 * 60, 90),
        _event('2', 12 * 60, 30),
      ];

      // Помещаем hero в MediaQuery с масштабом 1.3, как при системной
      // настройке крупного шрифта.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: ListView(children: [_hero(events)]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'нет overflow');
      for (final label in ['Занято', 'Свободно', 'Событий']) {
        final box = tester.renderObject<RenderBox>(find.text(label));
        expect(box.size.width, greaterThan(0),
            reason: '"$label" невидим при масштабе текста 1.3');
      }
    });
  });
}
