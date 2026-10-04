/// Секция создания глобального backup (.pbk).
library global_backup_section;

import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../../backup/backup_gateway.dart';
import '../../backup/backup_operation_controller.dart';
import 'backup_operation_banner.dart';

/// Карточка «Глобальный backup».
///
/// Отдельный контроллер операций: у каждой секции своя операция и свой
/// статус, иначе запуск backup модуля затирал бы сообщение о только что
/// завершившемся глобальном backup.
class GlobalBackupSection extends StatefulWidget {
  const GlobalBackupSection({
    super.key,
    required this.controller,
    required this.installedModuleIds,
    required this.displayNameOf,
  });

  final BackupOperationController controller;

  /// Идентификаторы установленных модулей.
  final List<String> installedModuleIds;

  final String Function(String moduleId) displayNameOf;

  @override
  State<GlobalBackupSection> createState() => _GlobalBackupSectionState();
}

class _GlobalBackupSectionState extends State<GlobalBackupSection> {
  bool _allInstalled = true;
  final Set<String> _selected = <String>{};
  bool _includeSettings = true;
  bool _includeData = true;
  bool _includeAssets = true;

  GlobalBackupSelection get _selection => GlobalBackupSelection(
        moduleIds: _allInstalled
            ? widget.installedModuleIds.toSet()
            : _selected,
        allInstalled: _allInstalled,
        includeGlobalSettings: _includeSettings,
        includeModuleData: _includeData,
        includeAssets: _includeAssets,
      );

  /// Можно ли что-то сохранять: либо все модули, либо выбран хотя бы один.
  bool get _canBackup {
    if (_allInstalled) {
      return _includeSettings || widget.installedModuleIds.isNotEmpty;
    }
    return _selected.isNotEmpty || _includeSettings;
  }

  @override
  Widget build(BuildContext context) {
    // Секция подписывается на контроллер сама: без этого состояние
    // «идёт операция» не дошло бы до кнопок, и повторный запуск
    // остался бы возможным.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = widget.controller.isRunning;

    return AppComponents.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppComponents.sectionHeader(
            context: context,
            title: 'Глобальный backup',
            subtitle: 'Сохраняет настройки и данные выбранных модулей '
                'в один файл .pbk.',
          ),
          SwitchListTile(
            value: _includeSettings,
            onChanged:
                busy ? null : (v) => setState(() => _includeSettings = v),
            title: const Text('Настройки приложения'),
            subtitle: const Text('Тема, язык и другие глобальные настройки'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _includeData,
            onChanged: busy ? null : (v) => setState(() => _includeData = v),
            title: const Text('Данные модулей'),
            subtitle: const Text('Ключи и значения из хранилища модулей'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _includeAssets,
            onChanged: busy ? null : (v) => setState(() => _includeAssets = v),
            title: const Text('Файлы модулей'),
            subtitle: const Text('Картинки и документы из папки модуля'),
            contentPadding: EdgeInsets.zero,
          ),
          // Состояние модулей (state.json) в формате .pbk пишется всегда
          // для каждого включённого модуля и отдельным флагом не
          // управляется, поэтому переключателя здесь намеренно нет.
          const _AlwaysIncludedNote(),
          const Divider(),
          _ModulePicker(
            allInstalled: _allInstalled,
            selected: _selected,
            installedModuleIds: widget.installedModuleIds,
            displayNameOf: widget.displayNameOf,
            enabled: !busy,
            onAllInstalledChanged: (v) => setState(() => _allInstalled = v),
            onModuleToggled: (id, selected) => setState(() {
              if (selected) {
                _selected.add(id);
              } else {
                _selected.remove(id);
              }
            }),
          ),
          SizedBox(height: AppSpacing.md),
          BackupOperationBanner(controller: widget.controller),
          SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppComponents.filledButton(
              onPressed: _canBackup && !busy
                  ? () => widget.controller.createGlobalBackup(_selection)
                  : null,
              isLoading: busy,
              leadingIcon: Icons.save_alt,
              child: const Text('Создать глобальный backup'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заметка о компоненте, который нельзя отключить.
class _AlwaysIncludedNote extends StatelessWidget {
  const _AlwaysIncludedNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        'Установленные и включённые модули сохраняются вместе с их '
        'состоянием — отдельно отключить это нельзя.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Общий выбор модулей: «все» или поимённо.
class _ModulePicker extends StatelessWidget {
  const _ModulePicker({
    required this.allInstalled,
    required this.selected,
    required this.installedModuleIds,
    required this.displayNameOf,
    required this.enabled,
    required this.onAllInstalledChanged,
    required this.onModuleToggled,
  });

  final bool allInstalled;
  final Set<String> selected;
  final List<String> installedModuleIds;
  final String Function(String) displayNameOf;
  final bool enabled;
  final ValueChanged<bool> onAllInstalledChanged;
  final void Function(String moduleId, bool selected) onModuleToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<bool>(
          groupValue: allInstalled,
          // RadioGroup не принимает null в onChanged, поэтому
          // заблокированное состояние выражается проверкой внутри, а не
          // подменой обработчика на null.
          onChanged: (v) {
            if (enabled) onAllInstalledChanged(v!);
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: true,
                title: Text('Все модули (${installedModuleIds.length})'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                value: false,
                title: const Text('Выбрать модули'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        if (!allInstalled)
          if (installedModuleIds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Text(
                'Установленных модулей нет.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            Column(
              children: [
                for (final id in installedModuleIds)
                  CheckboxListTile(
                    value: selected.contains(id),
                    onChanged: enabled
                        ? (v) => onModuleToggled(id, v ?? false)
                        : null,
                    title: Text(displayNameOf(id)),
                    subtitle: Text(id),
                    contentPadding: const EdgeInsets.only(
                      left: AppSpacing.lg,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
            ),
      ],
    );
  }
}
