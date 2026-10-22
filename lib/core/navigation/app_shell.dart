import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../ui/screens/home_screen.dart';
import '../../ui/screens/modules_screen.dart';
import '../../modules/schedule/ui/schedule_screen.dart';
import '../../modules/accounts/ui/accounts_screen.dart';
import '../design/design_system.dart';
import 'app_routes.dart';

/// Central navigation shell for Personal Hub v2.
///
/// Handles responsive navigation:
/// - compact (<600): Top Context Bar + Floating Island Dock
/// - medium/expanded/large (>=600): Navigation Rail
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const List<_NavigationDestination> _destinations = [
    _NavigationDestination(
      route: AppRoutes.home,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Главная',
    ),
    _NavigationDestination(
      route: AppRoutes.schedule,
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.schedule,
      label: 'Расписание',
      shortLabel: 'График',
    ),
    _NavigationDestination(
      route: AppRoutes.accounts,
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle,
      label: 'Аккаунты',
      shortLabel: 'Профили',
    ),
    _NavigationDestination(
      route: AppRoutes.modules,
      icon: Icons.extension_outlined,
      selectedIcon: Icons.extension,
      label: 'Модули',
    ),
  ];

  static const List<_NavigationDestination> _secondaryDestinations = [
    _NavigationDestination(
      route: AppRoutes.search,
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      label: 'Поиск',
    ),
    _NavigationDestination(
      route: AppRoutes.settings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Настройки',
    ),
  ];

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Переход ВНУТРИ оболочки: её собственный Navigator и есть
    // владелец этих экранов. Раньше здесь вызывался корневой
    // Navigator (контекст AppShell лежит выше вложенного), из-за чего
    // оболочка оставалась под новым экраном, а её вложенный
    // Navigator так и не переключался — пункт меню подсвечивался,
    // а содержимое оставалось прежним.
    _shellNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      _destinations[index].route,
      (route) => false,
    );
  }

  void _onSecondaryDestinationSelected(int index) {
    // Поиск и настройки открываются ПОВЕРХ оболочки: их маршруты
    // принадлежат корневому Navigator, а не вложенному, иначе
    // закрыть их было бы нечем.
    Navigator.of(context, rootNavigator: true).pushNamed(
      _secondaryDestinations[index].route,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationType = AppBreakpoints.navigationType(context);
    final isCompact = navigationType == NavigationType.drawer;

    return Scaffold(
      body: _buildBody(context, navigationType, isCompact),
    );
  }

  Widget _buildBody(BuildContext context, NavigationType type, bool isCompact) {
    if (isCompact) {
      return _buildCompactLayout(context);
    } else {
      return _buildRailLayout(context, type);
    }
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Column(
      children: [
        // Top Context Bar
        _TopContextBar(
          onSearchTap: () => _onSecondaryDestinationSelected(0),
          onSettingsTap: () => _onSecondaryDestinationSelected(1),
        ),
        // Main content area
        Expanded(
          child: _shellNavigator(),
        ),
        // Floating Island Dock
        _FloatingIslandDock(
          selectedIndex: _selectedIndex,
          destinations: _destinations,
          onDestinationSelected: _onDestinationSelected,
        ),
      ],
    );
  }

  Widget _buildRailLayout(BuildContext context, NavigationType type) {
    final isPermanent = type == NavigationType.permanentRail;
    final railWidth = AppBreakpoints.railWidth(context);

    return Row(
      children: [
        // Navigation Rail
        NavigationRail(
          extended: !isPermanent,
          minWidth: railWidth,
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          leading: _buildRailLeading(context),
          trailing: _buildRailTrailing(context),
          destinations: _destinations
              .map(
                (d) => NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
              )
              .toList(),
        ),
        // Vertical divider
        VerticalDivider(
          thickness: 1,
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        // Main content area
        Expanded(
          child: _shellNavigator(),
        ),
      ],
    );
  }

  /// Вложенный Navigator оболочки.
  ///
  /// Он нужен по назначению: оболочка (rail/dock) не должна уезжать
  /// вместе со сменой раздела, и pushNamed из экранов (например,
  /// «Перейти к расписанию» на Home) должен открывать раздел ВНУТРИ
  /// оболочки, а не поверх неё. Раньше onGenerateRoute игнорировал
  /// settings.name и всегда строил экран по _selectedIndex, поэтому
  /// именованный переход открывал текущий экран.
  ///
  /// NavigatorPopHandler отдаёт вложенному Navigator системную кнопку
  /// «Назад». Без него Back уходил корневому Navigator и закрывал
  /// раздел или приложение, даже когда внутри оболочки был свой
  /// маршрут (например, экран редактирования события в «Расписании»),
  /// — то есть внутренний маршрут становился недоступен для Back.
  ///
  /// Сам NavigatorPopHandler определяет, может ли вложенный Navigator
  /// обработать Back (через NavigationNotification). Когда может —
  /// вызывает [NavigatorPopHandler.onPopWithResult], и мы делаем
  /// maybePop именно вложенного. Когда не может (мы на корневом
  /// маршруте раздела) — колбэк не вызывается вовсе, и Back
  /// обрабатывается как раньше, то есть выход из приложения.
  Widget _shellNavigator() {
    return NavigatorPopHandler<void>(
      onPopWithResult: (_) => _shellNavigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: _shellNavigatorKey,
        onGenerateRoute: (settings) {
          final routeName = settings.name;
          if (routeName != null) {
            _syncSelectedIndexWithRoute(routeName);
          }
          return MaterialPageRoute(
            builder: (context) => _buildScreenForRoute(routeName) ??
                _buildScreenForIndex(_selectedIndex),
            settings: settings,
          );
        },
      ),
    );
  }

  /// Экран для имени маршрута, null — если такого раздела нет.
  Widget? _buildScreenForRoute(String? routeName) {
    if (routeName == AppRoutes.home) return const HomeScreen();
    if (routeName == AppRoutes.schedule) {
      return const ScheduleScreen(moduleId: 'schedule');
    }
    if (routeName == AppRoutes.accounts) {
      return const AccountsScreen(moduleId: 'accounts');
    }
    if (routeName == AppRoutes.modules) return const ModulesScreen();
    return null;
  }

  /// Подсветка активного раздела следует за маршрутом.
  ///
  /// Переход может прийти не только из докa (там индекс уже выставлен),
  /// но и из pushNamed с экрана — тогда индекс нужно догнать. Запись
  /// отложена на следующий кадр: onGenerateRoute вызывается во время
  /// сборки, и setState прямо здесь сломало бы Navigator.
  void _syncSelectedIndexWithRoute(String routeName) {
    final index = _destinations.indexWhere((d) => d.route == routeName);
    if (index < 0 || index == _selectedIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = index;
      });
    });
  }

  Widget? _buildRailLeading(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Personal Hub',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget? _buildRailTrailing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Здесь НЕЛЬЗЯ Spacer: NavigationRail передаёт trailing'у
        // неограниченную по высоте constraints, и Spacer приводил к
        // "RenderFlex children have non-zero flex but incoming height
        // constraints are unbounded" — падение раскладки на любой ширине
        // от 600dp. Поэтому отступ фиксированный.
        SizedBox(height: AppSpacing.lg),
        _RailSecondaryAction(
          destination: _secondaryDestinations[0],
          onTap: () => _onSecondaryDestinationSelected(0),
        ),
        SizedBox(height: AppSpacing.sm),
        _RailSecondaryAction(
          destination: _secondaryDestinations[1],
          onTap: () => _onSecondaryDestinationSelected(1),
        ),
        SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const ScheduleScreen(moduleId: 'schedule');
      case 2:
        return const AccountsScreen(moduleId: 'accounts');
      case 3:
        return const ModulesScreen();
      default:
        return const HomeScreen();
    }
  }
}

final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

class _NavigationDestination {
  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Короткая подпись для компактного дока, где полная не помещается.
  ///
  /// На телефоне 360 dp на раздел приходится ~90 dp минус внутренние
  /// отступы (~58 dp текста): «Расписание» и «Аккаунты» при масштабе
  /// текста 1.3 туда не влезают и переносились по слогам. В рельсе
  /// (≥600 dp) ширины хватает, поэтому там показывается [label].
  /// Идентификатор маршрута при этом не меняется.
  final String? shortLabel;

  const _NavigationDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.shortLabel,
  });

  String labelFor(bool compact) => compact && shortLabel != null
      ? shortLabel!
      : label;
}

/// Top Context Bar for compact layout.
class _TopContextBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;

  const _TopContextBar({
    required this.onSearchTap,
    required this.onSettingsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      automaticallyImplyLeading: false,
      elevation: AppSpacing.elevation0,
      scrolledUnderElevation: AppSpacing.elevation1,
      surfaceTintColor: Colors.transparent,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      title: Text(
        'Personal Hub',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        // Search action
        IconButton(
          icon: const Icon(Icons.search_outlined),
          onPressed: onSearchTap,
          tooltip: 'Поиск',
        ),
        // Settings action
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettingsTap,
          tooltip: 'Настройки',
        ),
      ],
    );
  }
}

/// Floating Island Dock for compact layout.
class _FloatingIslandDock extends StatelessWidget {
  final int selectedIndex;
  final List<_NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  const _FloatingIslandDock({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.md,
        ),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadiiValues.xl),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(
                  alpha: isDark ? 0.3 : 0.15,
                ),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(destinations.length, (index) {
              final dest = destinations[index];
              final isSelected = index == selectedIndex;

              return Expanded(
                child: InkWell(
                  onTap: () => onDestinationSelected(index),
                  borderRadius: BorderRadius.circular(AppRadiiValues.xl),
                  child: AnimatedContainer(
                    duration: AppAnimations.getDuration(
                      context,
                      AppSpacing.durationStandard,
                    ),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                      horizontal: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadiiValues.xl),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      // stretch, а не center по умолчанию: иначе Column
                      // расширяется под самую широкую подпись (66 dp против
                      // 58 dp доступных) и ряд переполняется на 8 px.
                      // При stretch дети получают реальную ширину, а
                      // FittedBox ниже масштабирует текст по ней.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          isSelected ? dest.selectedIcon : dest.icon,
                          size: 24,
                          color: isSelected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: AppSpacing.xs),
                        // Подпись — одна строка. Раньше `labelSmall` без
                        // maxLines переносил «Расписание»/«Аккаунты» по
                        // слогам, и ряд подписей вылезал за пределы
                        // контейнера. Теперь размер из темы (labelLarge,
                        // 11–12 sp) плюс FittedBox: если шиены не хватит
                        // даже короткой подписи, текст масштабируется,
                        // а не ломает вёрстку.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            dest.labelFor(true),
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: isSelected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Secondary action button in rail trailing area.
class _RailSecondaryAction extends StatelessWidget {
  final _NavigationDestination destination;
  final VoidCallback onTap;

  const _RailSecondaryAction({
    required this.destination,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadiiValues.md),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              destination.icon,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              destination.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}