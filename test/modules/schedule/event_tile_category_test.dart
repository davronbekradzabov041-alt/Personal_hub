import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/modules/schedule/models/category.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/ui/category_visuals.dart';
import 'package:personal_hub/modules/schedule/ui/event_tile.dart';

/// Плитка события показывает разрешённую категорию.
///
/// Проверяется виджет, а не сценарий целиком: правило «что показывать»
/// уже проверено в category_visuals_test, здесь важно, что оно дошло до
/// подписи и до иконки, а не потерялось по дороге.
void main() {
  ScheduleEvent event({String? categoryId, String legacy = ''}) {
    return ScheduleEvent(
      id: 'e1',
      title: 'Планёрка',
      category: legacy,
      categoryId: categoryId,
      priority: EventPriority.medium,
      date: DateTime(2026, 1, 15),
      startMinutes: 9 * 60 + 30,
      endMinutes: 10 * 60,
      status: EventStatus.planned,
    );
  }

  final work = Category(
    id: '7',
    name: 'Работа',
    colorValue: 0xFFD97706,
    iconKey: 'work',
    order: 0,
  );

  Widget tile({ScheduleEvent? tileEvent, ResolvedCategory? category}) =>
      MaterialApp(
        home: Scaffold(
          body: EventTile(
            event: tileEvent ?? event(),
            category: category,
            onTap: () {},
          ),
        ),
      );

  testWidgets('подпись содержит имя категории и время', (tester) async {
    await tester.pumpWidget(
      tile(category: ResolvedCategory.ofCategory(work)),
    );

    expect(find.text('Планёрка'), findsOneWidget);
    final metadata = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .firstWhere((data) => data != null && data.contains('Работа'));
    expect(metadata, contains('09:30–10:00'));
    expect(metadata, contains('Работа'));
  });

  testWidgets('иконка категории рисуется её цветом', (tester) async {
    await tester.pumpWidget(
      tile(category: ResolvedCategory.ofCategory(work)),
    );

    final icon = tester.widget<Icon>(
      find.byIcon(categoryIcons['work']!),
    );
    expect(icon.color, const Color(0xFFD97706));
  });

  testWidgets('без категории подпись прямо говорит об этом', (tester) async {
    await tester.pumpWidget(
      tile(category: ResolvedCategory.none),
    );

    expect(find.textContaining('Без категории'), findsOneWidget);
    expect(find.textContaining(' · '), findsWidgets,
        reason: 'метаданные не должны слипаться из-за пустого сегмента');
  });

  testWidgets('без перечитанной категории подпись остаётся рабочей',
      (tester) async {
    // Вызывающий не перечитал справочник: плитка показывает время и
    // статус, а не устаревшую строку события (у неё другое правило).
    await tester.pumpWidget(tile());

    expect(find.text('Планёрка'), findsOneWidget);
    expect(find.textContaining('09:30–10:00'), findsOneWidget);
    expect(find.textContaining('Без категории'), findsNothing);
  });

  testWidgets('висячая ссылка показывает устаревшее имя', (tester) async {
    final resolved = const CategoryResolver(<String, Category>{}).resolve(
      _dangling(),
    );

    await tester.pumpWidget(
      tile(tileEvent: _dangling(), category: resolved),
    );

    expect(find.textContaining('Работа'), findsOneWidget);
  });

  testWidgets('нажатие вызывается один раз', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTile(
            event: event(categoryId: work.id),
            category: ResolvedCategory.ofCategory(work),
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Планёрка'));
    expect(taps, 1);
  });
}

ScheduleEvent _dangling() => ScheduleEvent(
      id: 'e1',
      title: 'Планёрка',
      category: 'Работа',
      categoryId: 'уже-нет',
      priority: EventPriority.medium,
      date: DateTime(2026, 1, 15),
      startMinutes: 9 * 60 + 30,
      endMinutes: 10 * 60,
      status: EventStatus.planned,
    );