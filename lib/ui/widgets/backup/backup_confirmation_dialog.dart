/// Подтверждение восстановления перед изменением данных.
library backup_confirmation_dialog;

import 'package:flutter/material.dart';

import '../../backup/backup_gateway.dart';

/// Диалог подтверждения destructive-операции.
///
/// Показывает всё, что нужно для осознанного решения: имя файла,
/// модуль-назначение, режим и список затрагиваемых компонентов.
/// Без этого «Да» означало бы согласие вслепую.
///
/// Возвращает `true` только при явном подтверждении; возврат диалога
/// (кнопка «Отмена», back, тап вне) — это `false`, а не ошибка.
Future<bool> confirmModuleRestore(BuildContext context, {
  required String fileName,
  required String moduleName,
  required String moduleId,
  required ModuleRestoreMode mode,
  required BackupPreview preview,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Восстановить данные модуля?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Файл', fileName),
          _row('Модуль', moduleName),
          _row('Идентификатор', moduleId),
          _row('Режим', '${mode.label} — ${mode.description}'),
          const SizedBox(height: 8),
          Text(
            'Будет изменено: ${_components(mode)}',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Текущие данные модуля будут заменены. Отменить это действие '
            'нельзя.',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Восстановить'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Диалог для недоступной операции.
///
/// Глобального restore (.pbk) в core нет, поэтому UI не делает вид,
/// что он есть: показывает, что архив проверен, и объясняет, чем
/// воспользоваться вместо него.
Future<void> showGlobalRestoreUnavailable(
  BuildContext context, {
  required String fileName,
  required BackupPreview preview,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Глобальный backup: только проверка'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Файл', fileName),
          _row('Модулей в архиве', '${preview.moduleIds.length}'),
          _row('Создан', _formatDate(preview.createdAt)),
          const SizedBox(height: 8),
          Text(
            'Файл цел и прошёл проверку. Но восстановление глобального '
            'backup (.pbk) в системе пока не реализовано — есть только '
            'создание и проверка. Данные модуля восстанавливайте из '
            'отдельных backup .pmb.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

Widget _row(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _components(ModuleRestoreMode mode) {
  switch (mode) {
    case ModuleRestoreMode.full:
      return 'состояние, данные и файлы модуля';
    case ModuleRestoreMode.dataOnly:
      return 'только данные модуля';
    case ModuleRestoreMode.stateOnly:
      return 'только состояние модуля';
    case ModuleRestoreMode.assetsOnly:
      return 'только файлы модуля';
    case ModuleRestoreMode.dataAndAssets:
      return 'данные и файлы модуля';
  }
}
