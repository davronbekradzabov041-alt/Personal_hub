import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../category_repository.dart';
import 'accounts_visuals.dart';

/// Форма создания/редактирования категории.
class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({
    super.key,
    required this.repository,
    this.existing,
  });

  final CategoryRepository repository;

  /// null — создание, иначе редактирование.
  final Category? existing;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  late final TextEditingController _nameController;
  late int _colorValue;
  late String _iconKey;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _colorValue = existing?.colorValue ?? accountsCategoryPalette.first;
    _iconKey = existing?.iconKey ?? Category.defaultIconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final existing = widget.existing;

    try {
      if (_isEditing) {
        await widget.repository.update(
          id: existing!.id,
          name: name,
          iconKey: _iconKey,
          colorValue: _colorValue,
        );
      } else {
        await widget.repository.create(
          name: name,
          iconKey: _iconKey,
          colorValue: _colorValue,
        );
      }
    } on CategoryRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(context: context, message: error.reason);
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppComponents.showSnackBar(
        context: context,
        message: 'Не удалось сохранить категорию',
      );
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Категория' : 'Новая категория')),
      body: ListView(
        padding: AppInsets.screenBody(context),
        children: [
          // Превью
          AppComponents.card(
            child: Padding(
              padding: AppInsets.screenBody(context),
              child: Row(
                children: [
                  Icon(
                    accountsCategoryIconOf(_iconKey),
                    color: Color(_colorValue),
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
            labelText: 'Название',
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Цвет', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _CategoryColorPicker(
            selected: _colorValue,
            onSelected: (value) => setState(() => _colorValue = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Иконка', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _CategoryIconPicker(
            selectedKey: _iconKey,
            onSelected: (key) => setState(() => _iconKey = key),
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

/// Выбор цвета из [accountsCategoryPalette].
class _CategoryColorPicker extends StatelessWidget {
  const _CategoryColorPicker({
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
      children: accountsCategoryPalette.map((colorValue) {
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

/// Выбор иконки из каталога [accountsCategoryIcons].
class _CategoryIconPicker extends StatelessWidget {
  const _CategoryIconPicker({
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = accountsCategoryIcons.keys.toList();

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
                accountsCategoryIcons[key],
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