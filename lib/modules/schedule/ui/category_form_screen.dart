import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../schedule_category_repository.dart';
import 'category_visuals.dart';

/// Форма создания/редактирования категории: имя, цвет, иконка.
///
/// Отдельный экран, а не диалог: выбор цвета и иконки требует места,
/// которого в AlertDialog не бывает, а появление категории — обычное
/// действие пользователя, достойное своей кнопки «Назад».
class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({
    super.key,
    required this.repository,
    this.existing,
  });

  final ScheduleCategoryRepository repository;

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
    _colorValue = existing?.colorValue ?? categoryPalette.first;
    _iconKey = existing?.iconKey ?? categoryIcons.keys.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Сохраняет категорию.
  ///
  /// Ошибки домена (`ScheduleCategoryException` — пустое имя, дубль)
  /// показываются пользователю и оставляют форму открытой: потерять
  /// уже введённое имя из-за дубля было бы наказанием за ошибку.
  /// Исключение наружу не пробрасывается — экран не должен падать.
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
          colorValue: _colorValue,
          iconKey: _iconKey,
        );
      } else {
        await widget.repository.create(
          name: name,
          colorValue: _colorValue,
          iconKey: _iconKey,
        );
      }
    } on ScheduleCategoryException catch (error) {
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
          // Превью: пользователь видит результат до сохранения, а не
          // после — иначе первый заход в список был бы сюрпризом.
          AppComponents.card(
            child: Padding(
              padding: AppInsets.screenBody(context),
              child: Row(
                children: [
                  Icon(
                    categoryIconOf(_iconKey),
                    color: Color(_colorValue),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      nameOrHint,
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
          _ColorPicker(
            selected: _colorValue,
            onSelected: (value) => setState(() => _colorValue = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Иконка', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _IconPicker(
            selectedKey: _iconKey,
            onSelected: (key) => setState(() => _iconKey = key),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppComponents.filledButton(
            onPressed: _save,
            isLoading: _saving,
            child: Text(_isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }

  /// Подпись в превью: пока имя не введено, показывается приглашение,
  /// чтобы пустой экран не выглядел сломанным.
  String get nameOrHint {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Без названия' : name;
  }
}

/// Выбор цвета из [categoryPalette].
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: categoryPalette.map((colorValue) {
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
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.outlineVariant,
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

/// Выбор иконки из каталога [categoryIcons].
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Каталог — Map, а порядок нужен пользователю: иначе при каждой
    // сборке иконки прыгали бы произвольно.
    final keys = categoryIcons.keys.toList();

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
                categoryIcons[key],
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