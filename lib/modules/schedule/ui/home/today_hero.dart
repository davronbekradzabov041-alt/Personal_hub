import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../models/schedule_event.dart';
import '../../schedule_repository.dart';

/// Today Hero — показывает живое состояние дня в реальном времени.
///
/// Состояния:
/// - Сейчас идёт событие → «ИДЁТ СЕЙЧАС»
/// - Есть свободное окно → «СВОБОДНО • осталось XX мин»
/// - День завершён → «ВСЕ ДЕЛА ЗАВЕРШЕНЫ»
class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.events,
    required this.daySummary,
    required this.onNavigateToSchedule,
  });

  final List<ScheduleEvent> events;
  final ScheduleDaySummary daySummary;
  final VoidCallback onNavigateToSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Находим текущее событие
    ScheduleEvent? currentEvent;
    for (final event in events) {
      if (event.startMinutes <= currentMinutes && event.endMinutes > currentMinutes) {
        currentEvent = event;
        break;
      }
    }

    // Находим ближайшее будущее событие
    ScheduleEvent? nextEvent;
    for (final event in events) {
      if (event.startMinutes > currentMinutes) {
        nextEvent = event;
        break;
      }
    }

    String statusTitle;
    String statusSubtitle;
    Color statusColor;
    IconData statusIcon;

    if (currentEvent != null) {
      // Сейчас идёт событие
      final remaining = currentEvent.endMinutes - currentMinutes;
      statusTitle = 'ИДЁТ СЕЙЧАС';
      statusSubtitle = 'Осталось ${_formatMinutes(remaining)} до конца';
      statusColor = theme.colorScheme.error;
      statusIcon = Icons.play_circle_filled;
    } else if (nextEvent != null) {
      // Есть свободное окно до следующего события
      final freeMinutes = nextEvent.startMinutes - currentMinutes;
      statusTitle = 'СВОБОДНО';
      statusSubtitle = 'До следующего дела ${_formatMinutes(freeMinutes)}';
      statusColor = theme.colorScheme.tertiary;
      statusIcon = Icons.pause_circle_filled;
    } else if (events.isNotEmpty) {
      // День завершён
      statusTitle = 'ВСЕ ДЕЛА ЗАВЕРШЕНЫ';
      statusSubtitle = 'Хорош отдых';
      statusColor = theme.colorScheme.outline;
      statusIcon = Icons.check_circle_outline;
    } else {
      // Пустой день
      statusTitle = 'СВОБОДНЫЙ ДЕНЬ';
      statusSubtitle = 'Ничего не запланировано';
      statusColor = theme.colorScheme.outline;
      statusIcon = Icons.event_available_outlined;
    }

    return AppComponents.hero(
      context: context,
      child: Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.space7,
          bottom: AppSpacing.space7,
          left: AppSpacing.space7,
          right: AppSpacing.space7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Дата
            Text(
              _formatDate(now),
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: AppSpacing.space3),
            // Статус дня
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.space3,
                      vertical: AppSpacing.space2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadiiValues.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            statusTitle,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    statusSubtitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.space4),
            // Метрики дня
            if (daySummary.totalBusy > Duration.zero || daySummary.totalFree > Duration.zero)
              Wrap(
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space3,
                children: [
                  _MetricChip(
                    label: 'Занято',
                    value: _formatDuration(daySummary.totalBusy),
                    color: theme.colorScheme.primary,
                  ),
                  _MetricChip(
                    label: 'Свободно',
                    value: _formatDuration(daySummary.totalFree),
                    color: theme.colorScheme.tertiary,
                  ),
                  _MetricChip(
                    label: 'Событий',
                    value: events.length.toString(),
                    color: theme.colorScheme.secondary,
                  ),
                ],
              ),
            SizedBox(height: AppSpacing.space4),
            // CTA к расписанию
            SizedBox(
              width: double.infinity,
              child: AppComponents.filledButton(
                onPressed: onNavigateToSchedule,
                leadingIcon: Icons.chevron_right,
                child: const Text('Открыть расписание'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '${minutes} мин';
    if (minutes == 0) return '$hours ч';
    return '$hours ч $minutes мин';
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes мин';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours ч';
    return '$hours ч $mins мин';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 80),
      child: AppComponents.featureCard(
        context: context,
        accentColor: color,
        child: Padding(
          padding: AppInsets.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}