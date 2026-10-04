import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../models/schedule_event.dart';
import '../schedule_category_repository.dart';
import '../schedule_repository.dart';
import 'category_visuals.dart';
import 'event_form_screen.dart';
import 'event_tile.dart';

/// Вкладка «Сегодня»: список событий сегодняшнего дня, свободное время
/// и суммарная занятость.
class TodayTab extends StatefulWidget {
  const TodayTab({
    super.key,
    required this.repository,
    required this.categoryRepository,
  });

  final ScheduleRepository repository;
  final ScheduleCategoryRepository categoryRepository;

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  late Future<List<ScheduleEvent>> _future;
  List<Category> _categories = const <Category>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.getForDate(DateTime.now());
    _loadCategories();
  }

  /// Читает категории для показа. Отдельная загрузка от событий
  /// намеренна: события дня и категории меняются в разные моменты
  /// (категорию можно переименовать из соседней вкладки), и связывать
  /// их одним Future означало бы ждать оба чтения, чтобы показать
  /// список дня.
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
        final resolver = CategoryResolver.of(_categories);

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
                      category: resolver.resolve(e),
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