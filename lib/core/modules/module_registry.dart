import 'module.dart';
import 'module_lifecycle_error.dart';

/// Реестр модулей.
///
/// Модули регистрируются сюда один раз при старте приложения
/// (см. module_bootstrap.dart) и дальше ядро (боковое меню,
/// в будущем — глобальный поиск) читает список отсюда, не
/// зная заранее, какие модули существуют.
///
/// Подключение/отключение модуля = добавление/удаление одной
/// строки в module_bootstrap.dart, без изменений в core/ или ui/.
class ModuleRegistry {
  ModuleRegistry._();

  static final List<Module> _modules = [];

  /// Зарегистрированные модули, отсортированные по order.
  static List<Module> get modules {
    final sorted = List<Module>.from(_modules)
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(sorted);
  }

  /// Регистрирует один модуль.
  ///
  /// Безопасен для повторного вызова с ТЕМ ЖЕ объектом (no-op —
  /// удобно, если бутстрап когда-нибудь вызовется дважды). Но если
  /// под уже занятым id пытаются зарегистрировать ДРУГОЙ объект —
  /// это конфликт id (например, внешний модуль, Этап 11, пытается
  /// выдать себя за встроенный) и он запрещён явной ошибкой, а не
  /// молча игнорируется. Это и есть проверка «уникальность moduleId»
  /// из требований Этапа 8 — она принадлежит реестру (месту, где
  /// код модуля становится известен приложению), а не ModuleManager
  /// (который работает с уже зарегистрированными модулями).
  static void register(Module module) {
    final existing = get(module.id);
    if (existing == null) {
      _modules.add(module);
      return;
    }
    if (identical(existing, module)) return; // тот же объект — не ошибка
    throw ModuleLifecycleError(
      module.id,
      'id уже занят другим зарегистрированным модулем '
      '("${existing.manifest.name}")',
    );
  }

  /// Регистрирует список модулей за один вызов.
  static void registerAll(List<Module> modules) {
    for (final module in modules) {
      register(module);
    }
  }

  /// Возвращает модуль по id, если он зарегистрирован.
  /// Нужно будущему ModuleManager (Этап 8) для проверок версий,
  /// зависимостей и получения информации о конкретном модуле.
  static Module? get(String id) {
    for (final module in _modules) {
      if (module.id == id) return module;
    }
    return null;
  }

  static bool contains(String id) => get(id) != null;

  /// Убирает модуль из реестра. Реестр только выполняет операцию —
  /// решение о том, МОЖНО ли удалять (зависимости, разрешения),
  /// принимает ModuleManager (Этап 8), не этот класс.
  static bool unregister(String id) {
    final index = _modules.indexWhere((m) => m.id == id);
    if (index == -1) return false;
    _modules.removeAt(index);
    return true;
  }

  /// Заменяет зарегистрированный модуль на версию с тем же id и
  /// возвращает ПРЕДЫДУЩИЙ модуль — как раз то, что нужно для отката.
  ///
  /// Почему не `unregister` + `register` (как делал update до Этапа 8):
  /// между двумя вызовами модуль в реестре отсутствует. Для
  /// синхронного кода окно почти незаметно, но оно настоящее — любой
  /// код, прочитавший реестр в этот момент (отрисовка меню,
  /// проверка зависимостей), увидел бы модуль, которого нет, а
  /// исключение от `register` оставило бы модуль вообще без кода.
  ///
  /// Здесь ровно одна мутация списка, и она не может упасть после
  /// частичного изменения: подготовку (валидацию) вызывающий делает
  /// ДО swap, поэтому старый модуль не теряется до готовности нового.
  ///
  /// Откат — это `swap(previous)`, то есть та же операция: идемпотентная
  /// и безопасная.
  static Module swap(Module replacement) {
    final moduleId = replacement.id;
    if (moduleId.trim().isEmpty) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя заменить модуль с пустым id',
      );
    }

    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) {
      // Не обычный случай: обновляется уже зарегистрированный модуль.
      // Но вызывать register() вместо swap() молча означало бы
      // «обновление», которое на деле установило модуль заново.
      throw ModuleLifecycleError(
        moduleId,
        'нечего заменять: модуль с таким id не зарегистрирован',
      );
    }

    final previous = _modules[index];
    _modules[index] = replacement;
    return previous;
  }

  /// Только для тестов — очищает реестр.
  static void clear() => _modules.clear();
}
