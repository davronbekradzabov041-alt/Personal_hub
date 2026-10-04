/// TEST-19: сериализация restore проверяется на РАЗНЫХ payload.
///
/// Прежний тест запускал два restore одних и тех же байтов: если бы
/// сериализация была сломана, обе операции записали бы одинаковые данные,
/// итог выглядел бы правильным, и тест ничего не доказывал.
///
/// Здесь payload разные и различаются тем, что важно для отката:
///
/// * restore B (идёт первым) пишет ключ `kB` и состояние `enabled`;
/// * restore A (идёт вторым) пишет ключ `kA` и состояние `installed`,
///   и его запись данных ПАДАЕТ — срабатывает откат.
///
/// Проверяем ровно то, что обещает `_serializeRestore`: откат одного
/// restore не уничтожает результат другого. При сериализации A снимает
/// снимок уже ПОСЛЕ того, как B отработал, поэтому его откат возвращает
/// именно B. Без сериализации A может снять снимок до записи B — и его
/// откат вычистит `kB`, оставив модуль ни с одним payload.
///
/// Гонка создаётся НЕ временем, а барьером: A паркуется в снятии
/// снимка до тех пор, пока B не запишет свои данные. При наличии
/// `_serializeRestore` этот барьер не ждёт ничего — B уже отработал к
/// моменту входа A.
library module_restore_concurrency_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

class _FakeModule extends Module {
  _FakeModule(this._manifest);
  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

class _MemoryStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async => _data.remove(moduleId);
}

/// Хранилище с управляемым барьером и управляемым сбоем записи.
///
/// Моделирует ровно два эффекта, которые и должны быть защищены
/// сериализацией:
///
/// * `parkOnGetCall` — restore, снимающий снимок, ждёт чужую запись.
///   Барьер стоит в `getString`, потому что `getString` вызывает ТОЛЬКО
///   снятие снимка (`_captureSnapshot`); `deserialize` и откат работают
///   через `keys()/setString()/remove()` и сюда не заходят. Список ключей
///   берётся из последнего `keys()`, то есть снимок отражает момент
///   входа в критическую секцию.
/// * `failOnKey` — рваная запись: значение записано, потом приходит
///   ошибка (как в боевом откате ModuleStorageSerializer).
class _CoordinatedStorage implements ModuleStorage {
  _CoordinatedStorage(this._bucket);

  final Map<String, String> _bucket;

  /// Номер вызова getString(), на котором нужно встать на барьер.
  int? parkOnGetCall;

  /// Барьер: завершается, когда restore B записал свои данные.
  Completer<void>? waitForOtherWrite;

  /// Завершается, когда действительно записаны данные restore B.
  final Completer<void> otherWritten = Completer<void>();

  String? failOnKey;
  bool _alreadyTorn = false;

  int _getCalls = 0;
  List<String> _lastKeys = const [];

  /// Снимок, который видел restore, снявший его на барьере.
  List<String>? snapshotTakenAtBarrier;

  void armBarrier() {
    // Счётчики обнуляются: до барьера getString/keys вызывались
    // фикстурами (сбор архивов, подготовка данных).
    _getCalls = 0;
    _lastKeys = const [];
    parkOnGetCall = 2;
    waitForOtherWrite = otherWritten;
  }

  @override
  Future<List<String>> keys() async {
    _lastKeys = _bucket.keys.toList();
    return List<String>.of(_lastKeys);
  }

  @override
  Future<String?> getString(String key) async {
    _getCalls++;
    // Значение на момент снимка — до барьера.
    final value = _bucket[key];
    if (parkOnGetCall == _getCalls) {
      snapshotTakenAtBarrier = List<String>.of(_lastKeys);
      await waitForOtherWrite!.future;
    }
    return value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _bucket[key] = value; // запись состоялась...
    if (key == 'kB' && !otherWritten.isCompleted) {
      otherWritten.complete();
    }
    if (!_alreadyTorn && key == failOnKey) {
      _alreadyTorn = true;
      throw StateError('имитация сбоя после записи ключа $key'); // ...и пришёл сбой
    }
  }

  @override
  Future<void> remove(String key) async => _bucket.remove(key);
}

ModuleManifest _manifestFor(String id) => ModuleManifest(
      id: id,
      name: id,
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    );

ModuleStateSnapshot _snapshotFor(String moduleId, String state) {
  return ModuleStateSnapshot(
    moduleId: moduleId,
    state: state,
    installedVersion: '1.0.0',
    enabled: state == 'enabled',
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

void main() {
  late ModuleManager manager;
  late _MemoryStore store;
  late _CoordinatedStorage storage;
  late Directory tempRoot;

  const stateAndData =
      ModuleBackupOptions(includeState: true, includeData: true, includeAssets: false);

  ModuleBackupManager makeManager() => ModuleBackupManager(
        moduleManager: manager,
        stateStore: store,
        assetsDirectoryResolver: (id) async => Directory('${tempRoot.path}/$id/assets'),
      );

  /// Кладёт в хранилище ровно указанное содержимое.
  Future<void> putStorage(Map<String, String> entries) async {
    for (final key in await storage.keys()) {
      await storage.remove(key);
    }
    for (final e in entries.entries) {
      await storage.setString(e.key, e.value);
    }
  }

  /// Архив с собственным payload: свои данные И своё состояние.
  Future<List<int>> archiveWithData(
    Map<String, String> entries,
    String archivedState,
  ) async {
    await putStorage(entries);
    await store.save(_snapshotFor('alpha', archivedState));

    final outDir = Directory('${tempRoot.path}/out')..createSync(recursive: true);
    final result = await makeManager().createBackup(
      moduleId: 'alpha',
      outputDirectory: outDir,
      options: stateAndData,
    );
    return File(result.outputPath).readAsBytes();
  }

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(_FakeModule(_manifestFor('alpha')));

    final bucket = <String, String>{};
    storage = _CoordinatedStorage(bucket);
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => storage,
    );
    store = _MemoryStore();
    manager.setStateForTesting('alpha', ModuleState.enabled);
    tempRoot = Directory.systemTemp.createTempSync('restore_conc_');
  });

  tearDown(() {
    manager.dispose();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('откат одного restore не стирает результат другого (разные payload)',
      () async {
    // payload B — идёт первым и завершается успешно.
    final bytesB = await archiveWithData({'kB': 'value-B'}, 'enabled');
    // payload A — идёт вторым и падает на записи своих данных.
    final bytesA = await archiveWithData({'kA': 'value-A'}, 'installed');

    // Состояние до restore: ни payload B, ни payload A.
    await putStorage({'probe': 'user-data'});
    await store.save(_snapshotFor('alpha', 'disabled'));

    storage.failOnKey = 'kA';
    storage.armBarrier();

    final m = makeManager();
    // B стартует первым — так и выглядит допустимый порядок при
    // сериализации: сначала B целиком, потом A.
    final results = await Future.wait([
      m.restoreBackup(archiveBytes: bytesB, targetModuleId: 'alpha', options: stateAndData),
      m.restoreBackup(archiveBytes: bytesA, targetModuleId: 'alpha', options: stateAndData),
    ]);

    // A упал и откатился — это ожидаемо, именно его откат опасен.
    expect(results[0].isSuccess, isTrue,
        reason: 'restore B обязан преуспеть: ${results[0].error}');
    expect(results[1].isSuccess, isFalse,
        reason: 'restore A обязан упасть на записи kA');
    expect(results[1].rolledBackComponents, contains('data'));

    // Результат B пережил откат A: хранилище — ровно payload B.
    // ModuleStorageSerializer.deserialize приводит содержимое к точному
    // совпадению с архивом, поэтому «kB плюс что-то ещё» означало бы
    // смесь двух restore.
    expect((await storage.keys())..sort(), ['kB'],
        reason: 'откат A вычистил или испортил данные B — сериализации нет');
    expect(await storage.getString('kB'), 'value-B',
        reason: 'откат A затёр значение, записанное B');
    expect(await storage.getString('kA'), isNull,
        reason: 'данные упавшего restore A не должны остаться');

    // Состояние тоже принадлежит B: A откатил его к снимку, который
    // снял ПОСЛЕ успешного B.
    expect((await store.load('alpha'))!.state, 'enabled');
    expect(manager.stateOf('alpha'), ModuleState.enabled);

    // Снимок A снят уже после B — барьер не ждал его записи, потому
    // что к моменту входа A данные B уже были записаны.
    expect(storage.snapshotTakenAtBarrier, contains('kB'),
        reason: 'сериализация обязана исключить вход A до окончания B');
  });

  test('два параллельных restore с разными payload дают один целый payload',
      () async {
    final bytesA = await archiveWithData({'kA': 'value-A'}, 'installed');
    final bytesB = await archiveWithData({'kB': 'value-B'}, 'enabled');

    await putStorage({'probe': 'user-data'});
    await store.save(_snapshotFor('alpha', 'disabled'));

    final m = makeManager();
    final results = await Future.wait([
      m.restoreBackup(archiveBytes: bytesA, targetModuleId: 'alpha', options: stateAndData),
      m.restoreBackup(archiveBytes: bytesB, targetModuleId: 'alpha', options: stateAndData),
    ]);

    expect(results.every((r) => r.isSuccess), isTrue,
        reason: 'ошибки: ${results.map((r) => r.error).toList()}');

    // Итог — ЦЕЛИКОМ один из двух payload: данные и состояние от
    // одного и того же restore. Смесь (kA из одного, kB из другого)
    // означала бы, что критическая секция пересеклась.
    final keys = (await storage.keys())..sort();
    expect(keys.length, 1,
        reason: 'итог — данные ровно одного restore, без смеси: $keys');
    expect(keys.single, anyOf('kA', 'kB'));

    final state = (await store.load('alpha'))!.state;
    final winnerKey = keys.contains('kA') ? 'kA' : 'kB';
    final winnerState = winnerKey == 'kA' ? 'installed' : 'enabled';
    expect(state, winnerState,
        reason: 'состояние и данные обязаны принадлежать одному restore');
  });
}
