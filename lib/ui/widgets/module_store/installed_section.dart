import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../../../../core/modules/module_manager.dart';
import '../../../../core/modules/module.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../../../core/modules/module_registry.dart';
import '../../../../core/modules/module_state.dart';
import '../../../../core/modules/external/external_module_adapter.dart';
import '../../../../core/modules/platform/module_exporter.dart';
import '../../../../core/design/design_system.dart';
import 'module_action_runner.dart';
import 'module_card.dart';

/// Раздел «Установленные».
///
/// Показывает модули, для которых ModuleManager отслеживает состояние
/// installed/enabled/disabled — не просто всё, что есть в
/// ModuleRegistry (полностью удалённые модули туда не попадают, см.
/// README, раздел Этапа 12, "известное ограничение").
class InstalledSection extends StatelessWidget {
  const InstalledSection({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final installed = ModuleRegistry.modules
            .where((module) => manager.isInstalled(module.id))
            .toList();

        if (installed.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.install_mobile_outlined,
            title: 'Нет установленных модулей',
          );
        }

        // Карточки модулей с равным зазором 12 dp.
        //
        // `ListView.separated` здесь не подходит: секция встроена в общий
        // `ListView` экрана «Модули», а в тестах показывается внутри
        // `Scaffold` без скроллера. Вложенный скроллер с неограниченной
        // высотой сломал бы вёрстку, поэтому взят эквивалент — тот же
        // зазор между карточками, но без дублирования отступов: его нет
        // ни сверху, ни снизу списка, только МЕЖДУ соседями.
        final cards = <Widget>[];
        for (var index = 0; index < installed.length; index++) {
          if (index > 0) cards.add(const SizedBox(height: 12));
          cards.add(_buildModuleCard(context, manager, installed[index]));
        }

        return Column(children: cards);
      },
    );
  }

  Widget _buildModuleCard(
    BuildContext context,
    ModuleManager manager,
    Module module,
  ) {
    {
      final state = manager.stateOf(module.id)!;
      final isExternal = module is ExternalModuleAdapter;

      final actions = <Widget>[
        AppComponents.outlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: module.buildPage),
          ),
          child: const Text('Открыть'),
        ),
        if (state == ModuleState.installed ||
            state == ModuleState.disabled)
          AppComponents.filledButton(
            onPressed: () => runModuleAction(
              context,
              () => manager.enable(module.id),
            ),
            child: const Text('Включить'),
          ),
        if (state == ModuleState.enabled)
          AppComponents.outlinedButton(
            onPressed: () => runModuleAction(
              context,
              () => manager.disable(module.id),
            ),
            child: const Text('Выключить'),
          ),
        if (state == ModuleState.installed ||
            state == ModuleState.disabled)
          AppComponents.textButton(
            onPressed: () => runModuleAction(
              context,
              () => manager.uninstall(module.id),
            ),
            child: const Text('Удалить'),
          ),
        // Export action for external modules
        if (isExternal)
          AppComponents.outlinedButton(
            onPressed: () => _showExportDialog(context, module.id),
            child: const Text('Экспорт'),
          ),
      ];

      return ModuleCard(
        icon: module.icon,
        name: module.title,
        version: module.manifest.version,
        author: module.manifest.author,
        permissions: module.manifest.permissions,
        stateLabel: _stateLabel(state),
        actions: actions,
      );
    }
  }

  void _showExportDialog(BuildContext context, String moduleId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ExportModeDialog(moduleId: moduleId),
    );
  }

  String _stateLabel(ModuleState state) {
    switch (state) {
      case ModuleState.installed:
        return 'установлен';
      case ModuleState.enabled:
        return 'включён';
      case ModuleState.disabled:
        return 'выключен';
      case ModuleState.uninstalled:
        return 'удалён';
    }
  }
}

class _ExportModeDialog extends StatefulWidget {
  const _ExportModeDialog({required this.moduleId});
  final String moduleId;

  @override
  State<_ExportModeDialog> createState() => _ExportModeDialogState();
}

class _ExportModeDialogState extends State<_ExportModeDialog> {
  ModuleExportMode _selectedMode = ModuleExportMode.withoutData;
  bool _isExporting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Экспорт модуля'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберите режим экспорта:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          RadioListTile<ModuleExportMode>(
            title: const Text('Без пользовательских данных'),
            subtitle: const Text('Только манифест, README и ассеты'),
            value: ModuleExportMode.withoutData,
            groupValue: _selectedMode,
            onChanged: _isExporting
                ? null
                : (value) => setState(() => _selectedMode = value!),
          ),
          RadioListTile<ModuleExportMode>(
            title: const Text('С пользовательскими данными'),
            subtitle: const Text('Включает текущие данные модуля (ModuleStorage)'),
            value: ModuleExportMode.withData,
            groupValue: _selectedMode,
            onChanged: _isExporting
                ? null
                : (value) => setState(() => _selectedMode = value!),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _isExporting ? null : () => _exportModule(),
          child: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Экспорт'),
        ),
      ],
    );
  }

  Future<void> _exportModule() async {
    setState(() {
      _isExporting = true;
      _error = null;
    });

    try {
      final manager = ModuleManagerScope.of(context);
      final exporter = ModuleExporter(moduleManager: manager);
      final result = await exporter.export(
        moduleId: widget.moduleId,
        mode: _selectedMode,
      );

      if (!mounted) return;

      if (result.isFailure) {
        setState(() {
          _error = result.error;
          _isExporting = false;
        });
        return;
      }

      // Save the exported .phm file
      final fileName = '${result.moduleId}_${DateTime.now().millisecondsSinceEpoch}.phm';
      final output = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить экспорт модуля',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['phm'],
        bytes: result.phmBytes as Uint8List?,
      );

      if (!mounted) return;

      if (output == null) {
        // User cancelled save dialog
        Navigator.of(context).pop();
        return;
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Модуль экспортирован в $output')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка экспорта: $e';
        _isExporting = false;
      });
    }
  }
}
