import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../models/schedule_event.dart';
import '../category_visuals.dart';

/// Timeline Strip v1 — горизонтальная шкала дня.
///
/// Показывает:
/// - прошедшие события (серые);
/// - текущее время (маркер);
/// - ближайшие события (активные);
/// - свободные интервалы (прозрачные).
class TimelineStrip extends StatelessWidget {
  const TimelineStrip({
    super.key,
    required this.events,
    required this.currentMinutes,
    required this.onEventTap,
    this.categoryResolver,
  });

  final List<ScheduleEvent> events;
  final int currentMinutes;
  final void Function(ScheduleEvent event) onEventTap;

  /// Правило разрешения категории; null — блоки красятся по приоритету.
  final CategoryResolver? categoryResolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolver = categoryResolver;

    // День: 0:00 - 24:00 = 1440 минут
    const dayStart = 0;
    const dayEnd = 1440;

    // Сортируем события по времени начала
    final sortedEvents = [...events]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    // Строим сегменты: свободный + событие + свободный + ...
    final segments = _buildSegments(sortedEvents, dayStart, dayEnd);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = constraints.maxWidth;

        return Container(
          height: 56,
          padding: EdgeInsets.symmetric(vertical: AppSpacing.space2),
          child: CustomPaint(
            painter: _TimelinePainter(
              segments: segments,
              currentMinutes: currentMinutes,
              dayStart: dayStart,
              dayEnd: dayEnd,
              theme: theme,
              isDark: isDark,
              colorOf: (event) => _eventColor(event, resolver, theme),
            ),
            child: Stack(
              children: segments.map((segment) {
                if (segment.type == _SegmentType.event) {
                  return _buildEventOverlay(context, segment, stripWidth);
                }
                return const SizedBox.shrink();
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  /// Цвет блока события: категория, если она есть, иначе приоритет.
  ///
  /// Категория важнее приоритета на этой шкале: полоса показывает, чем
  /// занят день, и ответ «работа» полезнее ответа «средний». События без
  /// категории сохраняют прежнюю раскраску по приоритету, поэтому
  /// шкала не меняет вид у тех данных, где категорий ещё нет.
  Color _eventColor(
    ScheduleEvent event,
    CategoryResolver? resolver,
    ThemeData theme,
  ) {
    final category = resolver?.resolve(event);
    if (category != null && category.hasAppearance) {
      return Color(category.colorValue!);
    }

    switch (event.priority) {
      case EventPriority.high:
        return theme.colorScheme.error;
      case EventPriority.low:
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.primary;
    }
  }

  Widget _buildEventOverlay(BuildContext context, _TimelineSegment segment, double stripWidth) {
    final event = segment.event!;
    final theme = Theme.of(context);
    final left = _minutesToFraction(segment.start) * stripWidth;
    final width = ((segment.end - segment.start) / 1440) * stripWidth;

    // Минимальная видимая ширина для коротких событий
    const minVisibleWidth = 48.0;

    return Positioned(
      left: left.clamp(0.0, stripWidth - minVisibleWidth),
      top: 8,
      bottom: 8,
      width: width.clamp(minVisibleWidth, stripWidth),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onEventTap(event),
          borderRadius: BorderRadius.circular(AppRadiiValues.sm),
child: Container(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: _eventColor(event, categoryResolver, theme).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppRadiiValues.sm),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ScheduleEvent.formatMinutes(event.startMinutes)}–${ScheduleEvent.formatMinutes(event.endMinutes)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_TimelineSegment> _buildSegments(
    List<ScheduleEvent> events,
    int dayStart,
    int dayEnd,
  ) {
    final segments = <_TimelineSegment>[];
    var cursor = dayStart;

    for (final event in events) {
      // Свободный интервал до события
      if (event.startMinutes > cursor) {
        segments.add(_TimelineSegment(
          type: _SegmentType.free,
          start: cursor,
          end: event.startMinutes,
        ));
      }
      // Событие
      segments.add(_TimelineSegment(
        type: _SegmentType.event,
        start: event.startMinutes,
        end: event.endMinutes,
        event: event,
      ));
      cursor = event.endMinutes;
    }

    // Хвост дня после последнего события
    if (cursor < dayEnd) {
      segments.add(_TimelineSegment(
        type: _SegmentType.free,
        start: cursor,
        end: dayEnd,
      ));
    }

    // Если событий нет — весь день свободен
    if (events.isEmpty) {
      segments.add(_TimelineSegment(
        type: _SegmentType.free,
        start: dayStart,
        end: dayEnd,
      ));
    }

    return segments;
  }

  double _minutesToFraction(int minutes) {
    return (minutes / 1440).clamp(0.0, 1.0);
  }
}

enum _SegmentType { free, event }

class _TimelineSegment {
  const _TimelineSegment({
    required this.type,
    required this.start,
    required this.end,
    this.event,
  });

  final _SegmentType type;
  final int start;
  final int end;
  final ScheduleEvent? event;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TimelineSegment &&
        other.type == type &&
        other.start == start &&
        other.end == end &&
        other.event == event;
  }

  @override
  int get hashCode => Object.hash(type, start, end, event);
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.segments,
    required this.currentMinutes,
    required this.dayStart,
    required this.dayEnd,
    required this.theme,
    required this.isDark,
    required this.colorOf,
  });

  final List<_TimelineSegment> segments;
  final int currentMinutes;
  final int dayStart;
  final int dayEnd;
  final ThemeData theme;
  final bool isDark;

  /// Цвет события. Передаётся функцией, а не готовым цветом: painter
  /// перерисовывается и при смене событий, и при смене справочника
  /// категорий, и правило разрешения живёт в виджете, а не дублируется
  /// здесь.
  final Color Function(ScheduleEvent event) colorOf;

  /// Цвета блоков, посчитанные один раз при создании painter'а.
  ///
  /// Нужны для [shouldRepaint]: переименование категории меняет цвета,
  /// но НЕ меняет [segments], и сравнение только по сегментам оставило
  /// бы на экране старые цвета до следующего обновления шкалы.
  late final List<Color> _segmentColors = <Color>[
    for (final segment in segments)
      if (segment.event != null) colorOf(segment.event!) else Colors.transparent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 4;

    // Фон шкалы (весь день)
    final bgRect = Rect.fromLTWH(0, size.height / 2 - 2, size.width, 4);
    paint.color = theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.2);
    canvas.drawRect(bgRect, paint);

    // Сегменты
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final left = _minutesToX(segment.start, size.width);
      final right = _minutesToX(segment.end, size.width);

      if (segment.type == _SegmentType.free) {
        // Свободный интервал — тонкая пунктирная линия
        paint.color = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
        paint.strokeWidth = 2;
        paint.style = PaintingStyle.stroke;
        _drawDashedLine(canvas, left, right, size.height / 2, paint);
      } else {
        // Событие — яркая линия
        paint.color = _segmentColors[index];
        paint.strokeWidth = 6;
        paint.style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(left, size.height / 2),
          Offset(right, size.height / 2),
          paint,
        );
      }
    }

    // Текущее время — вертикальная линия (зажата в пределах ширины)
    final nowX = _minutesToX(currentMinutes, size.width).clamp(0.0, size.width);
    paint.color = theme.colorScheme.error;
    paint.strokeWidth = 2;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      paint,
    );

    // Круг текущего времени
    final circlePaint = Paint()..color = theme.colorScheme.error;
    canvas.drawCircle(Offset(nowX, size.height / 2), 6, circlePaint);
    canvas.drawCircle(Offset(nowX, size.height / 2), 3, Paint()..color = theme.colorScheme.onError);
  }

  double _minutesToX(int minutes, double width) {
    return ((minutes / 1440) * width).clamp(0.0, width);
  }

  void _drawDashedLine(Canvas canvas, double startX, double endX, double y, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    double x = startX;
    while (x < endX) {
      final nextX = (x + dashLength).clamp(startX, endX);
      canvas.drawLine(Offset(x, y), Offset(nextX, y), paint);
      x += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    if (oldDelegate.currentMinutes != currentMinutes) return true;
    if (oldDelegate.segments.length != segments.length) return true;
    // Переименование или перекраска категории меняют цвета при тех же
    // самых событиях — иначе шкала осталась бы со старыми цветами.
    for (var index = 0; index < _segmentColors.length; index++) {
      if (oldDelegate._segmentColors[index] != _segmentColors[index]) return true;
    }
    for (var index = 0; index < segments.length; index++) {
      if (oldDelegate.segments[index] != segments[index]) return true;
    }
    return false;
  }
}