import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/schedule_event.dart';

/// Одна строка события — используется и на «Сегодня», и в «Календаре».
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, required this.onTap});

  final ScheduleEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
        subtitle: Text(
          '${ScheduleEvent.formatMinutes(event.startMinutes)}–'
          '${ScheduleEvent.formatMinutes(event.endMinutes)} · '
          '${event.category} · ${event.status.label}',
          style: AppTypography.cardMetadata.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
