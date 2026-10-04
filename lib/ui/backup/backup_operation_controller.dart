/// Состояние одной операции backup/restore для UI.
library backup_operation_controller;

import 'package:flutter/foundation.dart';

import '../../core/backup/module_backup_options.dart';
import 'backup_error_presenter.dart';
import 'backup_file_service.dart';
import 'backup_gateway.dart';

/// Статус операции.
enum BackupOperationStatus {
  /// Операция ещё не запускалась.
  idle,

  /// Операция выполняется — повторный запуск запрещён.
  running,

  /// Операция завершилась успешно.
  success,

  /// Операция завершилась ошибкой.
  error,

  /// Пользователь отменил выбор файла или сохранение.
  cancelled,
}

/// Контроллер одной операции backup/restore.
///
/// Держит ровно одно активное состояние, поэтому запрет «нельзя запустить
/// вторую операцию поверх первой» обеспечивается здесь, а не размазывается
/// по виджетам: [_guard] игнорирует вызовы, пока статус
/// [BackupOperationStatus.running].
///
/// Отмена выбора файла — не ошибка: у неё отдельный статус
/// [BackupOperationStatus.cancelled], иначе пользователь, просто
/// закрывший диалог, увидел бы сообщение об ошибке.
class BackupOperationController extends ChangeNotifier {
  BackupOperationController({
    required BackupGateway gateway,
    required BackupFileService fileService,
  })  : _gateway = gateway,
        _fileService = fileService;

  final BackupGateway _gateway;
  final BackupFileService _fileService;

  BackupOperationStatus _status = BackupOperationStatus.idle;
  String? _message;
  String? _errorText;
  String? _savedPath;
  bool _canRetry = true;

  BackupOperationStatus get status => _status;

  /// Короткий итог операции для снэкбара или подписи.
  String? get message => _message;

  /// Текст ошибки — заполняется только при статусе error.
  String? get errorText => _errorText;

  /// Куда сохранился файл.
  String? get savedPath => _savedPath;

  bool get isRunning => _status == BackupOperationStatus.running;

  bool get isRetryable => _canRetry;

  // -------------------------------------------------------------------
  // Создание backup
  // -------------------------------------------------------------------

  Future<void> createGlobalBackup(GlobalBackupSelection selection) {
    return _guard(() async {
      final artifact = await _gateway.createGlobalBackup(selection);
      final outcome = await _fileService.saveArtifact(
        artifact,
        'Сохранить глобальный backup',
      );
      _completeSave(artifact, outcome);
    });
  }

  Future<void> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  ) {
    return _guard(() async {
      final artifact = await _gateway.createModuleBackup(moduleId, options);
      final outcome = await _fileService.saveArtifact(
        artifact,
        'Сохранить backup модуля',
      );
      _completeSave(artifact, outcome);
    });
  }

  // -------------------------------------------------------------------
  // Чтение и проверка
  // -------------------------------------------------------------------

  /// Проверенный файл, готовый к восстановлению.
  ///
  /// Байты возвращаются наружу, чтобы пользователю не пришлось выбирать
  /// один и тот же файл повторно: между проверкой и подтверждением файл
  /// не меняется, а повторный выбор был бы лишним шагом в сценарии,
  /// который и так требует подтверждения.
  Future<PickedBackup?> pickAndInspect({required bool asModule}) {
    return _guardReturning<PickedBackup>(() async {
      final picked = await _fileService.pickBackupFile(
        extensions: [asModule ? 'pmb' : 'pbk'],
        title: asModule
            ? 'Выберите backup модуля (.pmb)'
            : 'Выберите глобальный backup (.pbk)',
      );
      if (picked == null) {
        _cancelled('Выбор файла отменён.');
        return null;
      }

      final preview = asModule
          ? await _gateway.inspectModuleBackup(picked.bytes)
          : await _gateway.inspectGlobalBackup(picked.bytes);

      return PickedBackup(
        fileName: picked.name,
        bytes: picked.bytes,
        preview: preview,
      );
    });
  }

  // -------------------------------------------------------------------
  // Восстановление
  // -------------------------------------------------------------------

  /// Восстанавливает модуль из готовых байт.
  ///
  /// Подтверждение пользователя спрашивает виджет, а не контроллер:
  /// контроллер не знает про диалоги и обязан оставаться проверяемым.
  Future<void> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) {
    return _guard(() async {
      final outcome = await _gateway.restoreModuleBackup(
        archiveBytes: archiveBytes,
        moduleId: moduleId,
        options: options,
      );
      if (outcome.isSuccess) {
        _set(
          BackupOperationStatus.success,
          message: 'Модуль «${outcome.moduleId}» восстановлен: '
              '${_components(outcome.appliedComponents)}.',
        );
      } else {
        _set(
          BackupOperationStatus.error,
          errorText: _restoreFailureText(outcome),
        );
      }
    });
  }

  /// Текст для неудачного восстановления.
  ///
  /// Два разных случая, которые раньше сводились к одному тексту
  /// «изменения отменены»:
  ///
  /// * откат УСПЕШЕН (сюда мы попадаем — ModuleBackupManager бросает
  ///   ModuleRestoreException, когда откат провалился) — изменения
  ///   действительно отменены, и стоит сказать, что именно вернулось;
  /// * откат ПРОВАЛИЛСЯ — это исключение, и его текст даёт
  ///   [BackupErrorPresenter].
  ///
  /// Причина сбоя (`outcome.error`) раньше отбрасывалась целиком.
  String _restoreFailureText(RestoreOutcome outcome) {
    final cause = outcome.error;
    final reason = cause == null
        ? 'Восстановление не удалось.'
        : BackupErrorPresenter.present(cause).text;

    final rolledBack = outcome.rolledBackComponents;
    if (rolledBack.isEmpty) {
      return '$reason Данные модуля не изменены.';
    }
    return '$reason Изменения отменены — возвращено в исходное состояние: '
        '${_components(rolledBack)}.';
  }

  // -------------------------------------------------------------------
  // Внутреннее
  // -------------------------------------------------------------------

  /// Запрещает параллельный запуск: пока операция идёт, новый вызов
  /// игнорируется, а не ставится в очередь (очередь означала бы, что
  /// пользователь запустил вторую операцию, не заметив первую).
  Future<void> _guard(Future<void> Function() body) {
    if (isRunning) return Future<void>.value();
    _set(BackupOperationStatus.running);
    return _invoke(body);
  }

  Future<T?> _guardReturning<T>(Future<T?> Function() body) {
    if (isRunning) return Future<T?>.value(null);
    _set(BackupOperationStatus.running);
    return _invoke<T>(body).then((value) {
      // При отмене value == null и статус уже cancelled — success здесь
      // ставить нельзя.
      if (value != null) {
        _set(BackupOperationStatus.success, message: 'Файл прошёл проверку.');
      }
      return value;
    });
  }

  /// Единая точка перехвата ошибок: любое исключение из операции
  /// превращается в понятный текст, а не в стектрейс на экране.
  Future<T?> _invoke<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } catch (error) {
      final presented = BackupErrorPresenter.present(error);
      _set(
        BackupOperationStatus.error,
        errorText: presented.text,
        canRetry: presented.isRetryable,
      );
      return null;
    }
  }

  void _completeSave(BackupArtifact artifact, SaveOutcome outcome) {
    if (outcome.wasCancelled) {
      _cancelled('Сохранение отменено.');
      return;
    }
    _savedPath = outcome.savedPath;
    _set(
      BackupOperationStatus.success,
      message: 'Backup сохранён: ${artifact.fileName}',
    );
  }

  void _cancelled(String message) {
    _set(BackupOperationStatus.cancelled, message: message);
  }

  void _set(
    BackupOperationStatus status, {
    String? message,
    String? errorText,
    bool? canRetry,
  }) {
    _status = status;
    _message = message;
    _errorText = errorText;
    _canRetry = canRetry ?? (status == BackupOperationStatus.error);
    if (status != BackupOperationStatus.success) {
      _savedPath = null;
    }
    notifyListeners();
  }

  static String _components(List<String> components) {
    return components.isEmpty ? 'нет компонентов' : components.join(', ');
  }

  /// Возврат к исходному состоянию.
  void reset() {
    if (isRunning) return;
    _status = BackupOperationStatus.idle;
    _message = null;
    _errorText = null;
    _savedPath = null;
    _canRetry = true;
    notifyListeners();
  }
}
