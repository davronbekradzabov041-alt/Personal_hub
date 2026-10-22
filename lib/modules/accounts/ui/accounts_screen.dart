import 'package:flutter/material.dart';

import '../../../core/modules/module_manager_scope.dart';
import '../account_repository.dart';
import '../category_repository.dart';
import '../game_repository.dart';
import 'account_form_screen.dart';
import 'account_list_screen.dart';
import 'category_form_screen.dart';
import 'category_list_screen.dart';
import 'game_form_screen.dart';
import 'game_list_screen.dart';

/// Главный экран модуля Accounts с вкладками.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  AccountRepository? _accountRepository;
  CategoryRepository? _categoryRepository;
  GameRepository? _gameRepository;

  final ValueNotifier<int> _accountSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _categorySignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _gameSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ModuleManagerScope.of(context).apiFor(widget.moduleId);
    _accountRepository = AccountRepository(api.storage);
    _categoryRepository = CategoryRepository(api.storage);
    _gameRepository = GameRepository(
      api.storage,
      _accountRepository!,
      _categoryRepository!,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _accountSignal.dispose();
    _categorySignal.dispose();
    _gameSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountRepository = _accountRepository!;
    final categoryRepository = _categoryRepository!;
    final gameRepository = _gameRepository!;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            automaticallyImplyLeading: false,
            pinned: true,
            floating: true,
            snap: true,
            title: const Text('Аккаунты'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Аккаунты'),
                Tab(text: 'Игры'),
                Tab(text: 'Категории'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            AccountListView(
              key: ValueKey('accounts-$_accountSignal'),
              repository: accountRepository,
              refreshSignal: _accountSignal,
              onCreateRequested: _addAccount,
            ),
            GameListView(
              key: ValueKey('games-$_gameSignal'),
              repository: gameRepository,
              accountRepository: accountRepository,
              categoryRepository: categoryRepository,
              refreshSignal: _gameSignal,
              onCreateRequested: _addGame,
            ),
            CategoryListView(
              key: ValueKey('categories-$_categorySignal'),
              repository: categoryRepository,
              gameRepository: gameRepository,
              refreshSignal: _categorySignal,
              onCreateRequested: _addCategory,
            ),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          switch (_tabController.index) {
            case 0:
              return FloatingActionButton(
                onPressed: _addAccount,
                tooltip: 'Создать аккаунт',
                child: const Icon(Icons.add),
              );
            case 1:
              return FloatingActionButton(
                onPressed: _addGame,
                tooltip: 'Добавить игру',
                child: const Icon(Icons.add),
              );
            case 2:
              return FloatingActionButton(
                onPressed: _addCategory,
                tooltip: 'Создать категорию',
                child: const Icon(Icons.add),
              );
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Future<void> _addAccount() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountFormScreen(
          repository: _accountRepository!,
        ),
      ),
    );
    if (created == true) _accountSignal.value++;
  }

  Future<void> _addGame() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GameFormScreen(
          repository: _gameRepository!,
          accountRepository: _accountRepository!,
          categoryRepository: _categoryRepository!,
        ),
      ),
    );
    if (created == true) _gameSignal.value++;
  }

  Future<void> _addCategory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(
          repository: _categoryRepository!,
        ),
      ),
    );
    if (created == true) _categorySignal.value++;
  }
}