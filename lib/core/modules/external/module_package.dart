import '../module_manifest.dart';

/// Разобранный и провалидированный пакет внешнего модуля.
///
/// Чисто структура данных — не читает диск, не знает про ZIP.
/// `assetPaths`/`dataPaths` — относительные пути ВНУТРИ пакета
/// (`assets/icon.svg`, `data/seed.json` и т.п.), как их указал
/// вызывающий код; сами байты файлов эта модель не хранит и не
/// загружает — чтение содержимого ассетов/данных с диска или из
/// ZIP-архива остаётся за пределами Этапа 11 (см. "Не реализовывать").
class ModulePackage {
  final ModuleManifest manifest;
  final List<String> assetPaths;
  final List<String> dataPaths;
  final String? readme;

  const ModulePackage({
    required this.manifest,
    this.assetPaths = const [],
    this.dataPaths = const [],
    this.readme,
  });
}
