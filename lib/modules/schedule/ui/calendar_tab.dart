import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../models/schedule_event.dart';
import '../schedule_category_repository.dart';
import '../schedule_repository.dart';
import 'category_visuals.dart';
import 'event_form_screen.dart';
import 'event_tile.dart';

/// Вкладка «Календарь»: выбор даты + события выбранного дня.
class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.repository,
    required this.categoryRepository,
  });

  final ScheduleRepository repository;
  final ScheduleCategoryRepository categoryRepository;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _selectedDate = DateTime.now();
  late Future<List<ScheduleEvent>> _future;
  List<Category> _categories = const <Category>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.getForDate(_selectedDate);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await widget.categoryRepository.getAll();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _openEvent(ScheduleEvent? event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          repository: widget.repository,
          categoryRepository: widget.categoryRepository,
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
              final resolver = CategoryResolver.of(_categories);
              return ListView(
                padding: AppInsets.screenBody(context),
                children: events
                    .map((e) => EventTile(
                          event: e,
                          category: resolver.resolve(e),
                          onTap: () => _openEvent(e),
                        ))
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}