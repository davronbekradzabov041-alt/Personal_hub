/// Секция создания backup одного модуля (.pmb).
library module_backup_section;

import 'package:flutter/material.dart';

import '../../../core/backup/module_backup_options.dart';
import '../../../core/design/design_system.dart';
import '../../backup/backup_operation_controller.dart';
import 'backup_operation_banner.dart';

/// Карточка «Backup модуля».
class ModuleBackupSection extends StatefulWidget {
  const ModuleBackupSection({
    super.key,
    required this.controller,
    required this.installedModuleIds,
    required this.displayNameOf,
  });

  final BackupOperationController controller;
  final List<String> installedModuleIds;
  final String Function(String moduleId) displayNameOf;

  @override
  State<ModuleBackupSection> createState() => _ModuleBackupSectionState();
}

class _ModuleBackupSectionState extends State<ModuleBackupSection> {
  String? _moduleId;
  bool _includeState = true;
  bool _includeData = true;
  bool _includeAssets = true;

  /// Выбранный модуль мог исчезнуть из списка (например, удалён) — тогда
  /// сбрасываем выбор, иначе UI предлагал бы backup несуществующего.
  @override
  void didUpdateWidget(covariant ModuleBackupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _moduleId;
    if (current != null && !widget.installedModuleIds.contains(current)) {
      _moduleId = null;
    }
  }

  ModuleBackupOptions get _options => ModuleBackupOptions(
        includeState: _includeState,
        includeData: _includeData,
        includeAssets: _includeAssets,
      );

  @override
  Widget build(BuildContext context) {
    // Подписка на контроллер обязательна: без неё кнопка не
    // блокировалась бы на время операции.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = widget.controller.isRunning;
    final hasModules = widget.installedModuleIds.isNotEmpty;

    return AppComponents.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppComponents.sectionHeader(
            context: context,
            title: 'Backup модуля',
            subtitle: 'Сохраняет данные одного модуля в файл .pmb. '
                'Пригоден, чтобы перенести данные на другое устройство.',
          ),
          if (!hasModules)
            Text(
              'Нет установленных модулей.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _moduleId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Модуль',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final id in widget.installedModuleIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text(widget.displayNameOf(id)),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => _moduleId = v),
            ),
            SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _includeState,
              onChanged:
                  busy ? null : (v) => setState(() => _includeState = v ?? false),
              title: const Text('Состояние'),
              subtitle: const Text('Установлен, включён и версия модуля'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _includeData,
              onChanged:
                  busy ? null : (v) => setState(() => _includeData = v ?? false),
              title: const Text('Данные'),
              subtitle: const Text('Ключи и значения хранилища модуля'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _includeAssets,
              onChanged:
                  busy ? null : (v) => setState(() => _includeAssets = v ?? false),
              title: const Text('Файлы'),
              subtitle: const Text('Картинки и документы модуля'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            SizedBox(height: AppSpacing.sm),
            BackupOperationBanner(
              controller: widget.controller,
              emptyStateMessage: 'Выберите модуль и сохраните файл.',
            ),
            SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: AppComponents.filledButton(
                onPressed: _moduleId == null || busy
                    ? null
                    : () => widget.controller.createModuleBackup(
                          _moduleId!,
                          _options,
                        ),
                isLoading: busy,
                leadingIcon: Icons.save_alt,
                child: const Text('Создать backup модуля'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
