import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/account.dart';
import '../account_repository.dart';
import 'account_form_screen.dart';
import 'accounts_visuals.dart';

/// Список аккаунтов: создание, редактирование, удаление.
class AccountListView extends StatefulWidget {
  const AccountListView({
    super.key,
    required this.repository,
    this.refreshSignal,
    this.onCreateRequested,
  });

  final AccountRepository repository;

  /// Меняется, когда аккаунты изменили СНАРУЖИ списка.
  final ValueNotifier<int>? refreshSignal;

  /// Кнопка создания в пустом состоянии.
  final VoidCallback? onCreateRequested;

  @override
  State<AccountListView> createState() => _AccountListViewState();
}

class _AccountListViewState extends State<AccountListView> {
  late Future<List<Account>> _future;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant AccountListView oldWidget) {
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

  Future<void> _openForm({Account? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountFormScreen(
          repository: widget.repository,
          existing: existing,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _confirmDelete(Account account) async {
    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить аккаунт?'),
      content: Text(
        'Аккаунт «${account.name}» и все принадлежащие ему игры будут удалены безвозвратно.',
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

    await widget.repository.delete(account.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Account>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return AppComponents.loadingIndicator();

        final accounts = snapshot.data!;
        if (accounts.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.account_circle_outlined,
            title: 'Аккаунтов пока нет',
            subtitle: 'Добавьте первый аккаунт, чтобы начать вести библиотеку игр',
            action: AppComponents.filledButton(
              onPressed: widget.onCreateRequested ?? () => _openForm(),
              leadingIcon: Icons.add,
              child: const Text('Создать аккаунт'),
            ),
          );
        }

        return ListView.builder(
          padding: AppInsets.screenBody(context),
          itemCount: accounts.length,
          itemBuilder: (context, index) {
            final account = accounts[index];
            return Padding(
              key: ValueKey<String>('account-${account.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppComponents.card(
                onTap: () => _openForm(existing: account),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    accountIconOf(account.iconKey),
                    color: Color(account.colorValue),
                    size: 32,
                  ),
                  title: Text(account.name),
                  subtitle: Text('${account.type.label} · ${account.note.isEmpty ? 'без заметки' : account.note}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Удалить аккаунт',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(account),
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

/// Экранная обёртка списка аккаунтов.
class AccountListScreen extends StatefulWidget {
  const AccountListScreen({super.key, required this.repository});

  final AccountRepository repository;

  @override
  State<AccountListScreen> createState() => _AccountListScreenState();
}

class _AccountListScreenState extends State<AccountListScreen> {
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
        title: const Text('Аккаунты'),
        actions: [
          IconButton(
            tooltip: 'Создать аккаунт',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AccountFormScreen(
                    repository: widget.repository,
                  ),
                ),
              );
              if (created == true) _createdSignal.value++;
            },
          ),
        ],
      ),
      body: AccountListView(
        repository: widget.repository,
        refreshSignal: _createdSignal,
      ),
    );
  }
}