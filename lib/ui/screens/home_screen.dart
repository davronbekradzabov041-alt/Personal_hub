import 'package:flutter/material.dart';
import '../../core/design/design_system.dart';
import '../../core/modules/home_section.dart';
import '../../core/modules/module_manager.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../core/modules/module_registry.dart';

/// Главный экран Personal Hub — Today Cockpit Foundation.
///
/// Экран НЕ знает, какие модули существуют и что они умеют. Он
/// спрашивает у ядра одно: какие секции предлагают активные модули,
/// и размещает их в порядке [HomeSection.order]. Всё содержимое
/// секции — репозиторий, модели, экраны — остаётся внутри модуля.
///
/// Благодаря этому Accounts, Finance или Games подключат свой блок
/// на главном экране, не меняя ни одной строки здесь.
///
/// AppBar/Drawer предоставляется AppShell.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);

    // ModuleManager — ChangeNotifier, поэтому список секций
    // пересобирается сам при install/enable/disable/uninstall и при
    // update: модуль остаётся виден ровно тогда, когда активен.
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () => _refreshSections(context, manager),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _buildSlivers(context, _sectionsOf(manager)),
            ),
          ),
        );
      },
    );
  }

  /// Секции активных модулей в порядке объявления.
  ///
  /// Ничего не кэшируется: список читается заново на каждой сборке,
  /// иначе подменённый `ModuleManager.update()` новым экземпляром
  /// модуля показал бы устаревшие секции.
  List<HomeSection> _sectionsOf(ModuleManager manager) {
    final sections = <HomeSection>[];
    for (final module in ModuleRegistry.modules) {
      if (!manager.isEnabled(module.id)) continue;
      sections.addAll(module.homeSections);
    }
    sections.sort((a, b) => a.order.compareTo(b.order));
    return sections;
  }

  /// Pull-to-refresh обновляет все видимые секции.
  ///
  /// Последовательно, а не параллельно: так ведёт себя и сам
  /// RefreshIndicator, и модулю не нужно предполагать, что его
  /// onRefresh вызовут одновременно с чужой загрузкой.
  Future<void> _refreshSections(
    BuildContext context,
    ModuleManager manager,
  ) async {
    for (final section in _sectionsOf(manager)) {
      await section.onRefresh?.call();
    }
  }

  List<Widget> _buildSlivers(BuildContext context, List<HomeSection> sections) {
    return <Widget>[
      // ===== СЕКЦИИ МОДУЛЕЙ =====
      // Секция отдаёт готовый Column, поэтому каждый блок — один
      // SliverToBoxAdapter. Порядок задан модулями.
      for (final section in sections)
        SliverToBoxAdapter(child: section.builder(context)),

      // Просвет под плавающим доком: его высота + нижний отступ +
      // системный inset + 16 dp. Раньше здесь был просто 64 dp — меньше,
      // чем реальный док, и последняя карточка уезжала под навигацию.
      SliverToBoxAdapter(
        child: SizedBox(height: AppInsets.dockClearance(context).bottom),
      ),
    ];
  }
}
