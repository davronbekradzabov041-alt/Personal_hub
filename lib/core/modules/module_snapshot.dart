/// Снимок состояния модуля и его откат — общий для Этапа 8 (Update)
/// и Этапа 9 (Migration System).
///
/// Механизм не новый: он вынесен из ModuleBackupManager без изменения
/// поведения `.pmb` restore. Причина вынесения — обратная: два
/// независимых отката (один в backup, второй в update) разошлись бы
/// при первой же правке, а «откат, который удаляет хранилище» вместо
/// «отката к снимку» способен уничтожить данные, существовавшие ДО
/// операции.
///
/// Снимок снимает ровно те компоненты, которые операция будет менять:
/// если assets не участвуют, снимок по ним не берётся и откат их не
/// трогает.
library module_snapshot;

import 'dart:io';

import 'package:path/path.dart' as path;

import 'module_manager.dart';
import 'module_state.dart';
import 'module_state_store.dart';
import 'platform/module_sandbox.dart';

/// Что именно входит в снимок.
///
/// Строковые имена совпадают с теми, что ModuleBackupManager
/// использует в `appliedComponents`/`attemptedComponents`, поэтому
/// существующий отчёт restore остаётся прежним, а снимок можно
/// передавать между слоями как есть.
enum ModuleSnapshotComponent {
  storage('data'),
  state('state'),
  assets('assets');

  const ModuleSnapshotComponent(this.wireName);

  /// Имя компонента в отчётах о применении и откате.
  final String wireName;
}

/// Откат не удался.
///
/// Наполовину откатанный модуль опаснее явно сообщённой ошибки, поэтому
/// откат, который не смог вернуть прежнее состояние, падает, а не
/// возвращает «успешный» результат. Тип собственный, а не
/// ModuleRestoreException: этот файл не знает про слой backup и не
/// должен им зависеть — зависимость направлена backup → modules, а не
/// наоборот.
class ModuleSnapshotRollbackException implements Exception {
  final String message;

  ModuleSnapshotRollbackException(this.message);

  @override
  String toString() => message;
}

/// Снимок содержимого модуля — полная основа для отката.
class ModuleSnapshot {
  final String moduleId;

  /// Содержимое ModuleStorage на момент снятия.
  final Map<String, String> storage;

  /// Состояние из ModuleStateStore.
  final ModuleStateSnapshot? state;

  /// Состояние в ModuleManager на момент снятия.
  ///
  /// Откат обязан вернуть и его: одного лишь хранилища мало, иначе
  /// после неудачной операции менеджер остался бы с новым состоянием,
  /// а следующая синхронизация записала бы его в хранилище — модуль
  /// был бы «наполовину обновлён».
  final ModuleState? managerState;

  final Map<String, List<int>> assets;
  final bool assetsDirExisted;

  /// Что реально снято. Откат не прикасается к тому, чего в снимке
  /// нет.
  final Set<ModuleSnapshotComponent> components;

  const ModuleSnapshot({
    required this.moduleId,
    required this.storage,
    required this.state,
    required this.managerState,
    required this.assets,
    required this.assetsDirExisted,
    required this.components,
  });

  /// Хранилось ли что-то в снимке по данным/состоянию/активам.
  bool captured(ModuleSnapshotComponent component) =>
      components.contains(component);
}

/// Снимает и откатывает снимки.
///
/// Зависимости внедряются теми же конструкторными аргументами, что и
/// у ModuleBackupManager, и по той же причине: тест должен подменять
/// хранилище состояния и каталог ассетов, не поднимая Isar и не
/// трогая файловую систему пользователя.
class ModuleSnapshotService {
  ModuleSnapshotService({
    required ModuleManager moduleManager,
    ModuleStateStore? stateStore,
    Future<Directory> Function(String moduleId)? assetsDirectoryResolver,
  })  : _moduleManager = moduleManager,
        _stateStore = stateStore,
        _assetsDirectoryResolver = assetsDirectoryResolver;

  final ModuleManager _moduleManager;
  final ModuleStateStore? _stateStore;
  final Future<Directory> Function(String moduleId)? _assetsDirectoryResolver;

  /// Снимает снимок ДО любых записей.
  ///
  /// Снимок — best effort чтение, а не транзакция: между чтением
  /// хранилища и чтением состояния кто-то может успеть записать. Для
  /// отката это безопасно (снимок либо чуть старше, либо чуть новее
  /// операции), а вот МОЛЧАЛИВО продолжать операцию, снимок которой
  /// неполон, было бы хуже: поэтому исключение снятия не глотается,
  /// оно уходит вызывающему до того, как что-либо изменено.
  Future<ModuleSnapshot> capture({
    required String moduleId,
    Set<ModuleSnapshotComponent> components = const {
      ModuleSnapshotComponent.storage,
      ModuleSnapshotComponent.state,
      ModuleSnapshotComponent.assets,
    },
  }) async {
    final storage = <String, String>{};
    if (components.contains(ModuleSnapshotComponent.storage)) {
      final moduleStorage = _moduleManager.apiFor(moduleId).storage;
      for (final key in await moduleStorage.keys()) {
        final value = await moduleStorage.getString(key);
        if (value != null) storage[key] = value;
      }
    }

    final store = _stateStore;
    final state = (components.contains(ModuleSnapshotComponent.state) &&
            store != null)
        ? await store.load(moduleId)
        : null;

    final assets = <String, List<int>>{};
    var assetsDirExisted = false;
    if (components.contains(ModuleSnapshotComponent.assets)) {
      final dir = await resolveAssetsDirectory(moduleId);
      assetsDirExisted = await dir.exists();
      if (assetsDirExisted) {
        for (final entity in await dir.list().toList()) {
          if (entity is File) {
            assets[path.basename(entity.path)] = await entity.readAsBytes();
          }
        }
      }
    }

    return ModuleSnapshot(
      moduleId: moduleId,
      storage: storage,
      state: state,
      managerState: _moduleManager.stateOf(moduleId),
      assets: assets,
      assetsDirExisted: assetsDirExisted,
      components: Set.unmodifiable(components),
    );
  }

  /// Возвращает модуль к [snapshot] и возвращает список компонентов,
  /// которые действительно откатились.
  ///
  /// [attemptedComponents] — компоненты, которые начали применяться,
  /// ВКЛЮЧАЯ упавшие посередине: их данные уже изменились, даже если
  /// этап не завершился. Откатывать нужно именно их: откат только по
  /// «успешно применённым» молча оставил бы изменения наполовину
  /// применённого компонента (именно ради этого правила разделены
  /// applied и attempted в restore).
  ///
  /// Принимает и строки, и [ModuleSnapshotComponent]: restore
  /// оперирует именами компонентов из архива, update — типизированными.
  Future<List<String>> rollback(
    ModuleSnapshot snapshot, {
    required Iterable<Object> attemptedComponents,
  }) async {
    final rolledBack = <String>[];
    final failures = <Object>[];

    for (final raw in attemptedComponents) {
      final wireName = raw is ModuleSnapshotComponent
          ? raw.wireName
          : raw.toString();
      final component = _componentFor(wireName);
      if (component == null) {
        // Компонент, которого снимок не знает (например, какая-нибудь
        // будущая часть архива). Молча пропустить опасно: откат
        // выглядел бы успешным, не сделав ничего. Лучше явная ошибка.
        failures.add(
          'неизвестный компонент снимка: "$wireName" '
          '(снято: ${snapshot.components.map((c) => c.wireName).join(", ")})',
        );
        continue;
      }
      if (!snapshot.captured(component)) {
        continue;
      }

      try {
        switch (component) {
          case ModuleSnapshotComponent.state:
            await _rollbackState(snapshot);
            rolledBack.add(component.wireName);
          case ModuleSnapshotComponent.storage:
            await _restoreStorage(snapshot);
            rolledBack.add(component.wireName);
          case ModuleSnapshotComponent.assets:
            await _restoreAssets(snapshot);
            rolledBack.add(component.wireName);
        }
      } catch (error) {
        failures.add(error);
      }
    }

    if (failures.isNotEmpty) {
      throw ModuleSnapshotRollbackException(
        'откат не удался: ${failures.join("; ")}',
      );
    }
    return rolledBack;
  }

  /// Каталог ассетов модуля: внедрённый или боевой.
  Future<Directory> resolveAssetsDirectory(String moduleId) async {
    final resolver = _assetsDirectoryResolver;
    if (resolver != null) return resolver(moduleId);
    return ModuleSandbox.getAssetsDirectory(moduleId);
  }

  // --- Внутреннее ---

  static ModuleSnapshotComponent? _componentFor(String wireName) {
    for (final component in ModuleSnapshotComponent.values) {
      if (component.wireName == wireName) return component;
    }
    return null;
  }

  Future<void> _rollbackState(ModuleSnapshot snapshot) async {
    final store = _stateStore;
    if (store != null) {
      final previous = snapshot.state;
      if (previous == null) {
        await store.delete(snapshot.moduleId);
      } else {
        await store.save(previous);
      }
    }
    await _rollbackManagerState(snapshot);
  }

  /// Возвращает ModuleManager к состоянию, которое было до операции.
  ///
  /// Идёт через тот же контракт adoptRestoredState, что и restore, иначе
  /// откат состоял бы в прямой записи в приватную карту и не запустил бы
  /// lifecycle-хуки (модуль, ставший неактивным, должен снова отписаться
  /// от поиска, и наоборот).
  Future<void> _rollbackManagerState(ModuleSnapshot snapshot) async {
    final prior = snapshot.managerState;
    if (prior == null || prior == ModuleState.uninstalled) return;

    final moduleId = snapshot.moduleId;
    if (_moduleManager.stateOf(moduleId) == prior) return;

    final previous = snapshot.state;
    await _moduleManager.adoptRestoredState(ModuleStateSnapshot(
      moduleId: moduleId,
      state: prior.name,
      installedVersion: previous?.installedVersion ?? '',
      enabled: prior == ModuleState.enabled,
      installedAt: previous?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _restoreStorage(ModuleSnapshot snapshot) async {
    final storage = _moduleManager.apiFor(snapshot.moduleId).storage;
    final expected = snapshot.storage;

    // Убрать всё, чего не было до операции.
    for (final key in await storage.keys()) {
      if (!expected.containsKey(key)) {
        await storage.remove(key);
      }
    }
    // Вернуть прежние значения перезаписанных ключей.
    for (final entry in expected.entries) {
      await storage.setString(entry.key, entry.value);
    }
  }

  Future<void> _restoreAssets(ModuleSnapshot snapshot) async {
    final dir = await resolveAssetsDirectory(snapshot.moduleId);
    final expected = snapshot.assets;

    if (await dir.exists()) {
      for (final entity in await dir.list().toList()) {
        if (entity is File) await entity.delete();
      }
    }
    if (expected.isEmpty) {
      if (!snapshot.assetsDirExisted && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (final entry in expected.entries) {
      await File(path.join(dir.path, entry.key)).writeAsBytes(entry.value);
    }
  }
}