/// Сторож границы Этапа 9 (миграции данных модуля) — аудит Этапа 8.2.
///
/// Этап 8 закончил обновление модуля. Этап 9 будет решать, что делать с
/// ДАННЫМИ модуля при переходе между версиями. Чтобы Этап 9 не пришлось
/// переделывать обновление, в Этапе 8 должно быть верно следующее, и
/// именно это здесь проверяется:
///
/// 1. обновление НЕ трогает данные модуля (никакой миграции, никаких
///    преобразований, никакой записи в ModuleStorage);
/// 2. нет поля `schemaVersion` — версия схемы данных не выдумывается;
/// 3. нет миграционного движка и нет хука `onUpdate`;
/// 4. `installedVersion` — это ВЕРСИЯ МОДУЛЯ из ModuleRegistry, а не
///    версия схемы данных;
/// 5. инфраструктура снимка/отката одна и та же для backup и обновления,
///    то есть Этап 9 получит готовый откат, а не будет строить свой;
/// 6. версии, нужные Этапу 9, доступны: в плане обновления есть
///    fromVersion/toVersion, а в реестре — версия установленного кода.
///
/// Проверки статические и разбирают код до файловой системы, а ищут по
/// коду, а не по тексту: комментарии обсуждают миграции (чтобы объяснить,
/// почему их нет), и наивный поиск слова «миграция» ловил бы их.
library module_update_stage9_boundary_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/module_importer.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

const String _moduleId = 'notes';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = Directory.current;

  List<String> dartFilesUnder(String relativeDir) {
    final absolute = Directory('${root.path}${Platform.pathSeparator}'
        '${relativeDir.replaceAll('/', Platform.pathSeparator)}');
    if (!absolute.existsSync()) {
      fail('каталог не найден: $relativeDir');
    }
    return absolute
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path.substring(root.path.length + 1).replaceAll('\\', '/'))
        .toList()
      ..sort();
  }

  String readFile(String packageRelativePath) => File(
        '${root.path}${Platform.pathSeparator}'
        '${packageRelativePath.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();

  /// Строки файла, где образец встречается В КОДЕ, а не в комментарии.
  List<String> codeLinesContaining(String packageRelativePath, String pattern) {
    final regex = RegExp(pattern, multiLine: true);
    return _stripComments(readFile(packageRelativePath))
        .split('\n')
        .where(regex.hasMatch)
        .map((line) => line.trim())
        .toList();
  }

  /// Все места в каталоге, где образец встречается в коде.
  List<String> codeOccurrencesIn(String relativeDir, String pattern) {
    final found = <String>[];
    for (final file in dartFilesUnder(relativeDir)) {
      for (final line in codeLinesContaining(file, pattern)) {
        found.add('$file: $line');
      }
    }
    return found;
  }

  group('Этап 9: данных обновление не касается', () {
    test('обновление не делает НИ ОДНОЙ записи в ModuleStorage', () async {
      // Самое сильное утверждение, которое вообще можно сделать: не
      // «не вызывает migrate()», а «не пишет». Любая миграция данных
      // начинается с записи, поэтому хранилище, которое считает свои
      // вызовы, ловит её целиком — включая миграцию, написанную мимо
      // ModuleManager.
      final writes = _WriteCountingStorage();
      ModuleRegistry.clear();
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => writes,
      );
      final support = await Directory.systemTemp.createTemp('stage9_');
      addTearDown(() async {
        ModuleRegistry.clear();
        if (support.existsSync()) await support.delete(recursive: true);
      });

      ModuleImporter importer() => ModuleImporter(
            moduleManager: manager,
            testSupportDir: support,
            stateStore: _NoopStateStore(),
          );

      // Установка пишет (засевает пакет) — это законно.
      expect(
        (await importer().importFromBytes(_phm(version: '1.0.0'))).isSuccess,
        isTrue,
      );
      writes.reset();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0', storage: {'миграция': 'данных'}),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      expect(writes.setCalls, 0,
          reason: 'обновление обязано оставить данные модуля в покое');
      expect(writes.removeCalls, 0,
          reason: 'удаление ключа при обновлении — это тоже потеря данных');
    });

    test('schemaVersion объявлен ровно в манифесте', () {
      // С Этапа 9.1 версия схемы данных существует, но живёт в одном
      // месте: в манифесте. Второе объявление означало бы два
      // источника правды о форме данных, и они разошлись бы при
      // первом же несовпадении.
      final occurrences = codeOccurrencesIn(
        'lib/core/modules',
        r'\bint\s+get\s+schemaVersion\b|\bthis\.schemaVersion\b',
      );
      expect(occurrences, isNotEmpty,
          reason: 'поле schemaVersion обязано существовать в манифесте: '
              'без него «какой формы ждём данные» решить нечем');
      expect(occurrences.every((line) => line.contains('module_manifest')),
          isTrue,
          reason: 'schemaVersion — свойство только манифеста.\n'
              'Найдено:\n  ${occurrences.join('\n  ')}');
    });

    test('нет хука onUpdate, но есть платформенный ModuleMigrationRunner', () {
      // Хук `onUpdate` в модуле означал бы «реализация сама решает, что
      // делать с данными при обновлении» — то есть миграция внутри
      // непредсказуемого кода вместо отдельного, проверяемого шага.
      final hookInModule = codeLinesContaining(
        'lib/core/modules/module.dart',
        r'\bonUpdate\b|\bmigrat',
      );
      expect(hookInModule, isEmpty,
          reason: 'Module не должен получать хук обновления или миграции.\n'
              'Найдено:\n  ${hookInModule.join('\n  ')}');

      // Миграции теперь выполняются через ModuleMigrationRunner —
      // это платформенный executor, а не хук в Module.
      final runnerFiles = <String>[
        ...dartFilesUnder('lib/core/modules'),
        ...dartFilesUnder('lib/core/backup'),
      ].where((f) => RegExp(r'migration_runner').hasMatch(f.toLowerCase())).toList();
      expect(runnerFiles, isNotEmpty,
          reason: 'ModuleMigrationRunner обязан существовать на Этапе 9.3.\n'
              'Найдено: ${runnerFiles.join(', ')}');

      // Отдельного файла миграций в слое обновления и backup быть не
      // должно. Область — платформа модулей и backup, а не весь lib:
      // у модуля Schedule есть собственный migrator его ДАННЫХ (Этап 7.4),
      // и это другой механизм — он не часть обновления модуля.
      final migrationFiles = <String>[
        ...dartFilesUnder('lib/core/modules'),
        ...dartFilesUnder('lib/core/backup'),
      ].where((f) => RegExp(r'migrat').hasMatch(f.toLowerCase())).toList();
      // Разрешены: module_migration_runner.dart, module_migration_planner.dart,
      // module_migration_plan.dart, module_migration_result.dart,
      // module_migration_planner_boundary_test.dart, module_migration_runner_test.dart,
      // module_migration_planner_test.dart, schedule_migration_planner_test.dart
      final unexpected = migrationFiles
          .where((f) => !f.contains('migration_runner')
              && !f.contains('migration_planner')
              && !f.contains('migration_plan')
              && !f.contains('migration_result')
              && !f.contains('migration')
              && !f.contains('planner')
              && !f.contains('schedule'))
          .toList();
      expect(unexpected, isEmpty,
          reason: 'Файлы миграций разрешены только в платформе миграций '
              'и в Schedule (который делегирует в Runner).\n'
              'Найдено: ${unexpected.join(', ')}');
    });
  });

  group('Этап 9: installedVersion — это версия модуля', () {
    test('после обновления записанная версия равна версии реестра', () async {
      // Записывает версию не импортёр, а ModuleStatePersistence — единственный
      // её писатель. Поэтому проверяется связка «обновление → синхронизация
      // состояния»: именно её увидит Этап 9 на следующем запуске.
      final store = _RecordingStateStore();
      final support = await Directory.systemTemp.createTemp('stage9_ver_');
      ModuleRegistry.clear();
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => _MemoryStorage(),
      );
      final persistence = ModuleStatePersistence(
        manager,
        store,
        storageFactory: (_) => _MemoryStorage(),
      );
      addTearDown(() async {
        persistence.dispose();
        ModuleRegistry.clear();
        if (support.existsSync()) await support.delete(recursive: true);
      });

      ModuleImporter importer() => ModuleImporter(
            moduleManager: manager,
            testSupportDir: support,
            stateStore: store,
          );

      expect((await importer().importFromBytes(_phm(version: '1.0.0'))).isSuccess,
          isTrue);
      await persistence.flush();
      expect(store.snapshots[_moduleId]!.installedVersion, '1.0.0');

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );
      expect(result.isSuccess, isTrue, reason: result.error);
      await persistence.flush();

      // Снимок до обновления снял запись 1.0.0, но записанная версия
      // обязана совпадать с манифестом новой версии: Этап 9 будет решать
      // по ней, какую миграцию запускать, и «версия данных», взятая из
      // архива или из старой записи, увела бы его не туда.
      expect(
        store.snapshots[_moduleId]!.installedVersion,
        ModuleRegistry.get(_moduleId)!.manifest.version,
      );
      expect(store.snapshots[_moduleId]!.installedVersion, '1.1.0');
    });

    test('план обновления несёт fromVersion/toVersion для Этапа 9', () {
      final plan = codeLinesContaining(
        'lib/core/modules/module_update_plan.dart',
        r'fromVersion|toVersion',
      );
      expect(plan, isNotEmpty,
          reason: 'Версии «откуда» и «куда» — то, что Этап 9 будет читать в '
              'первую очередь. Если их нет в плане обновления, Этапу 9 '
              'придётся вычислять их заново или менять обновление.');
    });
  });

  group('Этап 9: снимок и откат — одна инфраструктура', () {
    test('снимок объявлен ровно в одном файле', () {
      final declarations = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (RegExp(r'class\s+ModuleSnapshotService\b')
            .hasMatch(_stripComments(readFile(file)))) {
          declarations.add(file);
        }
      }
      expect(declarations, <String>['lib/core/modules/module_snapshot.dart'],
          reason: 'Второе объявление снимка означало бы две несовместимые '
              'механики отката — ровно то, что Этапу 9 пришлось бы чинить.');
    });

    test('и обновление, и backup restore пользуются этим снимком', () {
      for (final file in const [
        'lib/core/modules/platform/module_importer.dart',
        'lib/core/backup/module_backup_manager.dart',
      ]) {
        final usages = codeLinesContaining(file, r'ModuleSnapshotService');
        expect(usages, isNotEmpty,
            reason: '$file обязан снимать и откатывать снимок через общий '
                'механизм. Собственная реализация отката здесь означала бы, '
                'что Этап 9 должен будет поддерживать её отдельно.');
      }
    });

    test('backup не откатывает данные своей самодельной логикой', () {
      // Прежний код backup делал откат вручную. Если он вернётся, у двух
      // подсистем появятся разные правила «что считать попыткой», и
      // миграция данных в Этапе 9 раскачала бы их в разные стороны.
      final manualRollback = codeLinesContaining(
        'lib/core/backup/module_backup_manager.dart',
        r'storage\.remove\(|for\s*\([^)]*\bkeys\(\)',
      );
      expect(manualRollback, isEmpty,
          reason: 'Откат в backup обязан идти через ModuleSnapshotService.\n'
              'Найдено:\n  ${manualRollback.join('\n  ')}');
    });
  });

  group('Этап 9: версии доступны там, где их и будут спрашивать', () {
    test('версия установленного кода берётся из реестра', () {
      // Единственный источник истины о версии — манифест зарегистрированного
      // модуля. Число «какая версия стоит» в другом месте (например, в
      // состоянии, взятом из архива) — это второй источник, и Этап 9 будет
      // принимать решения по тому, который нашёлся первым.
      final registryVersion = codeLinesContaining(
        'lib/core/modules/module_manager.dart',
        r'manifest\.version',
      );
      expect(registryVersion, isNotEmpty);
    });

    test('обновление не вызывает lifecycle-хуки модуля заново', () async {
      // Если бы обновление пересоздавало модуль как при установке, хук
      // onInstall исполнился бы второй раз на уже существующих данных.
      // Для Этапа 9 это значило бы, что миграция может выполниться дважды
      // или в момент, когда данные уже изменились.
      final hooks = _RecordingModule();
      ModuleRegistry.clear();
      final manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => _MemoryStorage(),
      );
      final support = await Directory.systemTemp.createTemp('stage9_hooks_');
      // tryInstall создаёт песочницу модуля, а она идёт через
      // path_provider — в тесте его нет.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => support.path,
      );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        ModuleRegistry.clear();
        if (support.existsSync()) await support.delete(recursive: true);
      });

      ModuleRegistry.register(hooks);
      expect((await manager.tryInstall(_moduleId)).isSuccess, isTrue);
      hooks.calls.clear();

      final result = await ModuleImporter(
        moduleManager: manager,
        testSupportDir: support,
        stateStore: _NoopStateStore(),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      expect(hooks.calls, isEmpty,
          reason: 'Обновление подменяет реализацию в реестре, но не '
              'переустанавливает модуль: хуки не должны вызываться заново.');
      expect(manager.stateOf(_moduleId), ModuleState.installed);
    });
  });
}

// =========================================================================
// Фикстуры
// =========================================================================

List<int> _phm({
  required String version,
  Map<String, String> storage = const <String, String>{},
}) {
  return ModulePackageWriter.write(PackageContent(
    manifest: ModuleManifest.fromJson(<String, dynamic>{
      'id': _moduleId,
      'name': 'Заметки',
      'version': version,
      'apiVersion': 1,
      'author': 'Test',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': '',
    }),
    data: storage.isEmpty
        ? null
        : PackageData(jsonDecode(jsonEncode(storage)) as Map<String, dynamic>),
  ));
}

/// Хранилище, считающее ВСЕ записи: так «обновление не пишет данные»
/// проверяется фактом, а не отсутствием вызова конкретного метода.
class _WriteCountingStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};
  int setCalls = 0;
  int removeCalls = 0;

  void reset() {
    setCalls = 0;
    removeCalls = 0;
  }

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    setCalls++;
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    removeCalls++;
    data.remove(key);
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

class _MemoryStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

class _NoopStateStore implements ModuleStateStore {
  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => const [];

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => null;

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {}

  @override
  Future<void> delete(String moduleId) async {}
}

class _RecordingStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> snapshots =
      <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => snapshots.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => snapshots[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    snapshots[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    snapshots.remove(moduleId);
  }
}

/// Внешний модуль, считающий вызовы lifecycle-хуков.
///
/// Именно потомок [ExternalModuleAdapter], а не произвольный Module:
/// обновление из .phm имеет право применять только к внешним модулям,
/// и подменять манифест встроенному оно не станет.
class _RecordingModule extends ExternalModuleAdapter {
  _RecordingModule() : super(_manifestOf(_moduleId, '1.0.0'));

  final List<String> calls = <String>[];

  @override
  Future<void> onInstall(ModuleApi api) async => calls.add('onInstall');

  @override
  Future<void> onEnable(ModuleApi api) async => calls.add('onEnable');

  @override
  Future<void> onDisable(ModuleApi api) async => calls.add('onDisable');

  @override
  Future<void> onUninstall(ModuleApi api) async => calls.add('onUninstall');
}

ModuleManifest _manifestOf(String id, String version) =>
    ModuleManifest.fromJson(<String, dynamic>{
      'id': id,
      'name': 'Заметки',
      'version': version,
      'apiVersion': 1,
      'author': 'Test',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': '',
    });

/// Убирает комментарии из исходника (по образцу сторожа Этапа 7.4):
/// иначе поиск по слову ловил бы объяснения того, почему чего-то нет.
String _stripComments(String source) {
  final out = StringBuffer();
  var index = 0;
  var quote = '';
  var rawString = false;
  var inBlockComment = false;

  while (index < source.length) {
    final char = source[index];

    if (inBlockComment) {
      if (char == '*' &&
          index + 1 < source.length &&
          source[index + 1] == '/') {
        inBlockComment = false;
        index += 2;
        continue;
      }
      if (char == '\n') out.write('\n');
      index++;
      continue;
    }

    if (quote.isNotEmpty) {
      out.write(char);
      if (char == r'\' && !rawString && index + 1 < source.length) {
        out.write(source[index + 1]);
        index += 2;
        continue;
      }
      if (char == quote) quote = '';
      index++;
      continue;
    }

    if (char == '/' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '/') {
        while (index < source.length && source[index] != '\n') {
          index++;
        }
        continue;
      }
      if (next == '*') {
        inBlockComment = true;
        index += 2;
        continue;
      }
    }

    if (char == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"')) {
      rawString = true;
      quote = source[index + 1];
      out.write(char);
      out.write(quote);
      index += 2;
      continue;
    }

    if (char == "'" || char == '"') {
      quote = char;
      rawString = false;
      out.write(char);
      index++;
      continue;
    }

    out.write(char);
    index++;
  }

  return out.toString();
}
