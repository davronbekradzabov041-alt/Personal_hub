import 'module_manager.dart';
import 'module_state.dart';
import 'module_state_store.dart';

/// Модуль не удалось вернуть в сохранённое состояние при старте.
///
/// Наружу не бросается: один сбойный модуль не должен мешать запуску
/// остальных. Передаётся в [ModuleStateRestorer.onError] и собирается в
/// [ModuleStateRestorer.failures], чтобы сбой не оставался невидимым.
class ModuleRestoreException implements Exception {
  ModuleRestoreException(this.moduleId, this.error);

  final String moduleId;
  final Object error;

  @override
  String toString() => 'не удалось восстановить модуль $moduleId: $error';
}

/// Восстанавливает состояние модулей из хранилища в свежий
/// ModuleManager при старте приложения.
///
/// Работает ИСКЛЮЧИТЕЛЬНО через публичный API ModuleManager —
/// install()/enable()/disable(). module_manager.dart на Этапе 9 не
/// менялся: у него нет и не должно быть метода "выставить состояние
/// напрямую", потому что это обошло бы lifecycle-хуки, а они как раз
/// и нужны заново на каждый холодный старт — GlobalSearchService и
/// прочие in-memory сервисы тоже пересоздаются при каждом запуске,
/// не только ModuleManager, и должны получить свои SearchProvider
/// обратно через onEnable(), а не через восстановление "мёртвого" флага.
///
/// Побочный эффект этого решения: чтобы попасть в состояние disabled,
/// приходится пройти install → enable → disable — onEnable
/// выполняется и тут же гасится onDisable. По результату это корректно
/// (модуль оказывается disabled), но лишний проход хуков — не бесплатен.
/// Убрать его можно только добавив в ModuleManager отдельный метод
/// восстановления без хуков — то есть изменив запрещённый на этом
/// этапе файл.
///
/// Что restore() НЕ делает: он не трогает хранилище, кроме одного
/// случая — вернуть сохранённое намерение, если восстановление
/// сорвалось (см. [_restoreStoredIntent]). Промежуточные состояния
/// install() → enable() в хранилище не пишутся: вызывающий выполняет
/// restore() внутри ModuleStatePersistence.runRestoreTransaction(),
/// иначе persist-слой успел бы зафиксировать состояние `installed` как
/// пользовательское намерение.
class ModuleStateRestorer {
  ModuleStateRestorer(
    this._manager,
    this._store, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _onError = onError;

  final ModuleManager _manager;
  final ModuleStateStore _store;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  final List<ModuleRestoreException> _failures = [];

  /// Сбои последнего [restore] — по одному на модуль.
  List<ModuleRestoreException> get failures => List.unmodifiable(_failures);

  /// Сколько модулей не удалось восстановить в последнем [restore].
  int get failedCount => _failures.length;

  Future<void> restore() async {
    _failures.clear();
    final snapshots = await _store.loadAll();

    for (final snapshot in snapshots) {
      final moduleId = snapshot.moduleId;
      final state = _parseState(snapshot.state);

      try {
        switch (state) {
          case ModuleState.installed:
            await _manager.install(moduleId);
            break;
          case ModuleState.enabled:
            await _manager.install(moduleId);
            await _manager.enable(moduleId);
            break;
          case ModuleState.disabled:
            await _manager.install(moduleId);
            await _manager.enable(moduleId);
            await _manager.disable(moduleId);
            break;
          case ModuleState.uninstalled:
            // Не долечивать: uninstall удаляет запись из
            // хранилища (см. ModuleStatePersistence), а не помечает
            // её как uninstalled. На любой случай — просто пропускаем.
            break;
        }
      } catch (error, stackTrace) {
        // Модуль мог перестать быть зарегистрированным между запусками
        // (например, удалён из module_bootstrap.dart) — тогда install()
        // бросит ModuleLifecycleError. Один сломанный модуль не должен
        // мешать запуску остальных.
        //
        // Но молчать здесь нельзя. enable() вызывает хук модуля ДО
        // мутации состояния, поэтому упавший onEnable() оставляет модуль
        // в состоянии installed. Если persist-слой успел записать это
        // промежуточное состояние, сохранённое намерение «включён» исчезает
        // навсегда: следующий запуск прочитает installed и не станет
        // повторять попытку включения. Поэтому возвращаем в хранилище
        // снимок, который restore() уже прочитал, и сообщаем о сбое.
        await _restoreStoredIntent(snapshot);
        final failure = ModuleRestoreException(moduleId, error);
        _failures.add(failure);
        _onError?.call(failure, stackTrace);
      }
    }
  }

  /// Возвращает в хранилище снимок, прочитанный в начале restore(),
  /// если что-то успело его заменить.
  ///
  /// Корректность порядка обеспечивает вызывающий (main.dart): restore()
  /// выполняется внутри ModuleStatePersistence.runRestoreTransaction(),
  /// поэтому синхронизация не ставит в очередь записи промежуточных
  /// состояний и правка этого метода не может быть затёрта более поздней
  /// записью того же запуска.
  Future<void> _restoreStoredIntent(ModuleStateSnapshot snapshot) async {
    try {
      final current = await _store.load(snapshot.moduleId);
      if (current == null) return;
      if (current.state == snapshot.state && current.enabled == snapshot.enabled) {
        return;
      }
      await _store.save(snapshot);
    } catch (_) {
      // Хранилище недоступно — восстановить намерение нечем. Исходная
      // ошибка уже передана через onError, а вторичная её не уточнит.
    }
  }

  ModuleState _parseState(String value) {
    return ModuleState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ModuleState.uninstalled,
    );
  }
}
