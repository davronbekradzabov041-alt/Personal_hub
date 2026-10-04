import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../schedule_category_repository.dart';
import 'category_form_screen.dart';
import 'category_visuals.dart';

/// Список категорий: создание, редактирование, удаление, порядок.
///
/// Отдельный виджет, а не экран, потому что список нужен в двух местах:
/// третьей вкладкой `ScheduleScreen` и маршрутом из формы события.
/// Экранная обёртка [CategoryListScreen] добавляет к нему AppBar и кнопку
/// создания — дублей кода и двух правд о том, как выглядит список, не
/// появляется.
///
/// Обновление — то же, что у вкладок расписания: чтение из хранилища по
/// [setState]. Нового состояния, кэша или шины событий не заводится, и
/// [refreshSignal] — тот же приём, что у `ScheduleHomeSection`: значение
/// меняется, список перечитывает хранилище.
class CategoryListView extends StatefulWidget {
  const CategoryListView({
    super.key,
    required this.repository,
    this.refreshSignal,
    this.onCreateRequested,
  });

  final ScheduleCategoryRepository repository;

  /// Меняется, когда категории изменили СНАРУЖИ списка (например, создали
  /// кнопкой на экране). null — список перечитывает себя сам.
  final ValueNotifier<int>? refreshSignal;

  /// Кнопка создания в пустом состоянии: вкладка зовёт вверх, где FAB
  /// уже есть. null — рисуем кнопку внутри списка.
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
      // Сигнал может прийти в момент, когда список уже снят с дерева.
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

  /// Удаление с подтверждением, в котором назван реальный счётчик
  /// затронутых событий.
  ///
  /// Счётчик берётся у репозитория
  /// ([ScheduleCategoryRepository.countLinkedEvents]), а не считается в
  /// UI: единственное правило «связано ли событие с категорией» живёт
  /// там, иначе диалог показал бы «не используется ни одним событием»
  /// под категорией, удаление которой всё-таки снимет ссылку.
  Future<void> _confirmDelete(Category category) async {
    final count = await widget.repository.countLinkedEvents(category.id);
    if (!mounted) return;

    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить категорию?'),
      content: Text(
        count == 0
            ? 'Категория «${category.name}» не используется ни одним событием.'
            : 'У $count ${_eventsWord(count)} снимется категория '
                '«${category.name}». События останутся на своих местах, '
                'но станут без категории.',
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
    _reload();
  }

  /// Существительное в родительном падеже для «У N … снимется
  /// категория»: 21 → «события», всё остальное → «событий».
  ///
  /// Именно родительный, а не предложный («У 2 событиях» — ошибка):
  /// сказуемое здесь «снимется», то есть падеж определяет глагол, а не
  /// предлог «у».
  static String _eventsWord(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'событий';
    return count % 10 == 1 ? 'события' : 'событий';
  }

  /// Сохраняет новый порядок после перетаскивания.
  ///
  /// [newIndex] уже приходит «после удаления» (onReorderItem именно для
  /// этого и отличается от устаревшего onReorder), поэтому индексы
  /// корректируются как в `List.insert`.
  ///
  /// Список сразу показывает перестановку, а расхождение с хранилищем
  /// исправляется [ScheduleCategoryRepository.reorder]. Отказ репозитория
  /// (он требует перечисления ВСЕХ категорий) возвращает список к
  /// данным из хранилища и объясняет причину — иначе на экране остался
  /// бы порядок, которого нигде нет.
  Future<void> _applyOrder(
    List<Category> categories,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<Category>.of(categories);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));

    // Блок, а не стрелка: `setState(() => _future = ...)` возвращал бы
    // из колбэка Future, а Flutter такой setState отвергает — перестановка
    // молча терялась бы вместе с записью в хранилище.
    setState(() {
      _future = Future<List<Category>>.value(reordered);
    });

    try {
      await widget.repository.reorder(<String>[
        for (final category in reordered) category.id,
      ]);
    } on ScheduleCategoryException catch (error) {
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
            subtitle: 'Категории группируют события и задают их вид',
            action: AppComponents.filledButton(
              onPressed: widget.onCreateRequested ?? () => _openForm(),
              leadingIcon: Icons.add,
              child: const Text('Создать категорию'),
            ),
          );
        }

        return ReorderableListView.builder(
          padding: AppInsets.md,
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
                    categoryIconOf(category.iconKey),
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

/// Экранная обёртка списка категорий — для открытия из формы события.
class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({super.key, required this.repository});

  final ScheduleCategoryRepository repository;

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  /// Счётчик изменений, сделанных кнопкой создания. Тот же механизм
  /// сигнала, что у Home-секции: список живёт в своём State, а родитель
  /// не имеет к нему доступа и не должен получать его через GlobalKey.
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
        refreshSignal: _createdSignal,
      ),
    );
  }
}