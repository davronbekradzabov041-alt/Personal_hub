import 'module_manager.dart';
import 'module_registry.dart';
import 'module_state_store.dart';

/// Автоматическая установка встроенных модулей при первом запуске.
///
/// Все модули, зарегистрированные в ModuleRegistry сейчас (Этап 10),
/// по определению встроенные — их код скомпилирован в приложение
/// через module_bootstrap.dart. Отличать встроенные от внешних по
/// какому-то отдельному признаку понадобится только на Этапе 11,
/// когда появится второй источник регистрации; сейчас в этом нет
/// смысла — любой зарегистрированный модуль обрабатывается одинаково.
///
/// Вызывается один раз при старте, ПОСЛЕ ModuleStateRestorer.restore():
/// если у модуля уже есть сохранённая запись состояния — значит, он
/// когда-то уже проходил через install(), и повторно устанавливать
/// его не нужно (это и есть «install работает один раз» из задачи
/// Этапа 10). Если записи нет — это первый запуск для этого модуля,
/// и он устанавливается и сразу включается.
Future<void> ensureBuiltinModulesInstalled(
  ModuleManager manager,
  ModuleStateStore store,
) async {
  for (final module in ModuleRegistry.modules) {
    final existing = await store.load(module.id);
    if (existing != null) continue; // уже был установлен раньше

    await manager.install(module.id);
    await manager.enable(module.id);
  }
}
