import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../../../core/modules/module_manager_scope.dart';
import 'event_form_screen.dart';
import '../schedule_repository.dart';
import 'calendar_tab.dart';
import 'today_tab.dart';

/// Главный экран Schedule.
///
/// Получает ModuleApi через ModuleManagerScope.of(context) — тот же
/// приём, что и у страницы ExampleModule (Этап 10): buildPage(context)
/// в контракте Module (Этап 7) не получает ModuleApi напрямую, чтобы
/// не тянуть за собой раннюю реализацию ModuleManager — вместо этого
/// каждая страница модуля сама достаёт его из Scope.
/// AppBar предоставляется AppShell. TabBar перенесён в body.
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _refreshTick = 0;

  Future<void> _addEvent() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(repository: _repository!),
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

  @override
  Widget build(BuildContext context) {
    final repository = _repository!;

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
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            TodayTab(key: ValueKey('today-$_refreshTick'), repository: repository),
            CalendarTab(key: ValueKey('calendar-$_refreshTick'), repository: repository),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        tooltip: 'Добавить событие',
        child: const Icon(Icons.add),
      ),
    );
  }
}
