import 'dart:convert';

import '../module_manifest.dart';

/// Ошибка разбора manifest.json внешнего модуля.
///
/// Одна ошибка на попытку разбора (в отличие от ManifestValidator,
/// который собирает СПИСОК всех нарушений сразу) — потому что если
/// JSON повреждён или структурно неверен, дальше разбирать нечего:
/// нет объекта ModuleManifest, который можно было бы проверять
/// дальше. Семантические проблемы (дубликат id, неподдерживаемый
/// apiVersion) — уже забота ManifestValidator, не этого класса.
class ManifestParseException implements Exception {
  final String message;
  const ManifestParseException(this.message);

  @override
  String toString() => 'ManifestParseException: $message';
}

/// Разбирает manifest.json внешнего модуля в ModuleManifest.
///
/// Строже, чем ModuleManifest.fromJson (Этап 7): там description/
/// icon/permissions/dependencies необязательны — это разумно для
/// СВОИХ встроенных модулей (ExampleModule и т.п.), которым можно
/// доверять и о которых мы не обязаны требовать явной полноты. Но
/// внешний, недоверенный пакет должен явно объявлять ВСЕ поля из
/// требования Этапа 11 — умолчания здесь маскировали бы то, что
/// автор пакета просто забыл что-то указать.
///
/// Не читает файлы и не знает про ZIP/диск — принимает уже
/// прочитанную строку. Откуда она взялась (файл, архив, буфер обмена)
/// — не забота этого класса; такое чтение — задача Этапа 12+.
class ManifestParser {
  /// Все поля, обязательные для ВНЕШНЕГО manifest.json.
  static const List<String> requiredKeys = [
    'id',
    'name',
    'version',
    'apiVersion',
    'author',
    'description',
    'permissions',
    'dependencies',
    'icon',
  ];

  ModuleManifest parse(String manifestJson) {
    final Map<String, dynamic> json;

    try {
      final decoded = jsonDecode(manifestJson);
      if (decoded is! Map<String, dynamic>) {
        throw const ManifestParseException(
          'manifest.json должен быть JSON-объектом верхнего уровня',
        );
      }
      json = decoded;
    } on FormatException catch (e) {
      throw ManifestParseException('повреждённый JSON: ${e.message}');
    }

    final missing = requiredKeys.where((key) => !json.containsKey(key)).toList();
    if (missing.isNotEmpty) {
      throw ManifestParseException(
        'отсутствуют обязательные поля: ${missing.join(", ")}',
      );
    }

    try {
      return ModuleManifest.fromJson(json);
    } on FormatException catch (e) {
      throw ManifestParseException(e.message);
    }
  }
}
