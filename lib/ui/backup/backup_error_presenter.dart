/// Перевод ошибок backup в понятные пользователю сообщения.
///
/// Пользователь не должен видеть ни стектрейс, ни внутренние имена
/// исключений. Здесь каждое известное исключение явно сводится к
/// одной фразе. Всё остальное — к общему «не удалось выполнить
/// операцию», но с сохранением причины из сообщения исключения, если
/// она есть: полностью выбрасывать текст ошибки значило бы заставить
/// пользователя гадать.
library backup_error_presenter;

import 'dart:io';

import '../../core/backup/backup_exceptions.dart';

/// Результат показа ошибки: текст для пользователя и флаг «можно
/// повторить».
class BackupErrorMessage {
  final String text;
  final bool isRetryable;

  const BackupErrorMessage(this.text, {this.isRetryable = true});
}

/// Превращает исключение в сообщение для UI.
class BackupErrorPresenter {
  BackupErrorPresenter._();

  static BackupErrorMessage present(Object error) {
    if (error is BackupException) {
      return BackupErrorMessage(_presentBackupException(error));
    }
    if (error is FileSystemException) {
      return const BackupErrorMessage(
        'Не удалось получить доступ к файлу. Проверьте права на папку.',
      );
    }
    if (error is FormatException) {
      return const BackupErrorMessage(
        'Файл повреждён и не является корректным backup.',
        isRetryable: false,
      );
    }
    return const BackupErrorMessage(
      'Не удалось выполнить операцию. Попробуйте ещё раз.',
    );
  }

  static String _presentBackupException(BackupException error) {
    // Порядок важен: подклассы проверяются раньше базового типа.
    if (error is ChecksumMismatchException) {
      return 'Backup повреждён: контрольная сумма не совпадает. '
          'Возможно, файл изменён или оборван при копировании.';
    }
    if (error is UnsupportedBackupVersionException) {
      return 'Эта версия backup создана более новой версией приложения '
          'и пока не поддерживается.';
    }
    if (error is ModuleIdMismatchException) {
      return 'Backup относится к другому модулю. Выберите файл, '
          'сделанный для этого модуля.';
    }
    if (error is ModuleNotInstalledException) {
      return 'Модуль не установлен. Сначала установите его, '
          'иначе восстановить данные будет некуда.';
    }
    if (error is ModuleRestoreException) {
      // ModuleRestoreException бросается именно тогда, когда откат
      // НЕ удался. Сообщать «данные возвращены в исходное состояние»
      // здесь нельзя: часть данных модуля может остаться изменённой.
      return 'Восстановление не удалось, и вернуть данные в исходное '
          'состояние не получилось. Часть данных модуля могла остаться '
          'изменённой. Не выполняйте новые операции с модулем и '
          'сохраните резервную копию перед следующей попыткой.';
    }
    if (error is BackupSecurityException) {
      return 'Backup отклонён проверкой безопасности: архив содержит '
          'недопустимые пути или слишком велик.';
    }
    if (error is CorruptedBackupException ||
        error is CorruptedArchiveException) {
      return 'Архив повреждён и не может быть прочитан.';
    }
    if (error is MissingBackupEntryException) {
      return 'Backup неполный: в архиве отсутствует обязательный файл.';
    }
    if (error is InvalidBackupManifestException) {
      return 'Описание backup некорректно, файл не подходит.';
    }
    if (error is BackupFormatException) {
      // Сообщение форматного исключения уже написано по-человечески
      // («архив повреждён», «не найдена сигнатура …» и т.п.).
      return _stripPrefix(error.message, 'некорректный формат backup: ');
    }
    return 'Не удалось выполнить операцию с backup.';
  }

  static String _stripPrefix(String message, String prefix) {
    return message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;
  }
}
