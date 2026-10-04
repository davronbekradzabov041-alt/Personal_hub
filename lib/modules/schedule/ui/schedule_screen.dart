import 'package:flutter/material.dart';
import '../../../core/modules/module_manager_scope.dart';
import '../schedule_category_repository.dart';
import '../schedule_repository.dart';
import 'calendar_tab.dart';
import 'category_form_screen.dart';
import 'category_list_view.dart';
import 'event_form_screen.dart';
import 'today_tab.dart';

/// Главный экран Schedule.
///
/// Получает ModuleApi через ModuleManagerScope.of(context) — тот же
/// приём, что и у страницы ExampleModule (Этап 10): buildPage(context)
/// в контракте Module (Этап 7) не получает ModuleApi напрямую, чтобы
/// не тянуть за собой раннюю реализацию ModuleManager — вместо этого
/// каждая страница модуля сама достаёт его из Scope.
/// AppBar предоставляется AppShell. TabBar перенесён в body.
///
/// Категории — третья вкладка, а не отдельный экран: ими пользуются
/// нечасто, но выбирают в них постоянно (каждый раз, когда у события
/// меняется категория), и прятать их за кнопку в AppBar означало бы
/// лишний шаг на каждом таком выборе.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.moduleId});
  final String moduleId;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ScheduleRepository? _repository;
  ScheduleCategoryRepository? _categoryRepository;

  /// Меняется, когда категория создана кнопкой на экране: список
  /// категорий живёт в своём State и не видит нажатий этого экрана.
  /// Тот же приём с сигналом, что у Home-секции Schedule.
  final ValueNotifier<int> _categorySignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // apiFor() возвращает один и тот же кэшированный ModuleApi между
    // вызовами (Этап 8/10) — присваивать репозиторий заново на каждый
    // didChangeDependencies безопасно (он просто тонкая обёртка над
    // storage), но не в build(): там это привело бы к пересозданию
    // объекта на каждую перерисовку без всякой пользы.
    final api = ModuleManagerScope.of(context).apiFor(widget.moduleId);
    _repository = ScheduleRepository(api.storage);
    _categoryRepository = ScheduleCategoryRepository(api.storage);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _categorySignal.dispose();
    super.dispose();
  }

  int _refreshTick = 0;

  Future<void> _addEvent() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          repository: _repository!,
          categoryRepository: _categoryRepository!,
        ),
      ),
    );
    // TodayTab/CalendarTab перечитывают данные в initState() — простого
    // setState() родителя недостаточно, Flutter сохранит их State (тот
    // же ключ/тип виджета). Меняем ключ через тик, чтобы гарантированно
    // получить свежий initState() на обеих вкладках после добавления
    // события через FAB. Плата: у «Календаря» при этом сбрасывается
    // выбранная дата на сегодня — принятое упрощение для базовой версии
    // Этапа 14, не влияет на сохранность самих данных.
    if (mounted) setState(() => _refreshTick++);
  }

  /// Создание категории с вкладки: форма открывается поверх экрана, а
  /// список вкладки узнаёт об изменении через сигнал.
  Future<void> _addCategory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(repository: _categoryRepository!),
      ),
    );
    if (created == true) _categorySignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository!;
    final categoryRepository = _categoryRepository!;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            automaticallyImplyLeading: false,
            pinned: true,
            floating: true,
            snap: true,
            title: const Text('Расписание'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Сегодня'),
                Tab(text: 'Календарь'),
                Tab(text: 'Категории'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            TodayTab(
              key: ValueKey('today-$_refreshTick'),
              repository: repository,
              categoryRepository: categoryRepository,
            ),
            CalendarTab(
              key: ValueKey('calendar-$_refreshTick'),
              repository: repository,
              categoryRepository: categoryRepository,
            ),
            CategoryListView(
              key: ValueKey('categories-$_refreshTick'),
              repository: categoryRepository,
              refreshSignal: _categorySignal,
              onCreateRequested: _addCategory,
            ),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          // На вкладке категорий FAB создаёт КАТЕГОРИЮ, а не событие:
          // одна кнопка с двумя смыслами в разных вкладках — источник
          // ошибок, а стоимость второго FAB равна нулю.
          if (_tabController.index == 2) {
            return FloatingActionButton(
              onPressed: _addCategory,
              tooltip: 'Создать категорию',
              child: const Icon(Icons.create_new_folder_outlined),
            );
          }
          return FloatingActionButton(
            onPressed: _addEvent,
            tooltip: 'Добавить событие',
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }
}