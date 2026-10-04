/// Баннер состояния операции backup/restore.
///
/// Показывает ровно одно из: успех, ошибку, отмену — и умеет сбросить
/// состояние по кнопке. Используется всеми тремя секциями экрана.
library backup_operation_banner;

import 'package:flutter/material.dart';

import '../../../core/design/design_system.dart';
import '../../backup/backup_operation_controller.dart';

/// Панель статуса операции.
class BackupOperationBanner extends StatelessWidget {
  const BackupOperationBanner({
    super.key,
    required this.controller,
    this.emptyStateMessage,
  });

  final BackupOperationController controller;

  /// Сообщение в покое, когда операций ещё не было.
  final String? emptyStateMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.status) {
          case BackupOperationStatus.idle:
            final text = emptyStateMessage;
            if (text == null) return const SizedBox.shrink();
            return AppComponents.inlinePanel(
              context: context,
              child: Text(text),
            );

          case BackupOperationStatus.running:
            return AppComponents.inlinePanel(
              context: context,
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('Выполняется операция…')),
                ],
              ),
            );

          case BackupOperationStatus.success:
            return _Banner(
              icon: Icons.check_circle_outline,
              message: controller.message ?? 'Готово',
              color: Theme.of(context).colorScheme.primary,
              onReset: controller.reset,
            );

          case BackupOperationStatus.cancelled:
            return _Banner(
              icon: Icons.info_outline,
              message: controller.message ?? 'Операция отменена',
              color: Theme.of(context).colorScheme.outline,
              onReset: controller.reset,
            );

          case BackupOperationStatus.error:
            return _Banner(
              icon: Icons.error_outline,
              message: controller.errorText ?? 'Операция не удалась',
              color: Theme.of(context).colorScheme.error,
              onReset: controller.reset,
            );
        }
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    required this.onReset,
  });

  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return AppComponents.inlinePanel(
      context: context,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onReset,
            tooltip: 'Сбросить',
          ),
        ],
      ),
    );
  }
}
