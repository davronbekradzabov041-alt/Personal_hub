import 'module_manager.dart';
import 'module_registry.dart';
import 'module_state_store.dart';

/// Итог автоустановки встроенных модулей при запуске.
///
/// Одна строка на модуль: установленный (и включённый) либо
/// неудавшийся с причиной. Отчёт нужен, чтобы вызывающий код
/// (main) мог сообщить о сбое, не роняя приложение: падение одного
/// модуля — это отсутствующий модуль, а не неработающее приложение.
class BuiltinInstallReport {
  const BuiltinInstallReport({
    required this.installed,
    required this.failed,
  });

  const BuiltinInstallReport.empty()
      : installed = const <String>[],
        failed = const <String>[];

  /// Модули, доехавшие до enabled.
  final List<String> installed;

  /// Модули, которые не удалось установить или включить.
  final List<String> failed;

  bool get hasFailures => failed.isNotEmpty;
  bool get isEmpty => installed.isEmpty && failed.isEmpty;
}

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
///
/// ## Сбой одного модуля не останавливает остальные
///
/// enable() бросает ModuleLifecycleError, если хук onEnable() модуля
/// упал (см. ModuleManager.enable). До Stage 11 это исключение
/// пролетало наверх и роняло _bootstrap() целиком: один сломанный
/// модуль делал неработоспособным всё приложение, хотя остальным
/// сломаться было нечему.
///
/// Поэтому каждый модуль обрабатывается независимо:
/// - install() идёт через tryInstall() — типизированный результат
///   без исключения, с собственным откатом внутри;
/// - enable() оборачивается в try/catch, и его сбой записывается в
///   отчёт, а цикл продолжается со следующим модулем;
/// - состояние сбойного модуля остаётся тем, что было ДО попытки:
///   откат делает сам ModuleManager (хук вызывается до мутации
///   состояния), здесь ничего не подделывается.
Future<BuiltinInstallReport> ensureBuiltinModulesInstalled(
  ModuleManager manager,
  ModuleStateStore store,
) async {
  final installed = <String>[];
  final failed = <String>[];

  for (final module in ModuleRegistry.modules) {
    final existing = await store.load(module.id);
    if (existing != null) {
      if (manager.isInstalled(module.id) && !manager.isEnabled(module.id)) {
        try {
          await manager.enable(module.id);
          installed.add(module.id);
        } on Object catch (_) {
          failed.add(module.id);
        }
      }
      continue;
    }

    final install = await manager.tryInstall(module.id);
    if (!install.isSuccess) {
      failed.add(module.id);
      continue;
    }

    try {
      await manager.enable(module.id);
      installed.add(module.id);
    } on Object catch (_) {
      // Модуль установлен, но не включён. Это законное состояние:
      // ModuleManager уже откатил состояние к тому, что было до
      // enable(), а пользователь может попробовать включить модуль
      // вручную со страницы «Модули» — там ошибка показывается
      // снэкбаром, а не экраном ошибки запуска.
      failed.add(module.id);
    }
  }

  return BuiltinInstallReport(installed: installed, failed: failed);
}
