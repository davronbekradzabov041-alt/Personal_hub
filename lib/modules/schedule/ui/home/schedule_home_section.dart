import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../models/category.dart';
import '../../models/schedule_event.dart';
import '../../schedule_category_repository.dart';
import '../../schedule_repository.dart';
import '../category_visuals.dart';
import '../event_form_screen.dart';
import 'timeline_strip.dart';
import 'today_hero.dart';
import 'upcoming_agenda.dart';

/// Home-секция модуля Schedule.
///
/// Всё, что главный экран раньше знал о Schedule, живёт здесь: и
/// репозиторий, и загрузка данных, и оба действия пользователя.
/// Ядро получает от модуля только `Widget` (см. `HomeSection`) и не
/// знает ни про `ScheduleEvent`, ни про `ScheduleDaySummary`, ни про
/// `EventFormScreen`.
///
/// Репозиторий получается тем же способом, каким его получает
/// ScheduleScreen: через `ModuleManagerScope.of(context).apiFor(...)`.
/// Нового API для этого не заводилось.
///
/// [refreshSignal] — часть контракта, а не деталь реализации: ядро
/// дёргает `HomeSection.onRefresh`, а виджет об этом узнаёт через
/// сигнал, который ему передал владелец секции. Так обновление
/// доходит до State виджета без GlobalKey и без статического
/// состояния — на каждый экземпляр модуля приходится свой сигнал.
class ScheduleHomeSection extends StatefulWidget {
  const ScheduleHomeSection({
    super.key,
    required this.moduleId,
    required this.refreshSignal,
  });

  final String moduleId;

  /// Меняется при pull-to-refresh главного экрана.
  final ValueNotifier<int> refreshSignal;

  @override
  State<ScheduleHomeSection> createState() => _ScheduleHomeSectionState();
}

class _ScheduleHomeSectionState extends State<ScheduleHomeSection> {
  // Репозиторий создаётся один раз за жизнь виджета.
  // didChangeDependencies вызывается не только при смене наследников,
  // но и при изменении темы или MediaQuery, поэтому `late final` с
  // присваиванием здесь падал бы с LateInitializationError на любой
  // смене темы (та же причина, что и на HomeScreen в AUD-02).
  ScheduleRepository? _repository;
  ScheduleCategoryRepository? _categoryRepository;
  List<ScheduleEvent> _events = <ScheduleEvent>[];
  List<Category> _categories = <Category>[];
  ScheduleDaySummary? _daySummary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_onRefreshSignal);
  }

  @override
  void didUpdateWidget(covariant ScheduleHomeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.refreshSignal, widget.refreshSignal)) return;
    oldWidget.refreshSignal.removeListener(_onRefreshSignal);
    widget.refreshSignal.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (mounted) _loadTodayData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) return;

    final api = ModuleManagerScope.of(context).apiFor(widget.moduleId);
    _repository = ScheduleRepository(api.storage);
    _categoryRepository = ScheduleCategoryRepository(api.storage);
    _loadTodayData();
  }

  /// Повторное чтение дня: и при первом построении, и при обновлении.
  ///
  /// Категории читаются здесь же, а не остаются от прошлой загрузки:
  /// переименование категории с другого экрана обязано менять то, что
  /// видно на главном, иначе главный экран показывал бы имя, которого
  /// у пользователя уже нет.
  Future<void> _loadTodayData() async {
    final repository = _repository;
    final categoryRepository = _categoryRepository;
    if (repository == null || categoryRepository == null) return;

    final events = await repository.getForDate(DateTime.now());
    final categories = await categoryRepository.getAll();
    if (!mounted) return;
    setState(() {
      _events = events;
      _categories = categories;
      _daySummary = ScheduleDaySummary.fromEvents(events);
      _loading = false;
    });
  }

  Future<void> _openEventForm(ScheduleEvent event) async {
    final repository = _repository;
    final categoryRepository = _categoryRepository;
    if (repository == null || categoryRepository == null) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          repository: repository,
          categoryRepository: categoryRepository,
          existing: event,
        ),
      ),
    );
    if (changed == true && mounted) {
      _loadTodayData();
    }
  }

  void _openSchedule() {
    Navigator.of(context).pushNamed(AppRoutes.schedule);
  }

  @override
  Widget build(BuildContext context) {
    // Пока данных нет, секция не занимает места: главный экран не
    // должен мигать индикатором загрузки целиком из-за одного модуля.
    if (_loading) return const SizedBox.shrink();

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final resolver = CategoryResolver.of(_categories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ===== TODAY HERO =====
        TodayHero(
          events: _events,
          daySummary: _daySummary!,
          onNavigateToSchedule: _openSchedule,
        ),
        // ===== TIMELINE STRIP =====
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space7,
            vertical: AppSpacing.space4,
          ),
          child: TimelineStrip(
            events: _events,
            currentMinutes: currentMinutes,
            categoryResolver: resolver,
            onEventTap: _openEventForm,
          ),
        ),
        // ===== UPCOMING AGENDA =====
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space7,
            vertical: AppSpacing.space4,
          ),
          child: UpcomingAgenda(
            events: _events,
            categoryResolver: resolver,
            onNavigateToSchedule: _openSchedule,
            onEventTap: _openEventForm,
            maxItems: 3,
          ),
        ),
      ],
    );
  }
}