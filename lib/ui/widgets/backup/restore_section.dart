/// Секция восстановления из backup-файла.
library restore_section;

import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../../backup/backup_gateway.dart';
import '../../backup/backup_operation_controller.dart';
import 'backup_confirmation_dialog.dart';
import 'backup_operation_banner.dart';

/// Какая разновидность файла выбрана для восстановления.
enum _RestoreKind { global, module }

/// Карточка «Восстановление».
///
/// Порядок работы повторяет требуемый сценарий: выбрать файл → показать,
/// что внутри → выбрать режим → подтвердить → выполнить. Восстановление
/// не начинается без подтверждения пользователя.
class RestoreSection extends StatefulWidget {
  const RestoreSection({
    super.key,
    required this.globalController,
    required this.moduleController,
    required this.installedModuleIds,
    required this.displayNameOf,
  });

  final BackupOperationController globalController;
  final BackupOperationController moduleController;
  final List<String> installedModuleIds;
  final String Function(String moduleId) displayNameOf;

  @override
  State<RestoreSection> createState() => _RestoreSectionState();
}

class _RestoreSectionState extends State<RestoreSection> {
  _RestoreKind _kind = _RestoreKind.module;
  ModuleRestoreMode _mode = ModuleRestoreMode.full;
  String? _targetModuleId;
  PickedBackup? _picked;

  /// Модуль из выбранного .pmb, которого нет среди установленных.
  ///
  /// Хранится отдельно от [_targetModuleId], чтобы показать пользователю
  /// причину, по которой модуль нельзя выбрать, и не подставлять
  /// несуществующий id в dropdown.
  String? _notInstalledArchiveModuleId;

  bool get _isModuleKind => _kind == _RestoreKind.module;

  /// Контроллер, отвечающий за текущий вид файла.
  BackupOperationController get _activeController =>
      _isModuleKind ? widget.moduleController : widget.globalController;

  bool get _busy =>
      widget.moduleController.isRunning || widget.globalController.isRunning;

  /// Целевой модуль мог исчезнуть из списка — тогда сбрасываем выбор.
  @override
  void didUpdateWidget(covariant RestoreSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _targetModuleId;
    if (target != null && !widget.installedModuleIds.contains(target)) {
      _targetModuleId = null;
      _picked = null;
      _notInstalledArchiveModuleId = null;
    }
  }

  /// Выбор вида файла сбрасывает и режим, и выбранный архив: они
  /// относились к другому типу файла.
  void _onKindChanged(_RestoreKind kind) {
    setState(() {
      _kind = kind;
      _picked = null;
      _notInstalledArchiveModuleId = null;
    });
    widget.globalController.reset();
    widget.moduleController.reset();
  }

  Future<void> _pickAndInspect() async {
    setState(() {
      _picked = null;
      _notInstalledArchiveModuleId = null;
    });

    final picked = await _activeController.pickAndInspect(asModule: _isModuleKind);
    if (!mounted) return;

    // null — это отмена или ошибка; статус уже отражён в баннере.
    if (picked == null) return;

    // Модуль внутри .pmb обязателен: без явного выбора нельзя понять,
    // куда восстанавливать, а угадывать нельзя.
    final archiveModuleId = picked.preview.moduleIds.isEmpty
        ? null
        : picked.preview.moduleIds.first;

    // Backup может принадлежать модулю, которого в приложении нет:
    // .pmb переносится между устройствами и не обязан совпадать с
    // текущим набором модулей. Такой id нельзя класть в dropdown —
    // значение отсутствует среди items, и Flutter падает с assertion.
    final isInstalled =
        archiveModuleId != null && widget.installedModuleIds.contains(archiveModuleId);

    setState(() {
      _picked = picked;
      if (_isModuleKind && archiveModuleId != null) {
        _targetModuleId = isInstalled ? archiveModuleId : null;
        _notInstalledArchiveModuleId = isInstalled ? null : archiveModuleId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Подписка на оба контроллера: статус операции и блокировка кнопок
    // восстановления должны обновляться без пересборки родителя.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.moduleController, widget.globalController]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return AppComponents.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppComponents.sectionHeader(
            context: context,
            title: 'Восстановление',
            subtitle: 'Выберите backup-файл, проверьте его содержимое '
                'и подтвердите восстановление.',
          ),
          RadioGroup<_RestoreKind>(
            groupValue: _kind,
            onChanged: (v) {
              if (!_busy) _onKindChanged(v!);
            },
            child: Column(
              children: const [
                RadioListTile<_RestoreKind>(
                  value: _RestoreKind.module,
                  title: Text('Backup модуля (.pmb)'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<_RestoreKind>(
                  value: _RestoreKind.global,
                  title: Text('Глобальный backup (.pbk)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (_isModuleKind) ...[
            SizedBox(height: AppSpacing.sm),
            _moduleTargetField(),
            SizedBox(height: AppSpacing.md),
            _ModeSelector(
              mode: _mode,
              enabled: !_busy,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ],
          SizedBox(height: AppSpacing.md),
          AppComponents.outlinedButton(
            onPressed: _busy ? null : _pickAndInspect,
            isLoading: _busy,
            leadingIcon: Icons.folder_open,
            child: Text(
              _isModuleKind ? 'Выбрать .pmb файл' : 'Выбрать .pbk файл',
            ),
          ),
          if (_picked != null) ...[
            SizedBox(height: AppSpacing.md),
            _PreviewCard(
              preview: _picked!.preview,
              fileName: _picked!.fileName,
              moduleNameFor: widget.displayNameOf,
            ),
          ],
          SizedBox(height: AppSpacing.md),
          BackupOperationBanner(controller: _activeController),
          SizedBox(height: AppSpacing.md),
          _restoreAction(),
        ],
      ),
    );
  }

  Widget _moduleTargetField() {
    final notInstalled = _notInstalledArchiveModuleId;

    if (widget.installedModuleIds.isEmpty) {
      return Text(
        'Нет установленных модулей — восстановление невозможно.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Значение dropdown берётся только из списка установленных
        // модулей: иначе Flutter упадёт с assertion «value не найден
        // среди items».
        DropdownButtonFormField<String>(
          value: _targetModuleId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Модуль-назначение',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final id in widget.installedModuleIds)
              DropdownMenuItem(
                value: id,
                child: Text(widget.displayNameOf(id)),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _targetModuleId = v),
        ),
        if (notInstalled != null) ...[
          SizedBox(height: AppSpacing.xs),
          Text(
            'Backup относится к модулю «${widget.displayNameOf(notInstalled)}», '
            'который не установлен. Установите модуль, чтобы восстановить его данные.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ],
    );
  }

  Widget _restoreAction() {
    if (!_isModuleKind) {
      return AppComponents.outlinedButton(
        onPressed: _picked == null || _busy
            ? null
            : () => showGlobalRestoreUnavailable(
                  context,
                  fileName: _picked!.fileName,
                  preview: _picked!.preview,
                ),
        leadingIcon: Icons.info_outline,
        child: const Text('Что можно сделать с этим файлом'),
      );
    }

    final ready = _picked != null && _targetModuleId != null && !_busy;

    return AppComponents.filledButton(
      onPressed: ready ? _confirmAndRestore : null,
      isLoading: widget.moduleController.isRunning,
      leadingIcon: Icons.restore,
      child: const Text('Восстановить модуль'),
    );
  }

  Future<void> _confirmAndRestore() async {
    final picked = _picked;
    final target = _targetModuleId;
    if (picked == null || target == null) return;

    final confirmed = await confirmModuleRestore(
      context,
      fileName: picked.fileName,
      moduleName: widget.displayNameOf(target),
      moduleId: target,
      mode: _mode,
      preview: picked.preview,
    );

    // Отмена — не ошибка: операция просто не запускалась, данные целы.
    if (!confirmed || !mounted) return;

    await widget.moduleController.restoreModuleBackup(
      archiveBytes: picked.bytes,
      moduleId: target,
      options: _mode.toOptions(),
    );
  }
}

/// Выбор режима восстановления.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final ModuleRestoreMode mode;
  final bool enabled;
  final ValueChanged<ModuleRestoreMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Режим', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final m in ModuleRestoreMode.values)
              ChoiceChip(
                label: Text(m.label),
                selected: mode == m,
                onSelected: enabled ? (_) => onChanged(m) : null,
              ),
          ],
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          mode.description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// Карточка с содержимым проверенного файла.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.fileName,
    required this.moduleNameFor,
  });

  final BackupPreview preview;
  final String fileName;
  final String Function(String) moduleNameFor;

  @override
  Widget build(BuildContext context) {
    return AppComponents.outlineSurface(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Файл проверен', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: AppSpacing.xs),
          _line(context, 'Файл', fileName),
          _line(context, 'Создан', _formatDate(preview.createdAt)),
          _line(context, 'Версия приложения', preview.appVersion),
          _line(
            context,
            'Модулей',
            preview.moduleIds.isEmpty
                ? 'нет'
                : preview.moduleIds.map(moduleNameFor).join(', '),
          ),
          if (preview.includesData) _line(context, 'Содержит данные', 'да'),
          if (preview.includesAssets) _line(context, 'Содержит файлы', 'да'),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
