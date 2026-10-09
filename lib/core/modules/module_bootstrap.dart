import 'module_registry.dart';
import '../../modules/example/example_module.dart';
import '../../modules/schedule/schedule_module.dart';
import '../../modules/accounts/accounts_module.dart';

/// Единственное место, где модули подключаются к приложению.
///
/// Чтобы добавить новый модуль в будущем: создать класс,
/// реализующий Module, в modules/<имя>/, и добавить его сюда
/// одной строкой. Ничего больше в ядре менять не нужно.
///
/// Этап 14 добавил первый настоящий функциональный модуль —
/// ScheduleModule — той же одной строкой, что и предсказывал этот
/// комментарий. Этап 10.1 добавил AccountsModule. Финансы/Файлы/AI/Бэкапы
/// по-прежнему запрещены.
void registerCoreModules() {
  ModuleRegistry.registerAll([
    ExampleModule(),
    ScheduleModule(),
    AccountsModule(),
  ]);
}
