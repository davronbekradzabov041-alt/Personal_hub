import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../category_repository.dart';
import '../game_repository.dart';
import 'category_form_screen.dart';
import 'accounts_visuals.dart';

/// Список категорий: создание, редактирование, удаление, порядок.
class CategoryListView extends StatefulWidget {
  const CategoryListView({
    super.key,
    required this.repository,
    required this.gameRepository,
    this.refreshSignal,
    this.onCreateRequested,
  });

  final CategoryRepository repository;
  final GameRepository gameRepository;

  /// Меняется, когда категории изменили СНАРУЖИ списка.
  final ValueNotifier<int>? refreshSignal;

  /// Кнопка создания в пустом состоянии.
  final VoidCallback? onCreateRequested;

  @override
  State<CategoryListView> createState() => _CategoryListViewState();
}

class _CategoryListViewState extends State<CategoryListView> {
  late Future<List<Category>> _future;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant CategoryListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.refreshSignal, widget.refreshSignal)) return;
    oldWidget.refreshSignal?.removeListener(_reload);
    widget.refreshSignal?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) {
      _future = widget.repository.getAll();
      return;
    }
    setState(_reloadFuture);
  }

  void _reloadFuture() {
    _future = widget.repository.getAll();
  }

  Future<void> _openForm({Category? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(
          repository: widget.repository,
          existing: existing,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _confirmDelete(Category category) async {
    // Игры, которым снимется категория: считает репозиторий, а не UI.
    final games = await widget.gameRepository.getByCategory(category.id);
    if (!mounted) return;

    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить категорию?'),
      content: Text(
        games.isEmpty
            ? 'Категория «${category.name}» не используется ни одной игрой.'
            : 'У ${games.length} ${_gamesWord(games.length)} снимется категория '
                '«${category.name}». Игры останутся на своих местах, '
                'но станут без этой категории.',
      ),
      actionsBuilder: (dialogContext) => [
        AppComponents.textButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        AppComponents.filledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Удалить'),
        ),
      ],
    );
    if (confirmed != true) return;

    await widget.repository.delete(category.id);
    // Отвязываем категорию от всех игр
    await widget.gameRepository.detachCategory(category.id);
    _reload();
  }

  static String _gamesWord(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'игр';
    return count % 10 == 1 ? 'игра' : 'игр';
  }

  Future<void> _applyOrder(
    List<Category> categories,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<Category>.of(categories);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));

    setState(() {
      _future = Future<List<Category>>.value(reordered);
    });

    try {
      await widget.repository.reorder(<String>[
        for (final category in reordered) category.id,
      ]);
    } on CategoryRepositoryException catch (error) {
      if (!mounted) return;
      _reload();
      AppComponents.showSnackBar(context: context, message: error.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return AppComponents.loadingIndicator();

        final categories = snapshot.data!;
        if (categories.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.category_outlined,
            title: 'Категорий пока нет',
            subtitle: 'Категории группируют игры и задают их вид',
            action: AppComponents.filledButton(
              onPressed: widget.onCreateRequested ?? () => _openForm(),
              leadingIcon: Icons.add,
              child: const Text('Создать категорию'),
            ),
          );
        }

        return ReorderableListView.builder(
          padding: AppInsets.screenBody(context),
          itemCount: categories.length,
          onReorderItem: (oldIndex, newIndex) =>
              _applyOrder(categories, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Padding(
              key: ValueKey<String>('category-${category.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppComponents.card(
                onTap: () => _openForm(existing: category),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    accountsCategoryIconOf(category.iconKey),
                    color: Color(category.colorValue),
                  ),
                  title: Text(category.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Удалить категорию',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(category),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.xs),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Экранная обёртка списка категорий.
class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({
    super.key,
    required this.repository,
    required this.gameRepository,
  });

  final CategoryRepository repository;
  final GameRepository gameRepository;

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  final ValueNotifier<int> _createdSignal = ValueNotifier<int>(0);

  @override
  void dispose() {
    _createdSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Категории'),
        actions: [
          IconButton(
            tooltip: 'Создать категорию',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => CategoryFormScreen(
                    repository: widget.repository,
                  ),
                ),
              );
              if (created == true) _createdSignal.value++;
            },
          ),
        ],
      ),
      body: CategoryListView(
        repository: widget.repository,
        gameRepository: widget.gameRepository,
        refreshSignal: _createdSignal,
      ),
    );
  }
}