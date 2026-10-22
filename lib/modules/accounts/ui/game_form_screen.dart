import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/game_profile.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../account_repository.dart';
import '../category_repository.dart';
import '../game_repository.dart';
import 'accounts_visuals.dart';
import 'account_form_screen.dart';
import 'category_list_screen.dart';

/// Экран создания/редактирования игры.
class GameFormScreen extends StatefulWidget {
  const GameFormScreen({
    super.key,
    required this.repository,
    required this.accountRepository,
    required this.categoryRepository,
    this.existing,
    this.initialAccountId,
  });

  final GameRepository repository;
  final AccountRepository accountRepository;
  final CategoryRepository categoryRepository;

  /// null — создание, иначе редактирование.
  final GameProfile? existing;

  /// Предвыбранный аккаунт для новой игры (например, из экрана аккаунта).
  final String? initialAccountId;

  @override
  State<GameFormScreen> createState() => _GameFormScreenState();
}

class _GameFormScreenState extends State<GameFormScreen> {
  static const String noCategoryChoice = 'no-category-choice';
  static const String manageCategoriesChoice = 'manage-categories-choice';

  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late GamePlatform _platform;
  late GameStatus _status;
  late int _playtimeMinutes;
  DateTime? _startedAt;
  DateTime? _completedAt;
  String? _region;

  String? _accountId;
  List<String> _categoryIds = const <String>[];

  List<Account> _accounts = const <Account>[];
  List<Category> _categories = const <Category>[];

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _platform = existing?.platform ?? GamePlatform.steam;
    _status = existing?.status ?? GameStatus.backlog;
    _playtimeMinutes = existing?.playtimeMinutes ?? 0;
    _startedAt = existing?.startedAt;
    _completedAt = existing?.completedAt;
    _region = existing?.region;
    _accountId = existing?.accountId ?? widget.initialAccountId;
    _categoryIds = existing?.categoryIds ?? const <String>[];
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final accounts = await widget.accountRepository.getAll();
    final categories = await widget.categoryRepository.getAll();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;

      // Аккаунт могли удалить, пока форма была открыта.
      if (_accountId != null &&
          !accounts.any((a) => a.id == _accountId)) {
        _accountId = accounts.isNotEmpty ? accounts.first.id : null;
      }

      // Новая игра без указанного аккаунта: подставляем первый.
      //
      // Без этого форма открывалась с «Выберите аккаунт», и при
      // единственном аккаунте пользователь был обязан тапнуть поле и
      // выбрать его заново — лишняя операция. Явно заданный аккаунт
      // (initialAccountId) и аккаунт существующей игры не перебиваются.
      if (_accountId == null && !_isEditing && accounts.isNotEmpty) {
        _accountId = accounts.first.id;
      }

      // Категории могли удалить.
      _categoryIds = _categoryIds
          .where((id) => categories.any((c) => c.id == id))
          .toList();
    });
  }

  Future<void> _pickAccount() async {
    final navigator = Navigator.of(context);

    final selected = await AppComponents.showBottomSheet<String>(
      context: context,
      title: 'Аккаунт',
      child: Builder(
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          children: [
            for (final account in _accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  accountIconOf(account.iconKey),
                  color: Color(account.colorValue),
                ),
                title: Text(account.name),
                subtitle: Text(account.type.label),
                selected: account.id == _accountId,
                onTap: () => Navigator.of(sheetContext).pop(account.id),
              ),
            const Divider(height: AppSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add),
              title: const Text('Новый аккаунт'),
              onTap: () async {
                Navigator.of(sheetContext).pop('new-account');
              },
            ),
          ],
        ),
      ),
    );

    if (selected == 'new-account') {
      await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => AccountFormScreen(
            repository: widget.accountRepository,
          ),
        ),
      );
      await _loadData();
      return;
    }
    if (!mounted || selected == null) return;

    setState(() => _accountId = selected);
  }

  Future<void> _pickCategories() async {
    final navigator = Navigator.of(context);

    final selected = await AppComponents.showBottomSheet<String>(
      context: context,
      title: 'Категории',
      child: Builder(
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          children: [
            _CategoryOption(
              name: ResolvedGameCategory.none.name,
              icon: ResolvedGameCategory.none.icon,
              selected: _categoryIds.isEmpty,
              onTap: () => Navigator.of(sheetContext).pop(noCategoryChoice),
            ),
            for (final category in _categories)
              _CategoryOption(
                name: category.name,
                icon: accountsCategoryIconOf(category.iconKey),
                color: Color(category.colorValue),
                selected: _categoryIds.contains(category.id),
                onTap: () => Navigator.of(sheetContext).pop(category.id),
              ),
            const Divider(height: AppSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: const Text('Управление категориями'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(manageCategoriesChoice),
            ),
          ],
        ),
      ),
    );

    if (selected == manageCategoriesChoice) {
      await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => CategoryListScreen(
            repository: widget.categoryRepository,
            gameRepository: widget.repository,
          ),
        ),
      );

      await _loadData();
      return;
    }
    if (!mounted || selected == null) return;

    setState(() {
      if (selected == noCategoryChoice) {
        _categoryIds.clear();
      } else {
        // Toggle selection
        if (_categoryIds.contains(selected)) {
          _categoryIds.remove(selected);
        } else {
          _categoryIds.add(selected);
        }
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startedAt ?? DateTime.now() : _completedAt ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startedAt = picked;
      } else {
        _completedAt = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Название не может быть пустым');
      return;
    }
    if (_accountId == null) {
      _showMessage('Выберите аккаунт');
      return;
    }

    setState(() => _saving = true);

    try {
      if (_isEditing) {
        await widget.repository.update(
          id: widget.existing!.id,
          accountId: _accountId,
          title: title,
          platform: _platform,
          region: _region,
          status: _status,
          playtimeMinutes: _playtimeMinutes,
          startedAt: _startedAt,
          completedAt: _completedAt,
          categoryIds: _categoryIds,
          note: _noteController.text.trim(),
        );
      } else {
        await widget.repository.create(
          accountId: _accountId!,
          title: title,
          platform: _platform,
          region: _region,
          status: _status,
          playtimeMinutes: _playtimeMinutes,
          startedAt: _startedAt,
          completedAt: _completedAt,
          categoryIds: _categoryIds,
          note: _noteController.text.trim(),
        );
      }
    } on GameRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(context: context, message: error.reason);
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(
        context: context,
        message: 'Не удалось сохранить игру',
      );
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final title = widget.existing!.title;
    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить игру?'),
      content: Text('«$title» будет удалена безвозвратно.'),
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

    await widget.repository.delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _showMessage(String message) {
    AppComponents.showSnackBar(context: context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    final account = _accountId != null
        ? _accounts.firstWhere(
            (a) => a.id == _accountId,
            orElse: () => _accounts.first,
          )
        : null;
    final resolvedCategories = GameCategoryResolver.of(_categories).resolveAll(
      GameProfile(
        id: '',
        accountId: _accountId ?? '',
        title: '',
        platform: _platform,
        status: _status,
        playtimeMinutes: _playtimeMinutes,
        categoryIds: _categoryIds,
        note: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Игра' : 'Новая игра'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Удалить',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: AppInsets.screenBody(context),
        children: [
          AppComponents.textField(
            controller: _titleController,
            labelText: 'Название',
          ),
          const SizedBox(height: AppSpacing.lg),
          // Аккаунт
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: account != null
                ? Icon(
                    accountIconOf(account.iconKey),
                    color: Color(account.colorValue),
                  )
                : const Icon(Icons.account_circle_outlined),
            title: const Text('Аккаунт'),
            subtitle: Text(account?.name ?? 'Выберите аккаунт'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickAccount,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Платформа
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Платформа'),
            subtitle: Text(_platform.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickPlatform,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Регион
          AppComponents.textField(
            controller: TextEditingController(text: _region ?? ''),
            labelText: 'Регион (опционально)',
            onChanged: (value) => setState(() => _region = value.trim().isEmpty ? null : value.trim()),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Статус
          Text('Статус', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<GameStatus>(
            segments: const [
              ButtonSegment(value: GameStatus.backlog, label: Text('В планах')),
              ButtonSegment(value: GameStatus.playing, label: Text('Играю')),
              ButtonSegment(value: GameStatus.completed, label: Text('Пройдено')),
              ButtonSegment(value: GameStatus.dropped, label: Text('Брошено')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Время игры
          Text('Время игры (минуты)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            initialValue: _playtimeMinutes.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) setState(() => _playtimeMinutes = parsed);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          // Даты
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Начато'),
            subtitle: Text(_startedAt != null
                ? '${_startedAt!.day}.${_startedAt!.month}.${_startedAt!.year}'
                : 'Не указано'),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Завершено'),
            subtitle: Text(_completedAt != null
                ? '${_completedAt!.day}.${_completedAt!.month}.${_completedAt!.year}'
                : 'Не указано'),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _pickDate(isStart: false),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Категории
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              resolvedCategories.first.icon,
              color: resolvedCategories.first.hasAppearance
                  ? Color(resolvedCategories.first.colorValue!)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: const Text('Категории'),
            subtitle: Text(resolvedCategories.map((c) => c.name).join(', ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCategories,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppComponents.textField(
            controller: _noteController,
            labelText: 'Заметка',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppComponents.filledButton(
            onPressed: _saving ? null : _save,
            isLoading: _saving,
            child: Text(_isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPlatform() async {
    final selected = await AppComponents.showBottomSheet<GamePlatform>(
      context: context,
      title: 'Платформа',
      child: Builder(
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          children: [
            for (final platform in GamePlatform.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(platform.label),
                selected: platform == _platform,
                onTap: () => Navigator.of(sheetContext).pop(platform),
              ),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;
    setState(() => _platform = selected);
  }
}

/// Строка выбора категории в листе.
class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color ?? theme.colorScheme.onSurfaceVariant),
      title: Text(name),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}