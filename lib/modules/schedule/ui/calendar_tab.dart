import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/schedule_event.dart';
import '../schedule_repository.dart';
import 'event_form_screen.dart';
import 'event_tile.dart';

/// Вкладка «Календарь»: выбор даты + события выбранного дня.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key, required this.repository});
  final ScheduleRepository repository;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _selectedDate = DateTime.now();
  late Future<List<ScheduleEvent>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.getForDate(_selectedDate);
  }

  Future<void> _openEvent(ScheduleEvent? event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          repository: widget.repository,
          existing: event,
          initialDate: _selectedDate,
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: DateTime(_selectedDate.year - 2),
          lastDate: DateTime(_selectedDate.year + 2),
          onDateChanged: (date) {
            setState(() {
              _selectedDate = date;
              _reload();
            });
          },
        ),
        Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<ScheduleEvent>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 50),
                  child: AppComponents.loadingIndicator(),
                );
              }
              final events = snapshot.data!;
              if (events.isEmpty) {
                return AppComponents.emptyState(
                  context: context,
                  icon: Icons.event_outlined,
                  title: 'Событий в этот день нет',
                );
              }
              return ListView(
                padding: AppInsets.md,
                children: events
                    .map((e) => EventTile(event: e, onTap: () => _openEvent(e)))
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
