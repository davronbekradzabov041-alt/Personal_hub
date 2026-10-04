import 'dart:convert';
import '../external/module_package.dart';
import '../module_manifest.dart';

/// Content of a successfully read and validated .phm package.
///
/// This is the result of PackageReader.read() — a fully validated,
/// safe-to-use representation of the package contents. It contains
/// the parsed manifest, asset entries, optional storage.json, and
/// optional README.
///
/// This model does NOT perform any I/O or registry operations.
/// It is a pure data carrier for the next stages (Importer/Exporter).
class PackageContent {
  final ModuleManifest manifest;
  final List<PackageAsset> assets;
  final PackageData? data;
  final String? readme;

  const PackageContent({
    required this.manifest,
    this.assets = const [],
    this.data,
    this.readme,
  });

  /// Creates a PackageContent from a ModulePackage and raw asset/storage data.
  factory PackageContent.fromPackage(
    ModulePackage pkg, {
    required List<PackageAsset> assets,
    PackageData? data,
    String? readme,
  }) {
    return PackageContent(
      manifest: pkg.manifest,
      assets: assets,
      data: data,
      readme: pkg.readme ?? readme,
    );
  }
}

/// An asset file from the package (under assets/).
class PackageAsset {
  final String path; // Relative path within package, e.g. "assets/icon.png"
  final List<int> bytes;

  const PackageAsset({required this.path, required this.bytes});

  String get extension {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot).toLowerCase() : '';
  }

  bool get isImage => const {
        '.png', '.jpg', '.jpeg', '.webp', '.svg'
      }.contains(extension);

  bool get isJson => extension == '.json';
}

/// The data/storage.json content (parsed JSON).
class PackageData {
  final Map<String, dynamic> storage;

  const PackageData(this.storage);

  factory PackageData.fromJson(String jsonString) {
    // Validated as valid JSON by reader; parsing here is safe.
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('storage.json должен быть JSON-объектом');
    }
    return PackageData(decoded);
  }

  Map<String, dynamic> toJson() => storage;
}