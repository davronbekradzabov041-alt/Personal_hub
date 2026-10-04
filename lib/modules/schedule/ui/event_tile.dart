import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/schedule_event.dart';
import 'category_visuals.dart';

/// Одна строка события — используется и на «Сегодня», и в «Календаре».
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.onTap,
    this.category,
  });

  final ScheduleEvent event;
  final VoidCallback onTap;

  /// Разрешённая категория. null — вызывающий её не перечитывал, и
  /// плитка показывает только время и статус: показывать устаревшую
  /// строку события здесь означало бы показать ПЕРВОЕ из двух разных
  /// правил (второе — в [CategoryResolver]).
  final ResolvedCategory? category;

  @override
  Widget build(BuildContext context) {
    final resolved = category;

    return AppComponents.card(
      onTap: onTap,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _priorityColor(context, event.priority),
          child: Text(
            ScheduleEvent.formatMinutes(event.startMinutes).substring(0, 2),
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
        title: Text(
          event.title,
          style: event.status == EventStatus.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                '${ScheduleEvent.formatMinutes(event.startMinutes)}–'
                '${ScheduleEvent.formatMinutes(event.endMinutes)}'
                '${resolved == null ? '' : ' · ${resolved.name}'} · '
                '${event.status.label}',
                style: AppTypography.cardMetadata.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (resolved != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Icon(
                  resolved.icon,
                  size: 14,
                  color: resolved.colorOr(
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        trailing: Icon(
          _statusIcon(event.status),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Color _priorityColor(BuildContext context, EventPriority priority) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (priority) {
      case EventPriority.low:
        return colorScheme.tertiary;
      case EventPriority.medium:
        return colorScheme.secondary;
      case EventPriority.high:
        return colorScheme.error;
    }
  }

  IconData _statusIcon(EventStatus status) {
    switch (status) {
      case EventStatus.planned:
        return Icons.schedule_outlined;
      case EventStatus.done:
        return Icons.check_circle_outline;
      case EventStatus.skipped:
        return Icons.remove_circle_outline;
    }
  }
}