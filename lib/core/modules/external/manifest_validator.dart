import '../module_manifest.dart';
import '../platform/module_sandbox.dart';
import '../platform/sandbox_exceptions.dart';

/// Семантическая проверка уже разобранного ModuleManifest.
///
/// Отдельно от ManifestParser: то, что проверяет этот класс, требует
/// контекста, которого нет в самом JSON — например, какие id уже
/// заняты. Разбор и проверка — разные обязанности, поэтому разные
/// классы (как и требовало условие Этапа 11).
///
/// validate() возвращает список ошибок, а не бросает исключение на
/// первой же: для внешнего, недоверенного пакета полезнее показать
/// сразу все нарушения, а не заставлять исправлять их по одному за
/// попытку импорта.
class ManifestValidator {
  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Проверяет один манифест. Пустой список — манифест валиден.
  List<String> validate(
    ModuleManifest manifest, {
    required Set<String> existingModuleIds,
  }) {
    final errors = <String>[];

    // Пустой id: ManifestParser уже отсекает его на уровне JSON через
    // ModuleManifest.fromJson (requireString бросает при пустой
    // строке) — но манифест сюда может попасть и не через парсер
    // (например, из теста или другого источника), так что проверка
    // здесь — не дубликат бизнес-правила, а defense-in-depth на
    // границе класса, который ничего не может предполагать о том,
    // как manifest был получен.
    if (manifest.id.trim().isEmpty) {
      errors.add('id пустой');
    } else {
      // Формат id — не бизнес-правило модуля, а требование безопасности
      // песочницы: id подставляется в filesystem path. Правила не
      // дублируются, а берутся из ModuleSandbox.validateModuleId — того же
      // источника, которым пользуется сам ModuleSandbox при построении
      // директорий. Здесь нужен именно список строк, а не исключение,
      // поэтому исключение превращается в violation.
      try {
        ModuleSandbox.validateModuleId(manifest.id);
      } on InvalidModuleIdException catch (e) {
        errors.add('недопустимый moduleId: ${e.reason}');
      }
    }

    // Формат версии (Этап 13): ManifestParser проверяет только, что
    // version — непустая строка, не её форму. Строгий major.minor.patch
    // — тот же паттерн, что ModuleManager.tryInstall() проверяет ещё
    // раз перед install() (Этап 13) — defense-in-depth на двух разных
    // границах (валидация пакета и сама установка).
    if (!_versionPattern.hasMatch(manifest.version)) {
      errors.add(
        'неверный формат версии: "${manifest.version}" '
        '(ожидается major.minor.patch, например 1.0.0)',
      );
    }

    if (manifest.apiVersion < 1 || manifest.apiVersion > kCoreModuleApiVersion) {
      errors.add(
        'неподдерживаемая версия Module API: ${manifest.apiVersion} '
        '(ядро поддерживает версии 1..$kCoreModuleApiVersion)',
      );
    }

    if (existingModuleIds.contains(manifest.id)) {
      errors.add(
        'id "${manifest.id}" уже занят другим установленным модулем',
      );
    }

    return errors;
  }

  /// Ищет циклы в графе зависимостей модулей: moduleId → список id,
  /// от которых он зависит.
  ///
  /// Специально НЕ принимает ModuleManifest напрямую — принимает уже
  /// свёрнутый граф, потому что для поиска циклов нужны зависимости
  /// ВСЕХ модулей сразу, а не одного манифеста. Сейчас в приложении
  /// граф пуст (у ExampleModule нет зависимостей, других модулей ещё
  /// нет) — это архитектура на будущее, подготовленная по прямому
  /// требованию Этапа 11, а не мёртвый код: она уже протестирована
  /// на синтетических графах (см. тесты) и готова к подключению, как
  /// только появится реальный источник графа (после импорта нескольких
  /// внешних модулей, не на этом этапе).
  List<String> findDependencyCycles(Map<String, List<String>> graph) {
    final cycles = <String>[];
    final visited = <String>{};
    final onStack = <String>{};
    final stack = <String>[];

    void visit(String node) {
      if (onStack.contains(node)) {
        final start = stack.indexOf(node);
        final cyclePath = [...stack.sublist(start), node];
        cycles.add(cyclePath.join(' → '));
        return;
      }
      if (visited.contains(node)) return;

      visited.add(node);
      onStack.add(node);
      stack.add(node);

      for (final dependency in graph[node] ?? const <String>[]) {
        visit(dependency);
      }

      stack.removeLast();
      onStack.remove(node);
    }

    for (final node in graph.keys) {
      visit(node);
    }

    return cycles;
  }
}
