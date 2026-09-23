import 'module_manager.dart';
import 'module_state.dart';
import 'module_state_store.dart';

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
class ModuleStateRestorer {
  ModuleStateRestorer(this._manager, this._store);

  final ModuleManager _manager;
  final ModuleStateStore _store;

  Future<void> restore() async {
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
            // Не должно встречаться: uninstall удаляет запись из
            // хранилища (см. ModuleStatePersistence), а не помечает
            // её uninstalled. На всякий случай — просто пропускаем.
            break;
        }
      } catch (_) {
        // Модуль мог перестать быть зарегистрирован между запусками
        // (например, убрали из module_bootstrap.dart) — тогда
        // install() бросит ModuleLifecycleError. Один сломанный
        // модуль не должен останавливать восстановление остальных
        // или запуск приложения.
      }
    }
  }

  ModuleState _parseState(String value) {
    return ModuleState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ModuleState.uninstalled,
    );
  }
}
