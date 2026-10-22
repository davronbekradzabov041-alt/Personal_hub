import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/category.dart';
import '../models/schedule_event.dart';
import '../schedule_category_repository.dart';
import '../schedule_repository.dart';
import 'category_list_view.dart';
import 'category_visuals.dart';

/// Экран создания/редактирования события. Если [existing] == null —
/// создание нового; иначе — редактирование (и доступна кнопка «Удалить»).
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({
    super.key,
    required this.repository,
    required this.categoryRepository,
    this.existing,
    this.initialDate,
  });

  final ScheduleRepository repository;

  /// Отдельный репозиторий, а не свойство [repository]: категории и
  /// события лежат в одном хранилище, но принадлежат разным сущностям,
  /// и форма обязана видеть обе.
  final ScheduleCategoryRepository categoryRepository;

  final ScheduleEvent? existing;

  /// Дата по умолчанию для НОВОГО события (например, выбранный день
  /// в «Календаре»). Игнорируется при редактировании существующего.
  final DateTime? initialDate;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  /// Значения, которых не может быть у id категории: id — строка из
  /// микросекундного счётчика, а эти два — нет.
  ///
  /// Отдельные строки вместо `null`: результат листа выбора — `String?`,
  /// и `null` там уже занят закрытием без выбора. Если бы «без категории»
  /// тоже возвращала `null`, клик по ней не отличался бы от отмены, а
  /// снять категорию с события было бы нечем.
  static const String noCategoryChoice = 'no-category-choice';
  static const String manageCategoriesChoice = 'manage-categories-choice';

  late final TextEditingController _titleController;
  late final TextEditingController _noteController;

  late DateTime _date;
  late int _startMinutes;
  late int _endMinutes;
  late EventPriority _priority;
  late EventStatus _status;

  /// Выбранная категория; null — «без категории».
  ///
  /// Инициализируется по ссылке события, а не по его устаревшей строке:
  /// строка может устареть (категорию переименовали), и форма обязана
  /// показать то, на что событие ссылается СЕЙЧАС.
  String? _categoryId;

  List<Category> _categories = const <Category>[];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _noteController = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? widget.initialDate ?? DateTime.now();
    _startMinutes = e?.startMinutes ?? 9 * 60;
    _endMinutes = e?.endMinutes ?? 10 * 60;
    _priority = e?.priority ?? EventPriority.medium;
    _status = e?.status ?? EventStatus.planned;
    _categoryId = ScheduleEvent.readCategoryId(e?.categoryId);
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Читает категории из хранилища.
  ///
  /// Список маленький и меняется только действиями пользователя, поэтому
  /// держать его между правками нормально; перечитывается он при входе
  /// на экран и после похода в управление категориями.
  Future<void> _loadCategories() async {
    final categories = await widget.categoryRepository.getAll();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      // Категорию могли удалить, пока форма была открыта: ссылка на
      // неё больше не разрешается, и форма обязана это показать.
      if (_categoryId != null &&
          !categories.any((c) => c.id == _categoryId)) {
        _categoryId = null;
      }
    });
  }

  /// Текущая категория для показа.
  ///
  /// Считается ТЕМ ЖЕ правилом, что и в плитках событий, поиске и Home:
  /// [CategoryResolver]. Расхождение этих правил означало бы, что в
  /// форме у события «есть» категория, а в списке — «нет».
  ResolvedCategory get _resolved {
    final existing = widget.existing;
    if (existing != null) {
      return CategoryResolver.of(_categories)
          .resolve(existing.copyWith(categoryId: _categoryId));
    }

    // У нового события устаревшей строки ещё нет — показывать нечего,
    // кроме выбранной категории.
    for (final category in _categories) {
      if (category.id == _categoryId) {
        return ResolvedCategory.ofCategory(category);
      }
    }
    return ResolvedCategory.none;
  }

  Future<void> _pickCategory() async {
    // Navigator берётся ДО await: иначе обращение к context после
    // асинхронного разрыва требовало бы проверки mounted, а форма может
    // быть уже снята с дерева — и тогда ошибка пришла бы из чужого места.
    final navigator = Navigator.of(context);

    // context листа — из Builder'а самого листа: Navigator.of(context)
    // формы указывает на маршрут ПОД листом (та же ловушка, что в
    // _delete с actionsBuilder).
    final selected = await AppComponents.showBottomSheet<String>(
      context: context,
      title: 'Категория',
      child: Builder(
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          children: [
            _CategoryOption(
              name: ResolvedCategory.none.name,
              icon: ResolvedCategory.none.icon,
              selected: _categoryId == null,
              onTap: () => Navigator.of(sheetContext).pop(noCategoryChoice),
            ),
            for (final category in _categories)
              _CategoryOption(
                name: category.name,
                icon: categoryIconOf(category.iconKey),
                color: Color(category.colorValue),
                selected: category.id == _categoryId,
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
          ),
        ),
      );

      // Справочник перечитывается ВСЕГДА, а не по результату маршрута.
      // Экран можно уйти назад жестом, кнопкой AppBar и кнопкой системы —
      // и каждый путь обязан принести новые категории в форму. Согласовывать
      // все эти выходы через возвращаемое значение значило бы забыть один из
      // них; чтение маленького справочника из хранилища дешевле.
      await _loadCategories();
      return;
    }
    if (!mounted || selected == null) return;

    setState(() {
      _categoryId = selected == noCategoryChoice ? null : selected;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startMinutes : _endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMinutes = minutes;
      } else {
        _endMinutes = minutes;
      }
    });
  }

  /// Устаревшее имя выбранной категории.
  ///
  /// Пишется в событие ВСЕГДА и всегда в согласии со ссылкой: старые
  /// сборки читают только строку, а расхождение строки и ссылки — это
  /// ровно тот случай, который чинит ScheduleMigrator.
  String _legacyCategoryName() {
    for (final category in _categories) {
      if (category.id == _categoryId) return category.name;
    }
    return '';
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Название не может быть пустым');
      return;
    }
    if (_endMinutes <= _startMinutes) {
      _showMessage('Время окончания должно быть позже времени начала');
      return;
    }

    final event = ScheduleEvent(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      category: _legacyCategoryName(),
      categoryId: _categoryId,
      priority: _priority,
      date: _date,
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
      status: _status,
      note: _noteController.text.trim(),
    );

    if (_isEditing) {
      await widget.repository.update(event);
    } else {
      await widget.repository.add(event);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final title = widget.existing!.title;

    // Кнопки строятся через actionsBuilder, потому что им нужен
    // context самого диалога. Navigator.of(context) с context'ом
    // EventFormScreen закрыл бы сам экран, а не диалог: await ниже
    // вернул бы не 'true', а результат закрытия формы, и удаление
    // события происходило бы без подтверждения.
    final confirmed = await AppComponents.showAppDialog<bool>(
      context: context,
      title: const Text('Удалить событие?'),
      content: Text('«$title» будет удалено безвозвратно.'),
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
    final resolved = _resolved;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать событие' : 'Новое событие'),
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
          SizedBox(height: AppSpacing.lg),
          // Категория выбирается из справочника, а не вводится строкой.
          // Свободный текст здесь означал бы вторую правду о категории:
          // «Работа» и «работа» стали бы двумя разными категориями, а
          // переименование категории — невозможным.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              resolved.icon,
              color: resolved.hasAppearance
                  ? Color(resolved.colorValue!)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: const Text('Категория'),
            subtitle: Text(resolved.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCategory,
          ),
          SizedBox(height: AppSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Дата'),
            subtitle: Text(ScheduleEvent.formatDateKey(_date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Начало'),
            subtitle: Text(ScheduleEvent.formatMinutes(_startMinutes)),
            trailing: const Icon(Icons.schedule_outlined),
            onTap: () => _pickTime(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Окончание'),
            subtitle: Text(ScheduleEvent.formatMinutes(_endMinutes)),
            trailing: const Icon(Icons.schedule_outlined),
            onTap: () => _pickTime(isStart: false),
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Приоритет', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: AppSpacing.sm),
          SegmentedButton<EventPriority>(
            segments: const [
              ButtonSegment(value: EventPriority.low, label: Text('Низкий')),
              ButtonSegment(value: EventPriority.medium, label: Text('Средний')),
              ButtonSegment(value: EventPriority.high, label: Text('Высокий')),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Статус', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: AppSpacing.sm),
          SegmentedButton<EventStatus>(
            segments: const [
              ButtonSegment(value: EventStatus.planned, label: Text('Запланировано')),
              ButtonSegment(value: EventStatus.done, label: Text('Выполнено')),
              ButtonSegment(value: EventStatus.skipped, label: Text('Пропущено')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          SizedBox(height: AppSpacing.lg),
          AppComponents.textField(
            controller: _noteController,
            labelText: 'Заметка',
            maxLines: 3,
          ),
          SizedBox(height: AppSpacing.xl),
          AppComponents.filledButton(
            onPressed: _save,
            child: Text(_isEditing ? 'Сохранить' : 'Создать'),
          ),
        ],
      ),
    );
  }
}

/// Строка выбора категории в листе.
///
/// Своя строка на [ListTile], а не на `RadioListTile` и не на
/// `AppComponents.listItem`: у списка категорий есть цвет и иконка,
/// ради которых он и выбирается, а `AppComponents.listItem` печатает
/// заголовок через `toString()` и на Widget-иконке показал бы
/// «Text(Иконка(...))» вместо названия.
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