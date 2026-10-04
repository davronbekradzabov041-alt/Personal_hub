import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../models/schedule_event.dart';
import '../schedule_repository.dart';

/// Экран создания/редактирования события. Если [existing] == null —
/// создание нового; иначе — редактирование (и доступна кнопка «Удалить»).
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({
    super.key,
    required this.repository,
    this.existing,
    this.initialDate,
  });

  final ScheduleRepository repository;
  final ScheduleEvent? existing;

  /// Дата по умолчанию для НОВОГО события (например, выбранный день
  /// в «Календаре»). Игнорируется при редактировании существующего.
  final DateTime? initialDate;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late final TextEditingController _noteController;

  late DateTime _date;
  late int _startMinutes;
  late int _endMinutes;
  late EventPriority _priority;
  late EventStatus _status;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _categoryController = TextEditingController(text: e?.category ?? '');
    _noteController = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? widget.initialDate ?? DateTime.now();
    _startMinutes = e?.startMinutes ?? 9 * 60;
    _endMinutes = e?.endMinutes ?? 10 * 60;
    _priority = e?.priority ?? EventPriority.medium;
    _status = e?.status ?? EventStatus.planned;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
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
      category: _categoryController.text.trim(),
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
        padding: AppInsets.md,
        children: [
          AppComponents.textField(
            controller: _titleController,
            labelText: 'Название',
          ),
          SizedBox(height: AppSpacing.md),
          AppComponents.textField(
            controller: _categoryController,
            labelText: 'Категория',
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
