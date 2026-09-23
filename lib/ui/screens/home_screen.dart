import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../modules/schedule/schedule_repository.dart';
import '../../modules/schedule/models/schedule_event.dart';
import '../../core/design/design_system.dart';
import '../widgets/app_drawer.dart';

/// Главный экран Personal Hub — Focused Workspace.
///
/// Композиция: Hero (дата + метрика) → Schedule Preview → Module Shortcuts.
/// Без AppBar — status bar blends into hero.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ScheduleRepository _scheduleRepository;
  List<ScheduleEvent> _todayEvents = [];
  ScheduleDaySummary? _daySummary;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = ModuleManagerScope.of(context);
    final api = manager.apiFor('schedule');
    _scheduleRepository = ScheduleRepository(api.storage);
    _loadTodayData();
  }

  Future<void> _loadTodayData() async {
    final now = DateTime.now();
    final events = await _scheduleRepository.getForDate(now);
    if (mounted) {
      setState(() {
        _todayEvents = events.take(3).toList();
        _daySummary = ScheduleDaySummary.fromEvents(events);
        _loading = false;
      });
    }
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

  List<Widget> _buildSchedulePreview(BuildContext context, ThemeData theme) {
    if (_todayEvents.isEmpty) {
      return [
        AppComponents.featureCard(
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
                  'На сегодня событий нет',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.space2),
                Text(
                  'Нажмите "Все события" чтобы добавить',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return _todayEvents.take(3).map((event) => Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.space3),
      child: AppComponents.featureCard(
        context: context,
        accentColor: AppColors.accentAmber,
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.schedule),
        child: Padding(
          padding: AppInsets.cardPadding,
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentAmber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: AppSpacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      '${ScheduleEvent.formatMinutes(event.startMinutes)}–${ScheduleEvent.formatMinutes(event.endMinutes)}  ·  ${event.category}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
      ),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: null, // No AppBar on Home - hero blends with status bar
      drawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTodayData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ===== HERO =====
                  SliverToBoxAdapter(
                    child: AppComponents.hero(
                      context: context,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + AppSpacing.space7,
                          bottom: AppSpacing.space7,
                          left: AppSpacing.space7,
                          right: AppSpacing.space7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(DateTime.now()),
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            SizedBox(height: AppSpacing.space3),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  _todayEvents.length.toString(),
                                  style: theme.textTheme.displayLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                SizedBox(width: AppSpacing.space3),
                                Text(
                                  _todayEvents.length == 1 ? 'событие' : 'события',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (_daySummary != null) ...[
                              SizedBox(height: AppSpacing.space4),
                              Row(
                                children: [
                                  _MetricChip(
                                    label: 'Занято',
                                    value: _formatDuration(_daySummary!.totalBusy),
                                    color: theme.colorScheme.primary,
                                  ),
                                  SizedBox(width: AppSpacing.space3),
                                  _MetricChip(
                                    label: 'Свободно',
                                    value: _formatDuration(_daySummary!.totalFree),
                                    color: theme.colorScheme.tertiary,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ===== SCHEDULE PREVIEW =====
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.space7,
                        vertical: AppSpacing.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Расписание',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_todayEvents.isNotEmpty)
                                AppComponents.filledButton(
                                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.schedule),
                                  leadingIcon: Icons.chevron_right,
                                  child: const Text('Все события'),
                                ),
                            ],
                          ),
SizedBox(height: AppSpacing.space4),
                          ..._buildSchedulePreview(context, theme),

                          // ===== MODULE SHORTCUTS =====
],
                      ),
                    ),
                  ),

                  // ===== MODULE SHORTCUTS =====
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.space7,
                        vertical: AppSpacing.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Модули',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: AppSpacing.space4),
                          _ModuleShortcutsGrid(),
                        ],
                      ),
                    ),
                  ),

                  // Bottom padding for safe area
                  SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.space9),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Small metric display chip
class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: AppComponents.featureCard(
        context: context,
        accentColor: color,
        child: Padding(
          padding: AppInsets.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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

/// Adaptive grid of module shortcuts
class _ModuleShortcutsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = AppBreakpoints.isCompact(context);

    final shortcuts = [
      _Shortcut(
        icon: Icons.schedule_outlined,
        label: 'Расписание',
        color: AppColors.accentAmber,
        route: AppRoutes.schedule,
      ),
      _Shortcut(
        icon: Icons.extension_outlined,
        label: 'Модули',
        color: AppColors.accentIndigo,
        route: AppRoutes.modules,
      ),
      _Shortcut(
        icon: Icons.search_outlined,
        label: 'Поиск',
        color: AppColors.accentViolet,
        route: AppRoutes.search,
      ),
      _Shortcut(
        icon: Icons.settings_outlined,
        label: 'Настройки',
        color: AppColors.accentSlate,
        route: AppRoutes.settings,
      ),
    ];

    return isCompact
        ? Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ShortcutCard(shortcut: shortcuts[0]),
                  ),
                  SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: _ShortcutCard(shortcut: shortcuts[1]),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.space3),
              Row(
                children: [
                  Expanded(
                    child: _ShortcutCard(shortcut: shortcuts[2]),
                  ),
                  SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: _ShortcutCard(shortcut: shortcuts[3]),
                  ),
                ],
              ),
            ],
          )
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.4,
              crossAxisSpacing: AppSpacing.space3,
              mainAxisSpacing: AppSpacing.space3,
            ),
            itemCount: shortcuts.length,
            itemBuilder: (context, index) => _ShortcutCard(shortcut: shortcuts[index]),
          );
  }
}

class _Shortcut {
  final IconData icon;
  final String label;
  final Color color;
  final String route;

  const _Shortcut({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
}

class _ShortcutCard extends StatelessWidget {
  final _Shortcut shortcut;

  const _ShortcutCard({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppComponents.featureCard(
      context: context,
      accentColor: shortcut.color,
      onTap: () => Navigator.of(context).pushNamed(shortcut.route),
      child: Padding(
        padding: AppInsets.cardPaddingMedium,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(AppSpacing.space4),
              decoration: BoxDecoration(
                color: shortcut.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadiiValues.lg),
              ),
              child: Icon(
                shortcut.icon,
                size: 28,
                color: shortcut.color,
              ),
            ),
            SizedBox(height: AppSpacing.space3),
            Text(
              shortcut.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}