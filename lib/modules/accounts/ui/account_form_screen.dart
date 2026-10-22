import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/account.dart';
import 'accounts_visuals.dart';
import '../account_repository.dart';

/// Форма создания/редактирования аккаунта.
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    required this.repository,
    this.existing,
  });

  final AccountRepository repository;

  /// null — создание, иначе редактирование.
  final Account? existing;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late AccountType _type;
  late int _colorValue;
  late String _iconKey;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _type = existing?.type ?? AccountType.steam;
    _colorValue = existing?.colorValue ?? accountPalette.first;
    _iconKey = existing?.iconKey ?? Account.defaultIconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Сохраняет аккаунт.
  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final note = _noteController.text.trim();

    try {
      if (_isEditing) {
        await widget.repository.update(
          id: widget.existing!.id,
          name: name,
          type: _type,
          iconKey: _iconKey,
          colorValue: _colorValue,
          note: note,
        );
      } else {
        await widget.repository.create(
          name: name,
          type: _type,
          iconKey: _iconKey,
          colorValue: _colorValue,
          note: note,
        );
      }
    } on AccountRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(context: context, message: error.reason);
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(
        context: context,
        message: 'Не удалось сохранить аккаунт',
      );
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Аккаунт' : 'Новый аккаунт')),
      body: ListView(
        padding: AppInsets.screenBody(context),
        children: [
          // Превью: пользователь видит результат до сохранения.
          AppComponents.card(
            child: Padding(
              padding: AppInsets.screenBody(context),
              child: Row(
                children: [
                  Icon(
                    accountIconOf(_iconKey),
                    color: Color(_colorValue),
                    size: 32,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _nameOrHint,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppComponents.textField(
            controller: _nameController,
            labelText: 'Имя',
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Тип', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _TypeSelector(
            selected: _type,
            onSelected: (type) => setState(() => _type = type),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Цвет', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _AccountColorPicker(
            selected: _colorValue,
            onSelected: (value) => setState(() => _colorValue = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Иконка', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _AccountIconPicker(
            selectedKey: _iconKey,
            onSelected: (key) => setState(() => _iconKey = key),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppComponents.textField(
            controller: _noteController,
            labelText: 'Заметка',
            maxLines: 3,
            textInputAction: TextInputAction.done,
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

  String get _nameOrHint {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Без названия' : name;
  }
}

/// Выбор типа аккаунта.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onSelected,
  });

  final AccountType selected;
  final ValueChanged<AccountType> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const types = AccountType.values;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: types.map((type) {
        final isSelected = type == selected;
        return FilterChip(
          selected: isSelected,
          onSelected: (_) => onSelected(type),
          label: Text(type.label),
          avatar: Icon(
            accountIcons[type.name]!,
            size: 18,
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          selectedColor: theme.colorScheme.primaryContainer,
          showCheckmark: false,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.full,
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: isSelected ? AppBorders.medium : AppBorders.thin,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Выбор цвета из [accountPalette].
class _AccountColorPicker extends StatelessWidget {
  const _AccountColorPicker({
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: accountPalette.map((colorValue) {
        final isSelected = colorValue == selected;
        return Semantics(
          label: 'Цвет ${colorValue.toRadixString(16).substring(2)}',
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: () => onSelected(colorValue),
            borderRadius: BorderRadius.circular(AppSpacing.fabMiniSize / 2),
            child: Container(
              width: AppSpacing.fabMiniSize,
              height: AppSpacing.fabMiniSize,
              decoration: BoxDecoration(
                color: Color(colorValue),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outlineVariant,
                  width: isSelected ? AppBorders.medium : AppBorders.thin,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Выбор иконки из каталога [accountIcons].
class _AccountIconPicker extends StatelessWidget {
  const _AccountIconPicker({
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = accountIcons.keys.toList();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: keys.map((key) {
        final isSelected = key == selectedKey;
        return Semantics(
          label: 'Иконка $key',
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: () => onSelected(key),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: Container(
              width: AppSpacing.fabMiniSize,
              height: AppSpacing.fabMiniSize,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: isSelected ? AppBorders.medium : AppBorders.thin,
                ),
              ),
              child: Icon(
                accountIcons[key],
                size: 20,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}