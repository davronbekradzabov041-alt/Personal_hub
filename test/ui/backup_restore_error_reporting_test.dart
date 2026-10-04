/// Регрессия AUD-09: «восстановление не удалось» и «не удалось вернуть
/// данные в исходное состояние» — это разные сообщения.
///
/// ModuleRestoreException бросается РОВНО тогда, когда откат не удался,
/// но пользователю показывалось «данные возвращены в исходное
/// состояние» — то есть ровно то, чего не произошло.
library backup_restore_error_reporting_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/ui/backup/backup_error_presenter.dart';
import 'package:personal_hub/ui/backup/backup_file_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/backup_operation_controller.dart';

/// Gateway, отдающий заранее заданный исход восстановления
/// (или бросающий заранее заданное исключение).
class _ScriptedGateway implements BackupGateway {
  _ScriptedGateway({this.outcome, this.error});

  final RestoreOutcome? outcome;
  final Object? error;

  @override
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) async {
    if (error != null) throw error!;
    return outcome!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('в этом тесте нужен только restore');
}

class _UnusedFileService implements BackupFileService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('в этом тесте файловый сервис не нужен');
}

void main() {
  group('BackupErrorPresenter: ModuleRestoreException', () {
    test('не обещает возврат данных в исходное состояние', () {
      final message = BackupErrorPresenter.present(
        ModuleRestoreException('откат не удался: boom'),
      );

      expect(
        message.text.toLowerCase(),
        isNot(contains('возвращены в исходное состояние')),
        reason: 'откат не удался — обещать возврат нельзя',
      );
      expect(
        message.text.toLowerCase(),
        anyOf(contains('не получилось'), contains('не удалось')),
      );
    });

    test('предупреждает, что данные могли остаться изменёнными', () {
      final message = BackupErrorPresenter.present(
        ModuleRestoreException('откат не удался: boom'),
      );

      expect(message.text, contains('изменённ'));
    });

    test('не раскрывает технические детали исключения', () {
      final message = BackupErrorPresenter.present(
        ModuleRestoreException('откат не удался: StateError: path C:/data'),
      );

      expect(message.text, isNot(contains('StateError')));
      expect(message.text, isNot(contains('C:/data')));
      expect(message.text, isNot(contains('Exception')));
    });
  });

  group('BackupOperationController: текст неудачного восстановления', () {
    late BackupOperationController _controller;

    BackupOperationController controllerFor(_ScriptedGateway gateway) {
      return BackupOperationController(
        gateway: gateway,
        fileService: _UnusedFileService(),
      );
    }

    tearDown(() {
      _controller.dispose();
    });

    Future<void> restore() {
      return _controller.restoreModuleBackup(
        archiveBytes: [1, 2, 3],
        moduleId: 'schedule',
        options: const ModuleBackupOptions(),
      );
    }

    test('откат успешен: сообщает, что именно отменено', () async {
      _controller = controllerFor(
        _ScriptedGateway(
          outcome: const RestoreOutcome(
            isSuccess: false,
            moduleId: 'schedule',
            appliedComponents: ['state', 'data'],
            rolledBackComponents: ['state', 'data'],
            message: 'FormatException: bad',
            error: FormatException('bad'),
          ),
        ),
      );

      await restore();

      final text = _controller.errorText ?? '';
      // Причина (FormatException) переведена Presenter'ом в понятную
      // фразу, а не показана как «FormatException: bad».
      expect(text, contains('Файл повреждён'));
      expect(text, isNot(contains('FormatException')));
      expect(text, contains('Изменения отменены'));
      expect(text, contains('state'));
      expect(text, contains('data'));
    });

    test('ничего не применялось: обещает неизменность данных', () async {
      _controller = controllerFor(
        _ScriptedGateway(
          outcome: const RestoreOutcome(
            isSuccess: false,
            moduleId: 'schedule',
            error: ChecksumMismatchException(),
          ),
        ),
      );

      await restore();

      final text = _controller.errorText ?? '';
      expect(text, contains('контрольная сумма'));
      expect(text, contains('не изменены'));
    });

    test('откат провалился (исключение): не говорит об отмене изменений', () async {
      _controller = controllerFor(
        _ScriptedGateway(error: ModuleRestoreException('откат не удался')),
      );

      await restore();

      final text = _controller.errorText ?? '';
      expect(text.toLowerCase(), isNot(contains('изменения отменены')));
      expect(text, contains('изменённ'));
    });

    test('причина сбоя не показывается пользователю как есть', () async {
      _controller = controllerFor(
        _ScriptedGateway(
          outcome: RestoreOutcome(
            isSuccess: false,
            moduleId: 'schedule',
            error: StateError('internal path /data/user/0/secret'),
          ),
        ),
      );

      await restore();

      final text = _controller.errorText ?? '';
      expect(text, isNot(contains('StateError')));
      expect(text, isNot(contains('/data/user/0/secret')));
      expect(text, isNotEmpty);
    });

    test('успешное восстановление по-прежнему сообщает состав', () async {
      _controller = controllerFor(
        _ScriptedGateway(
          outcome: const RestoreOutcome(
            isSuccess: true,
            moduleId: 'schedule',
            appliedComponents: ['state', 'data'],
          ),
        ),
      );

      await restore();

      expect(_controller.status, BackupOperationStatus.success);
      expect(_controller.message, contains('schedule'));
      expect(_controller.message, contains('state'));
    });
  });
}
