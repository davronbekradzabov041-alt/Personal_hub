import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/schedule_event.dart';
import '../schedule_repository.dart';
import 'event_form_screen.dart';
import 'event_tile.dart';

/// Вкладка «Сегодня»: список событий сегодняшнего дня, свободное время
/// и суммарная занятость.
class TodayTab extends StatefulWidget {
  const TodayTab({super.key, required this.repository});
  final ScheduleRepository repository;

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  late Future<List<ScheduleEvent>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.getForDate(DateTime.now());
  }

  Future<void> _openEvent(ScheduleEvent? event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          repository: widget.repository,
          existing: event,
          initialDate: DateTime.now(),
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScheduleEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return AppComponents.loadingIndicator();
        }

        final events = snapshot.data!;
        final summary = ScheduleDaySummary.fromEvents(events);

        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView(
            padding: AppInsets.md,
            children: [
              AppComponents.card(
                child: Padding(
                  padding: AppInsets.md,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SummaryStat(
                        label: 'Занято',
                        value: _formatDuration(summary.totalBusy),
                      ),
                      _SummaryStat(
                        label: 'Свободно',
                        value: _formatDuration(summary.totalFree),
                      ),
                      _SummaryStat(
                        label: 'Событий',
                        value: events.length.toString(),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              if (events.isEmpty)
                AppComponents.emptyState(
                  context: context,
                  icon: Icons.event_available_outlined,
                  title: 'На сегодня событий нет',
                  subtitle: 'Нажмите + чтобы добавить событие',
                )
              else
                ...events.map((e) => EventTile(
                      event: e,
                      onTap: () => _openEvent(e),
                    )),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (minutes == 0) return '$hours ч';
    return '$hours ч $minutes мин';
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTypography.statValue.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        )),
        Text(label, style: AppTypography.statLabel.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        )),
      ],
    );
  }
}
