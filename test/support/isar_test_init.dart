import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:isar/isar.dart';

/// Подготовка нативной библиотеки Isar для тестов на Windows.
///
/// `Isar.open()` всегда вызывает `initializeCoreBinary()` без
/// аргументов (`isar-3.1.0+1/lib/src/native/open.dart`), и isar
/// открывает библиотеку по bare-имени `isar.dll`. Windows
/// разрешает такое имя через рабочий каталог процесса, а
/// `flutter test` запускается из корня пакета — поэтому требовался
/// `isar.dll` рядом с `pubspec.yaml`.
///
/// `isar_flutter_libs` — Flutter-плагин: его бинарники попадают
/// только в сборку приложения, а в `flutter test` (в VM
/// `flutter_tester`) плагины не собираются. Поэтому штатный
/// `DynamicLibrary.open('isar.dll')` в тестах не работает, хотя
/// сам пакет с библиотекой на месте.
///
/// Решение — документированный API isar для unit-тестов:
/// `Isar.initializeIsarCore(libraries: ...)`. Путь берётся из
/// установленного пакета `isar_flutter_libs`, поэтому файл не нужно
/// ни хранить в репозитории, ни копировать вручную, ни скачивать.
///
/// Вызывается один раз до первого `Isar.open()` — обычно первым
/// оператором в `setUpAll`. Повторные вызовы безопасны: сам Isar
/// игнорирует повторную инициализацию.
Future<void> ensureIsarCoreInitialized() async {
  final libraryPath = await _isarCoreLibraryPath();
  await Isar.initializeIsarCore(
    libraries: <Abi, String>{Abi.current(): libraryPath},
  );
}

const String _packageName = 'isar_flutter_libs';

/// Путь к нативной библиотеке внутри установленного пакета.
///
/// Сначала используется штатный механизм Dart: `package:`-URI
/// разрешается в реальный файл пакета. Если он недоступен, путь
/// читается из `.dart_tool/package_config.json`, который
/// `flutter pub get` генерирует рядом с `pubspec.yaml`.
Future<String> _isarCoreLibraryPath() async {
  final packageRoot = await _packageRootFromIsolate() ??
      _packageRootFromPackageConfig();
  if (packageRoot == null) {
    throw StateError(
      'Не удалось определить расположение пакета $_packageName.\n'
      'Запустите `flutter pub get` и убедитесь, что он завершился '
      'без ошибок.',
    );
  }

  final library = File(
    '${packageRoot.path}${Platform.pathSeparator}'
    'windows${Platform.pathSeparator}isar.dll',
  );
  if (!library.existsSync()) {
    throw StateError(
      'Нативная библиотека Isar не найдена: ${library.path}\n'
      'Ожидается, что пакет $_packageName содержит windows/isar.dll — '
      'то есть тесты запускаются на Windows. На других платформах '
      'этот helper не нужен.',
    );
  }
  return library.absolute.path;
}

/// Каталог установленного пакета через `package:`-URI.
Future<Directory?> _packageRootFromIsolate() async {
  // Точка входа пакета всегда есть: у isar_flutter_libs это
  // единственный файл в lib/.
  final entryPoint = Uri.parse('package:$_packageName/$_packageName.dart');
  try {
    final resolved = await Isolate.resolvePackageUri(entryPoint);
    if (resolved == null) return null;
    // resolved = <package>/lib/isar_flutter_libs.dart
    return Directory(resolved.toFilePath()).parent.parent;
  } on Object {
    return null;
  }
}

/// Каталог установленного пакета из `.dart_tool/package_config.json`.
Directory? _packageRootFromPackageConfig() {
  final projectRoot = _findProjectRoot();
  if (projectRoot == null) return null;

  final configFile = File(
    '${projectRoot.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}package_config.json',
  );
  if (!configFile.existsSync()) return null;

  final Map<String, dynamic> config = jsonDecode(configFile.readAsStringSync())
      as Map<String, dynamic>;
  for (final package in config['packages']! as List<dynamic>) {
    final entry = package as Map<String, dynamic>;
    if (entry['name'] != _packageName) continue;
    final rootUri = entry['rootUri']! as String;
    return Directory(Uri.parse(Uri.decodeFull(rootUri)).toFilePath());
  }
  return null;
}

/// Каталог с `pubspec.yaml`: ищем вверх от рабочего каталога, затем
/// от каталога скрипта. Не полагаемся только на текущий каталог.
Directory? _findProjectRoot() {
  final starts = <String>[
    Directory.current.path,
    if (Platform.script.scheme == 'file')
      Directory.fromUri(Platform.script).parent.path,
  ];

  for (final start in starts) {
    var dir = Directory(start).absolute;
    while (true) {
      if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}
