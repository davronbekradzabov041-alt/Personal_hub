/// Работа с файлами backup: выбор существующего и сохранение нового.
///
/// Обёртка над file_picker. Существует по двум причинам:
///
/// 1. в UI-тестах плагин недоступен — операция подменяется фейком;
/// 2. отмена выбора файла — штатный сценарий (пункт 6 ТЗ), и она должна
///    отличаться от ошибки, поэтому возвращается `null`, а не бросается
///    исключение.
library backup_file_service;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'backup_gateway.dart';

/// Выбранный пользователем файл.
class PickedFile {
  final String name;
  final Uint8List bytes;

  const PickedFile({required this.name, required this.bytes});
}

/// Результат сохранения файла.
class SaveOutcome {
  /// Куда сохранили — путь, если плагин его вернул.
  final String? savedPath;

  /// Пользователь отказался от сохранения.
  final bool wasCancelled;

  const SaveOutcome.saved(this.savedPath) : wasCancelled = false;

  const SaveOutcome.cancelled()
      : savedPath = null,
        wasCancelled = true;
}

/// Операции выбора/сохранения файлов для UI.
abstract class BackupFileService {
  /// Сохранить [artifact] под предложенным именем.
  /// `null` в [SaveOutcome.savedPath] при отмене — см. [SaveOutcome].
  Future<SaveOutcome> saveArtifact(BackupArtifact artifact, String title);

  /// Выбрать существующий backup-файл.
  /// `null` — пользователь отменил выбор.
  Future<PickedFile?> pickBackupFile({
    required List<String> extensions,
    required String title,
  });
}

/// Реализация поверх file_picker.
class PickerBackupFileService implements BackupFileService {
  const PickerBackupFileService();

  @override
  Future<SaveOutcome> saveArtifact(
    BackupArtifact artifact,
    String title,
  ) async {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: artifact.fileName,
      type: FileType.custom,
      allowedExtensions: [artifact.fileName.split('.').last],
      bytes: Uint8List.fromList(artifact.bytes),
    );
    return savedPath == null
        ? const SaveOutcome.cancelled()
        : SaveOutcome.saved(savedPath);
  }

  @override
  Future<PickedFile?> pickBackupFile({
    required List<String> extensions,
    required String title,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedFile(name: file.name, bytes: bytes);
  }
}
