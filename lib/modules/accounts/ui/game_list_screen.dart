import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/game_profile.dart';
import '../models/category.dart';
import '../account_repository.dart';
import '../category_repository.dart';
import '../game_repository.dart';
import 'game_form_screen.dart';

/// Список игр: создание, редактирование, удаление.
class GameListView extends StatefulWidget {
  const GameListView({
    super.key,
    required this.repository,
    required this.accountRepository,
    required this.categoryRepository,
    this.accountId,
    this.refreshSignal,
    this.onCreateRequested,
  });

  final GameRepository repository;
  final AccountRepository accountRepository;
  final CategoryRepository categoryRepository;

  /// Если задан — показываем игры только этого аккаунта.
  final String? accountId;

  /// Меняется, когда игры изменили СНАРУЖИ списка.
  final ValueNotifier<int>? refreshSignal;

  /// Кнопка создания в пустом состоянии.
  final VoidCallback? onCreateRequested;

  @override
  State<GameListView> createState() => _GameListViewState();
}

class _GameListViewState extends State<GameListView> {
  late Future<List<GameProfile>> _future;
  late Future<List<Category>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant GameListView oldWidget) {
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
      _future = _loadGames();
      _categoriesFuture = widget.categoryRepository.getAll();
      return;
    }
    setState(_reloadFuture);
  }

  void _reloadFuture() {
    _future = _loadGames();
    _categoriesFuture = widget.categoryRepository.getAll();
  }

  Future<List<GameProfile>> _loadGames() async {
    if (widget.accountId != null) {
      return widget.repository.getByAccount(widget.accountId!);
    }
    return widget.repository.getAll();
  }

  Future<void> _openForm({GameProfile? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GameFormScreen(
          repository: widget.repository,
          accountRepository: widget.accountRepository,
          categoryRepository: widget.categoryRepository,
          existing: existing,
          initialAccountId: widget.accountId,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _confirmDelete(GameProfile game) async {
    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить игру?'),
      content: Text('«${game.title}» будет удалена безвозвратно.'),
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

    await widget.repository.delete(game.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GameProfile>>(
      future: _future,
      builder: (context, gamesSnapshot) {
        if (!gamesSnapshot.hasData) {
          return AppComponents.loadingIndicator();
        }

        return FutureBuilder<List<Category>>(
          future: _categoriesFuture,
          builder: (context, categoriesSnapshot) {
            if (!categoriesSnapshot.hasData) {
              return AppComponents.loadingIndicator();
            }

            final games = gamesSnapshot.data!;
            final categories = categoriesSnapshot.data!;
            final categoryById = <String, Category>{
              for (final c in categories) c.id: c,
            };

            if (games.isEmpty) {
              return AppComponents.emptyState(
                context: context,
                icon: Icons.videogame_asset_outlined,
                title: widget.accountId != null
                    ? 'У этого аккаунта игр пока нет'
                    : 'Игр пока нет',
                subtitle: 'Добавьте первую игру, чтобы начать библиотеку',
                action: AppComponents.filledButton(
                  onPressed: widget.onCreateRequested ?? () => _openForm(),
                  leadingIcon: Icons.add,
                  child: const Text('Добавить игру'),
                ),
              );
            }

            return ListView.builder(
              padding: AppInsets.screenBody(context),
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                final names = <String>[];
                for (final id in game.categoryIds) {
                  final category = categoryById[id];
                  if (category != null) names.add(category.name);
                }
                final categoryNames = names.join(', ');

                return Padding(
                  key: ValueKey<String>('game-${game.id}'),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppComponents.card(
                    onTap: () => _openForm(existing: game),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.videogame_asset_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                      title: Text(game.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${game.platform.label} · ${game.status.label}'),
                          if (categoryNames.isNotEmpty)
                            Text(
                              'Категории: $categoryNames',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Удалить игру',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(game),
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
      },
    );
  }
}

/// Экранная обёртка списка игр.
class GameListScreen extends StatefulWidget {
  const GameListScreen({
    super.key,
    required this.repository,
    required this.accountRepository,
    required this.categoryRepository,
    this.accountId,
  });

  final GameRepository repository;
  final AccountRepository accountRepository;
  final CategoryRepository categoryRepository;

  /// Если задан — показываем игры только этого аккаунта.
  final String? accountId;

  @override
  State<GameListScreen> createState() => _GameListScreenState();
}

class _GameListScreenState extends State<GameListScreen> {
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
        title: const Text('Игры'),
        actions: [
          IconButton(
            tooltip: 'Добавить игру',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => GameFormScreen(
                    repository: widget.repository,
                    accountRepository: widget.accountRepository,
                    categoryRepository: widget.categoryRepository,
                    initialAccountId: widget.accountId,
                  ),
                ),
              );
              if (created == true) _createdSignal.value++;
            },
          ),
        ],
      ),
      body: GameListView(
        repository: widget.repository,
        accountRepository: widget.accountRepository,
        categoryRepository: widget.categoryRepository,
        accountId: widget.accountId,
        refreshSignal: _createdSignal,
      ),
    );
  }
}
