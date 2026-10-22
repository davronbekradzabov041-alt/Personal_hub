import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../models/schedule_event.dart';
import '../category_visuals.dart';

/// Upcoming Agenda — список ближайших событий (максимум 3).
///
/// Показывает только будущие события, прошедшие скрывает.
/// Заменяет старый Schedule Preview.
class UpcomingAgenda extends StatelessWidget {
  const UpcomingAgenda({
    super.key,
    required this.events,
    required this.onNavigateToSchedule,
    required this.onEventTap,
    this.categoryResolver,
    this.maxItems = 3,
  });

  final List<ScheduleEvent> events;
  final VoidCallback onNavigateToSchedule;
  final void Function(ScheduleEvent event) onEventTap;
  final int maxItems;

  /// Правило разрешения категории. null — виджет показывает события без
  /// категорий: он же используется в тестах и превью, где справочника
  /// нет, и выдумывать подпись значило бы расходиться с [CategoryResolver].
  final CategoryResolver? categoryResolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Фильтруем только будущие события
    final upcoming = events
        .where((e) => e.endMinutes > currentMinutes)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    final displayEvents = upcoming.take(maxItems).toList();

    if (displayEvents.isEmpty) {
      return _EmptyState(onNavigate: onNavigateToSchedule);
    }

    final resolver = categoryResolver;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Ближайшие дела',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (upcoming.length > maxItems)
              Flexible(
                child: AppComponents.textButton(
                  onPressed: onNavigateToSchedule,
                  child: Text(
                    'Все (${upcoming.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: AppSpacing.space3),
        ...displayEvents.map((event) => _AgendaItem(
              event: event,
              category: resolver?.resolve(event),
              onTap: onEventTap,
            )).toList(),
      ],
    );
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({required this.event, required this.onTap, this.category});

  final ScheduleEvent event;
  final void Function(ScheduleEvent event) onTap;
  final ResolvedCategory? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final isCurrent = event.startMinutes <= currentMinutes && event.endMinutes > currentMinutes;

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.space3),
      child: AppComponents.featureCard(
        context: context,
        accentColor: _getEventColor(event, theme),
        onTap: () => onTap(event),
        child: Row(
          children: [
            // Индикатор времени/статуса
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: isCurrent ? theme.colorScheme.error : _getEventColor(event, theme),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title.trim().isEmpty ? 'Без названия' : event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isCurrent ? theme.colorScheme.error : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent)
                        Padding(
                          padding: EdgeInsets.only(left: AppSpacing.xs),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadiiValues.full),
                            ),
                            child: Text(
                              'СЕЙЧАС',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    '${ScheduleEvent.formatMinutes(event.startMinutes)}–${ScheduleEvent.formatMinutes(event.endMinutes)}'
                    '${category == null ? '' : '  ·  ${category!.name}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Color _getEventColor(ScheduleEvent event, ThemeData theme) {
    switch (event.priority) {
      case EventPriority.high:
        return theme.colorScheme.error;
      case EventPriority.low:
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.primary;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNavigate});

  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppComponents.featureCard(
      context: context,
      accentColor: AppColors.accentAmber,
      child: Padding(
        padding: AppInsets.cardPaddingMedium,
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            SizedBox(height: AppSpacing.space3),
            Text(
              'На сегодня дел больше нет',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.space2),
            Text(
              'Отличная работа! Отдохни или добавь новое дело.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.space4),
            SizedBox(
              width: double.infinity,
              child: AppComponents.filledButton(
                onPressed: onNavigate,
                leadingIcon: Icons.add,
                child: const Text('Добавить дело'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}