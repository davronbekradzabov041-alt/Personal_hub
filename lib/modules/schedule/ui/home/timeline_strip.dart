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
/// - свободные интервалы (прозрачные);
/// - общий временной диапазон дня под полосой.
/// - компактный список коротких событий под полосой для надёжного выбора.
class TimelineStrip extends StatefulWidget {
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
  State<TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends State<TimelineStrip> {
  /// События, которые накладываются на заданное событие по времени.
  List<ScheduleEvent> _findOverlapping(ScheduleEvent event) {
    return widget.events.where((e) =>
        e.id != event.id &&
        e.startMinutes < event.endMinutes &&
        e.endMinutes > event.startMinutes,
    ).toList();
  }

  /// Обработка нажатия на событие: при пересечении показывает диалог выбора.
  void _handleEventTap(ScheduleEvent tappedEvent) {
    final overlapping = _findOverlapping(tappedEvent);
    if (overlapping.isEmpty) {
      widget.onEventTap(tappedEvent);
      return;
    }

    final candidates = <ScheduleEvent>[tappedEvent]..addAll(overlapping)
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    _showSelectionDialog(candidates);
  }

  void _showSelectionDialog(List<ScheduleEvent> candidates) {
    showDialog<ScheduleEvent>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выберите событие'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return ListTile(
                title: Text(
                  candidate.title.trim().isEmpty
                      ? 'Без названия'
                      : candidate.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${ScheduleEvent.formatMinutes(candidate.startMinutes)}–'
                  '${ScheduleEvent.formatMinutes(candidate.endMinutes)}',
                ),
                onTap: () {
                  Navigator.pop(dialogContext, candidate);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
        ],
      ),
    ).then((selected) {
      if (selected != null && mounted) {
        widget.onEventTap(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolver = widget.categoryResolver;

    // День: 0:00 - 24:00 = 1440 минут
    const dayStart = 0;
    const dayEnd = 1440;

    // Сортируем события по времени начала
    final sortedEvents = [...widget.events]..sort(
      (a, b) => a.startMinutes.compareTo(b.startMinutes),
    );

    // Строим сегменты: свободный + событие + свободный + ...
    final segments = _buildSegments(sortedEvents, dayStart, dayEnd);

    // Вычисляем общий диапазон событий для подписи под полосой
    final timeRangeLabel = _buildTimeRangeLabel(sortedEvents);

    // Короткие события для списка под таймлайном (до 15 мин)
    final shortEvents = sortedEvents.where(
      (e) => (e.endMinutes - e.startMinutes) <= 15,
    ).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = constraints.maxWidth;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Сама полоса таймлайна
            Container(
              height: 56,
              padding: EdgeInsets.symmetric(vertical: AppSpacing.space2),
              child: CustomPaint(
                painter: _TimelinePainter(
                  segments: segments,
                  currentMinutes: widget.currentMinutes,
                  dayStart: dayStart,
                  dayEnd: dayEnd,
                  theme: theme,
                  isDark: isDark,
                  colorOf: (event) => _eventColor(event, resolver, theme),
                ),
                child: Stack(
                  children: segments.map((segment) {
                    if (segment.type == _SegmentType.event) {
                      return _buildEventOverlay(
                        context, segment, stripWidth,
                      );
                    }
                    return const SizedBox.shrink();
                  }).toList(),
                ),
              ),
            ),
            // Подпись общего временного диапазона под полосой
            if (timeRangeLabel != null)
              Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.space2, left: 4, right: 4,
                ),
                child: Text(
                  timeRangeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // Компактный список коротких событий под таймлайном
            if (shortEvents.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.space2,
                  left: AppInsets.screen(context).left,
                  right: AppInsets.screen(context).right,
                  bottom: AppSpacing.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Короткие события',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...shortEvents.map((event) => _buildShortEventItem(
                      context, event, theme,
                    )),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildShortEventItem(
    BuildContext context,
    ScheduleEvent event,
    ThemeData theme,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 4,
        height: 40,
        decoration: BoxDecoration(
          color: _eventColor(event, widget.categoryResolver, theme)
              .withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: Text(
        event.title.trim().isEmpty ? 'Без названия' : event.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${ScheduleEvent.formatMinutes(event.startMinutes)}–'
        '${ScheduleEvent.formatMinutes(event.endMinutes)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => _handleEventTap(event),
    );
  }

  String? _buildTimeRangeLabel(List<ScheduleEvent> sortedEvents) {
    if (sortedEvents.isEmpty) return null;
    final firstStart = sortedEvents.first.startMinutes;
    final lastEnd = sortedEvents.last.endMinutes;
    return '${ScheduleEvent.formatMinutes(firstStart)}–'
        '${ScheduleEvent.formatMinutes(lastEnd)}';
  }

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

  Widget _buildEventOverlay(
    BuildContext context,
    _TimelineSegment segment,
    double stripWidth,
  ) {
    final event = segment.event!;
    final theme = Theme.of(context);
    final left = _minutesToFraction(segment.start) * stripWidth;
    final width = ((segment.end - segment.start) / 1440) * stripWidth;

    if (stripWidth <= 0 || width <= 0) {
      return const SizedBox.shrink();
    }

    const titleMinWidth = 40.0;

    // Ограничиваем позицию и ширину, чтобы событие не выходило за границы полосы.
    final clampedLeft = left.clamp(0.0, stripWidth);
    final clampedWidth = width.clamp(0.0, stripWidth - clampedLeft);

    final displayTitle = event.title.trim().isEmpty
        ? 'Без названия'
        : event.title;

    // Короткие события (до 15 мин) показывают только время без заголовка.
    const shortEventThresholdMinutes = 15;
    final isShortEvent =
        (segment.end - segment.start) <= shortEventThresholdMinutes;
    final showTitle = clampedWidth >= titleMinWidth && !isShortEvent;

    return Positioned(
      left: clampedLeft,
      top: 8,
      bottom: 8,
      width: clampedWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleEventTap(event),
          borderRadius: BorderRadius.circular(AppRadiiValues.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: _eventColor(
                    event, widget.categoryResolver, theme,
                  ).withValues(alpha: 0.9),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTitle)
                      Flexible(
                        child: Text(
                          displayTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        '${ScheduleEvent.formatMinutes(event.startMinutes)}–'
                        '${ScheduleEvent.formatMinutes(event.endMinutes)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
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

  final Color Function(ScheduleEvent event) colorOf;

  late final List<Color> _segmentColors = <Color>[
    for (final segment in segments)
      if (segment.event != null) colorOf(segment.event!)
      else Colors.transparent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 4;

    // Фон шкалы (весь день)
    final bgRect = Rect.fromLTWH(
      0, size.height / 2 - 2, size.width, 4,
    );
    paint.color = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.3 : 0.2,
    );
    canvas.drawRect(bgRect, paint);

    // Сегменты
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final left = _minutesToX(segment.start, size.width);
      final right = _minutesToX(segment.end, size.width);

      if (segment.type == _SegmentType.free) {
        paint.color = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
        paint.strokeWidth = 2;
        paint.style = PaintingStyle.stroke;
        _drawDashedLine(canvas, left, right, size.height / 2, paint);
      } else {
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
    final nowX = _minutesToX(currentMinutes, size.width)
        .clamp(0.0, size.width);
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
    canvas.drawCircle(
      Offset(nowX, size.height / 2), 3,
      Paint()..color = theme.colorScheme.onError,
    );
  }

  double _minutesToX(int minutes, double width) {
    return ((minutes / 1440) * width).clamp(0.0, width);
  }

  void _drawDashedLine(
    Canvas canvas, double startX, double endX, double y, Paint paint,
  ) {
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
    for (var index = 0; index < _segmentColors.length; index++) {
      if (oldDelegate._segmentColors[index] != _segmentColors[index]) {
        return true;
      }
    }
    for (var index = 0; index < segments.length; index++) {
      if (oldDelegate.segments[index] != segments[index]) return true;
    }
    return false;
  }
}
