import 'package:flutter/foundation.dart';

import 'external/manifest_validator.dart';
import '../search/global_search_service.dart';
import '../search/search_provider.dart';
import 'module.dart';
import 'module_api.dart';
import 'module_install_result.dart';
import 'module_lifecycle_error.dart';
import 'module_manifest.dart';
import 'module_permission.dart';
import 'module_registry.dart';
import 'module_state.dart';
import 'module_state_store.dart';
import 'module_storage.dart';
import 'module_storage_isar.dart';
import 'module_update_validator.dart';
import 'module_version.dart';

/// Оркестратор жизненного цикла модулей.
///
/// Владеет состоянием (`ModuleState`) каждого модуля — сам `Module`
/// о своём состоянии не знает (см. Этап 7). Работает поверх уже
/// существующего `ModuleRegistry` (каталог того, чей код известен
/// приложению) — не создаёт второй реестр, только добавляет слой
/// состояния и проверок над ним.
///
/// `ChangeNotifier` — по аналогии с `AppSettingsController`
/// (см. итоги аудита Этапа 6): это архитектурный ориентир, а не
/// копирование кода. Подключён в main.dart/app.dart начиная с
/// Этапа 10 (до Этапа 9 подключать было рано — не было персистентности,
/// состояние сбрасывалось бы при каждом перезапуске).
///
/// Этап 13 (аудит безопасности) добавил: проверку apiVersion/формата
/// версии/зависимостей/циклов при install, откат (rollback) при
/// неудачном install/enable/disable, типизированный результат
/// установки (ModuleInstallResult) — ничего из публичного контракта
/// install/enable/disable/uninstall/update не удалено и не изменило
/// сигнатуру, только добавлены новые проверки внутри и новый
/// параллельный метод tryInstall().
class ModuleManager extends ChangeNotifier {
  ModuleManager({
    required GlobalSearchService searchService,
    ModuleStorage Function(String moduleId)? storageFactory,
    ModuleUpdateValidator? updateValidator,
  })  : _searchService = searchService,
        _storageFactory = storageFactory ?? ModuleStorageIsar.new,
        _updateValidator = updateValidator ?? ModuleUpdateValidator();

  final GlobalSearchService _searchService;

  /// Проверки обновления (Этап 8.1-А). Внедряются, чтобы политика
  /// отката была задаваемой в одном месте, а не размазанной по
  /// вызывающим: по умолчанию откат версии запрещён.
  final ModuleUpdateValidator _updateValidator;

  /// Валидатор обновления, действующий в этом менеджере.
  ///
  /// Открыт наружу для проверки плана ДО попытки обновления (UI
  /// Этапа 8.1-Б показывает, что именно не так, не начиная обновления).
  ModuleUpdateValidator get updateValidator => _updateValidator;

  /// Фабрика хранилища модуля — по умолчанию настоящий Isar-backed
  /// ModuleStorageIsar (Этап 9/10). Параметр — не смена архитектуры,
  /// а то, что нужно, чтобы Этап 13 мог написать тест на rollback,
  /// который реально проверяет, что частично записанные данные
  /// стираются, не трогая настоящую базу (которой в этой среде и
  /// быть не может — нет Flutter/Dart SDK для кодогенерации Isar).
  final ModuleStorage Function(String moduleId) _storageFactory;

  /// Состояние каждого модуля по его id. Отсутствие ключа means
  /// «модуль никогда не устанавливался» — не то же самое, что
  /// ModuleState.uninstalled (модуль был установлен и удалён).
  final Map<String, ModuleState> _states = {};

  /// Один ModuleApi (и одно хранилище) на модуль, переиспользуется
  /// между вызовами хуков — иначе onInstall и onEnable одного модуля
  /// видели бы разные объекты ModuleStorage.
  final Map<String, ModuleApi> _apiCache = {};

  // --- Наблюдение за состоянием (для будущего UI/тестов) ---

  ModuleState? stateOf(String moduleId) => _states[moduleId];

  bool isInstalled(String moduleId) {
    final state = _states[moduleId];
    return state != null && state != ModuleState.uninstalled;
  }

  bool isEnabled(String moduleId) => _states[moduleId] == ModuleState.enabled;

  /// Снимок состояний всех модулей, когда-либо тронутых менеджером.
  Map<String, ModuleState> get states => Map.unmodifiable(_states);

  /// Тестовый метод: устанавливает состояние модуля напрямую без Isar.
  /// Только для тестов! Не использовать в продакшн-коде.
  @visibleForTesting
  void setStateForTesting(String moduleId, ModuleState state) {
    _states[moduleId] = state;
    notifyListeners();
  }

  // --- Жизненный цикл ---

  /// Обратно совместимая обёртка над tryInstall() — бросает
  /// ModuleLifecycleError при отказе вместо возврата результата.
  /// Существующие вызывающие (Этапы 8/10/12, ModuleStateRestorer,
  /// builtin_module_installer) ловят именно это исключение — их
  /// код на Этапе 13 не менялся ни строкой, только этот метод стал
  /// тоньше и делегирует всю логику в tryInstall().
  Future<void> install(String moduleId) async {
    final result = await tryInstall(moduleId);
    if (!result.isSuccess) {
      throw ModuleLifecycleError(
        moduleId,
        result.violations.isEmpty
            ? (result.reason ?? 'ошибка установки')
            : '${result.reason}: ${result.violations.join("; ")}',
      );
    }
  }

  /// installed: модуль должен быть уже известен ModuleRegistry и ещё
  /// не установлен. Возвращает типизированный результат вместо
  /// исключения (Этап 13, п. 5 — "не использовать Exception там, где
  /// нужен типизированный результат").
  ///
  /// Проверки, добавленные на Этапе 13 (ничего из этого не было на
  /// Этапе 8): пустой id (defense-in-depth), формат версии,
  /// совместимость apiVersion, невыполненные зависимости, циклы в
  /// графе зависимостей. Если onInstall() модуля бросает исключение —
  /// откат: состояние возвращается к тому, что было ДО попытки, а
  /// хранилище модуля, если хук успел туда что-то записать, стирается.
  Future<ModuleInstallResult> tryInstall(String moduleId) async {
    final module = ModuleRegistry.get(moduleId);
    if (module == null) {
      return ModuleInstallResult.failure(
        moduleId,
        reason: 'модуль не зарегистрирован в ModuleRegistry',
      );
    }

    if (module.id.trim().isEmpty) {
      // Не должно случиться через ManifestParser (Этап 11), но
      // Module можно создать и в обход парсера — defense-in-depth.
      return ModuleInstallResult.failure(
        moduleId,
        reason: 'у модуля пустой id',
      );
    }

    final priorState = _states[moduleId];
    if (priorState != null && priorState != ModuleState.uninstalled) {
      return ModuleInstallResult.failure(
        moduleId,
        reason: 'модуль уже установлен (текущее состояние: ${priorState.name})',
      );
    }

    final violations = _validateForInstall(module);
    if (violations.isNotEmpty) {
      return ModuleInstallResult.failure(
        moduleId,
        reason: 'установка отклонена проверками безопасности',
        violations: violations,
      );
    }

    try {
      await module.onInstall(_apiFor(module));
    } catch (error) {
      await _rollbackFailedInstall(moduleId, priorState);
      return ModuleInstallResult.failure(
        moduleId,
        reason: 'onInstall завершился с ошибкой: $error',
      );
    }

    _states[moduleId] = ModuleState.installed;
    notifyListeners();
    return ModuleInstallResult.success(moduleId);
  }

  /// enabled: модуль должен быть installed или disabled.
  /// Нельзя включить то, что не установлено, — отдельная явная
  /// проверка, как отдельно потребовано в задаче Этапа 8.
  ///
  /// Этап 13: если onEnable() бросает исключение (например,
  /// registerSearchProvider() отказал из-за отсутствия разрешения —
  /// это реальный, а не гипотетический путь, см. _ModuleApiImpl
  /// ниже), состояние откатывается к тому, что было до вызова —
  /// раньше оно оставалось "enabled" даже при упавшем хуке.
  Future<void> enable(String moduleId) async {
    final module = _requireRegistered(moduleId);
    final priorState = _states[moduleId];

    if (priorState == null || priorState == ModuleState.uninstalled) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя включить неустановленный модуль — сначала install()',
      );
    }
    if (priorState == ModuleState.enabled) {
      throw ModuleLifecycleError(moduleId, 'модуль уже включён');
    }

    await module.onEnable(_apiFor(module));

    _states[moduleId] = ModuleState.enabled;
    notifyListeners();
  }

  /// disabled: модуль должен быть enabled.
  /// Этап 13: та же перестановка порядка, что и в enable() — хук
  /// вызывается ДО мутации состояния, а не после.
  Future<void> disable(String moduleId) async {
    final module = _requireRegistered(moduleId);
    final priorState = _states[moduleId];

    if (priorState != ModuleState.enabled) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя выключить модуль в состоянии '
        '${priorState?.name ?? "не установлен"} — модуль не включён',
      );
    }

    await module.onDisable(_apiFor(module));

    _states[moduleId] = ModuleState.disabled;
    notifyListeners();
  }

  /// uninstalled: модуль должен быть installed или disabled.
  /// Удаление включённого модуля запрещено напрямую — сначала
  /// disable(), чтобы модуль гарантированно успел отписаться от
  /// поиска и т.п. до того, как его пометят удалённым. Это и есть
  /// «корректная последовательность жизненного цикла».
  ///
  /// Безопасное удаление (Этап 13, п. 4): хук вызывается первым (как
  /// и раньше — здесь порядок уже был правильным), а persist-слой
  /// (ModuleStatePersistence, Этап 9, подписан на notifyListeners()
  /// и не менялся) стирает запись состояния И все key-value данные
  /// модуля (ModuleDataRow, отфильтрованные по этому moduleId — ядро
  /// и другие модули хранятся в других строках/коллекциях и не
  /// затрагиваются никаким из этих вызовов).
  Future<void> uninstall(String moduleId) async {
    final module = _requireRegistered(moduleId);
    final current = _states[moduleId];

    if (current != ModuleState.installed && current != ModuleState.disabled) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя удалить модуль в состоянии '
        '${current?.name ?? "не установлен"} — если модуль включён, '
        'сначала disable()',
      );
    }

    await module.onUninstall(_apiFor(module));
    _states[moduleId] = ModuleState.uninstalled;
    _apiCache.remove(moduleId);
    notifyListeners();

    // Примечание: код модуля из ModuleRegistry НЕ убираем. Для
    // встроенного модуля он всё равно скомпилирован в приложение —
    // «удаление» здесь про состояние и данные, не про стирание кода.
  }

  /// Минимальное обновление: подменяет реализацию модуля в
  /// ModuleRegistry той же id, не меняя текущее состояние
  /// жизненного цикла (installed/enabled/disabled — как было).
  ///
  /// Этап 8.1-А: проверки вынесены в ModuleUpdateValidator, обмен —
  /// в ModuleRegistry.swap. Здесь остаётся только разворот отказа
  /// плана в ModuleLifecycleError, потому что сигнатура update()
  /// задана вызывающими Этапов 10/12, а менять её без необходимости
  /// нельзя.
  ///
  /// Чего здесь по-прежнему НЕТ (Этап 8.1-Б): миграции сохранённых
  /// данных, `onUpdate`-хука, обмена песочницы внешнего модуля,
  /// notion «обновление в процессе» и UI. Ничего из этого не
  /// симулируется: подменяется ТОЛЬКО объект в реестре, хранилище и
  /// состояние не трогаются.
  ///
  /// Отката как отдельного шага здесь нет не по недосмотру: swap —
  /// одна мутация списка, которая не бросает после частичного
  /// изменения. Если подготовка (валидация) не прошла, реестр не
  /// тронут вовсе, а если прошла — обмен уже состоялся, и
  /// ModuleRegistry.swap(previous) возвращает всё как было.
  Future<void> update(Module newVersion) async {
    final moduleId = newVersion.id;
    final current = _states[moduleId];

    if (current == null || current == ModuleState.uninstalled) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя обновить модуль, который не установлен',
      );
    }

    final old = ModuleRegistry.get(moduleId);
    if (old == null) {
      // Не должно происходить, если состояние есть, но проверяем —
      // рассинхронизация ModuleManager/ModuleRegistry это и есть один
      // из случаев, которые должна ловить архитектура проверок.
      throw ModuleLifecycleError(moduleId, 'модуль не найден в ModuleRegistry');
    }

    final plan = _updateValidator.validate(
      newManifest: newVersion.manifest,
      currentManifest: old.manifest,
      currentState: current,
      installedManifests: [
        for (final module in ModuleRegistry.modules)
          if (module.id != moduleId) module.manifest,
      ],
    );
    if (!plan.isAccepted) {
      throw updateRejectionToError(plan);
    }

    ModuleRegistry.swap(newVersion);
    // Состояние (installed/enabled/disabled) намеренно сохраняется
    // как было — update не должен незаметно "включать" или
    // "выключать" модуль. Хуки onInstall/onEnable заново не зовутся.
    notifyListeners();
  }

  // --- Восстановление состояния из внешнего источника ---

  /// Принимает состояние, восстановленное из внешнего источника (архив
  /// `.pmb`), как АВТОРИТЕТНОЕ состояние модуля.
  ///
  /// Зачем отдельный вход, если есть install/enable/disable: переход
  /// `enabled → installed` невыразим через них. uninstall() + install()
  /// стёрли бы только что восстановленные данные (uninstall отдаёт
  /// tombstone, на который ModuleStatePersistence реагирует очисткой
  /// всех данных модуля), а «молча выставить installed» без хуков
  /// оставило бы активный модуль активным: его SearchProvider остался бы
  /// зарегистрированным в GlobalSearchService при состоянии «не активен».
  ///
  /// Отсюда семантика: ось «активен / не активен» проходит через
  /// настоящие lifecycle-хуки (onEnable/onDisable), а уже ПОСЛЕ них
  /// переносится точное состояние из снимка. Поэтому результат — одна
  /// транзакция с одним notifyListeners(), а не цепочка промежуточных
  /// состояний.
  ///
  /// Источник истины остаётся один: состояние живёт в [_states], а
  /// ModuleStatePersistence расходится по нему сам, услышав
  /// notifyListeners(). Метод не пишет в ModuleStateStore напрямую —
  /// иначе получилось бы ровно то рассогласование, которое он и
  /// устраняет.
  ///
  /// Отклоняет (ModuleLifecycleError):
  ///
  /// * пустой moduleId;
  /// * модуль, которого нет в ModuleRegistry — восстановление состояния
  ///   не оживляет модуль, это делает install();
  /// * неизвестное имя состояния;
  /// * `uninstalled` — это только результат uninstall(). Принять его
  ///   здесь значило бы записать tombstone и стереть данные модуля,
  ///   тогда как .pmb restore восстанавливает данные, а не удаляет их;
  /// * модуль, который сейчас не установлен (состояния нет или оно
  ///   uninstalled) — принять для него состояние значило бы выполнить
  ///   переход, которого не было.
  ///
  /// Повторное принятие уже текущего состояния — не ошибка и не
  /// уведомление: ничего не меняется.
  Future<void> adoptRestoredState(ModuleStateSnapshot snapshot) async {
    final moduleId = snapshot.moduleId;

    if (moduleId.trim().isEmpty) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя принять состояние модуля с пустым id',
      );
    }

    final module = _requireRegistered(moduleId);

    final target = _parseState(snapshot.state);
    if (target == null) {
      throw ModuleLifecycleError(
        moduleId,
        'неизвестное состояние "${snapshot.state}"',
      );
    }

    if (target == ModuleState.uninstalled) {
      throw ModuleLifecycleError(
        moduleId,
        'восстановление не может вернуть модуль в uninstalled — '
        'это состояние только uninstall(), иначе данные модуля будут стёрты',
      );
    }

    final current = _states[moduleId];
    if (current == null || current == ModuleState.uninstalled) {
      throw ModuleLifecycleError(
        moduleId,
        'нельзя принять восстановленное состояние для неустановленного модуля',
      );
    }

    if (current == target) return;

    if (current != ModuleState.enabled && target == ModuleState.enabled) {
      // installed/disabled → enabled: обычный lifecycle целиком,
      // включая его собственные проверки и откат при ошибке onEnable.
      await enable(moduleId);
      return;
    }

    if (current == ModuleState.enabled && target != ModuleState.enabled) {
      // enabled → installed/disabled: onDisable обязателен, иначе
      // SearchProvider модуля останется в GlobalSearchService, а
      // состояние скажет, что модуль не активен. Если хук бросит
      // исключение, состояние не меняется вовсе.
      await module.onDisable(_apiFor(module));
    }

    // enabled → installed и installed ↔ disabled: модуль и до, и после
    // перехода не активен, хуков нет — меняется только пометка.
    _states[moduleId] = target;
    notifyListeners();
  }

  /// Имя состояния → ModuleState, либо null, если такого имени нет.
  ///
  /// Строгое сравнение с [ModuleState.name] — тем же контрактом, которым
  /// состояние записывается в хранилище (ModuleState.name) и читается
  /// обратно (ModuleStateRestorer).
  static ModuleState? _parseState(String value) {
    for (final state in ModuleState.values) {
      if (state.name == value) return state;
    }
    return null;
  }

  // --- Внутренние проверки ---

  Module _requireRegistered(String moduleId) {
    final module = ModuleRegistry.get(moduleId);
    if (module == null) {
      throw ModuleLifecycleError(
        moduleId,
        'модуль не зарегистрирован в ModuleRegistry',
      );
    }
    return module;
  }

  /// Формат версии — тот же, что у ModuleVersion и ModuleUpdateValidator:
  /// одно правило на всех, иначе «валидная версия» означала бы разное в
  /// установке и в обновлении.
  static final RegExp _versionPattern = ModuleVersion.pattern;

  /// Все проверки, которые должны провалить install() (Этап 13,
  /// пп. 1–2). Возвращает список нарушений — специально не
  /// останавливается на первом, чтобы вызывающий видел все проблемы
  /// сразу (тот же принцип, что и в ManifestValidator, Этап 11).
  List<String> _validateForInstall(Module module) {
    final violations = <String>[];
    final manifest = module.manifest;

    if (!_versionPattern.hasMatch(manifest.version)) {
      violations.add(
        'неверный формат версии: "${manifest.version}" '
        '(ожидается major.minor.patch, например 1.0.0)',
      );
    }

    if (manifest.apiVersion < 1 || manifest.apiVersion > kCoreModuleApiVersion) {
      violations.add(
        'несовместимая версия Module API: ${manifest.apiVersion} '
        '(ядро поддерживает версии 1..$kCoreModuleApiVersion)',
      );
    }

    final missingDeps = manifest.dependencies
        .where((dep) => !isEnabled(dep.moduleId))
        .map((dep) => dep.moduleId)
        .toList();
    if (missingDeps.isNotEmpty) {
      violations.add('не выполнены зависимости: ${missingDeps.join(", ")}');
    }

    final cycles = _dependencyCycles(module);
    if (cycles.isNotEmpty) {
      violations.add('циклические зависимости: ${cycles.join("; ")}');
    }

    return violations;
  }

  /// Строит граф зависимостей из ВСЕХ модулей, уже известных
  /// ModuleRegistry, плюс проверяемый модуль, и ищет циклы через уже
  /// существующий ManifestValidator.findDependencyCycles (Этап 11) —
  /// не дублирует алгоритм поиска циклов, только строит граф для него.
  ///
  /// Практически сейчас граф всегда тривиален: ни один реальный
  /// модуль в приложении не объявляет зависимостей. Проверка тем не
  /// менее реальная, не заглушка — активируется, как только у
  /// какого-нибудь модуля появятся dependencies (тест использует
  /// синтетические модули именно для этого).
  List<String> _dependencyCycles(Module module) {
    final graph = <String, List<String>>{
      for (final m in ModuleRegistry.modules)
        m.id: m.manifest.dependencies.map((d) => d.moduleId).toList(),
    };
    graph[module.id] = module.manifest.dependencies.map((d) => d.moduleId).toList();

    return ManifestValidator().findDependencyCycles(graph);
  }

  /// Rollback неудачного install() (Этап 13, п. 3): состояние
  /// возвращается к тому, что было ДО попытки (null или uninstalled —
  /// install() допускает только эти два варианта на входе), а всё,
  /// что onInstall() успел записать в своё хранилище до того, как
  /// упасть, стирается — не оставляем частично установленный модуль.
  Future<void> _rollbackFailedInstall(
    String moduleId,
    ModuleState? priorState,
  ) async {
    if (priorState == null) {
      _states.remove(moduleId);
    } else {
      _states[moduleId] = priorState;
    }

    final api = _apiCache.remove(moduleId);
    if (api != null) {
      for (final key in await api.storage.keys()) {
        await api.storage.remove(key);
      }
    }
  }

  /// Публичный доступ к ModuleApi модуля — нужен странице самого
  /// модуля (Этап 10), чтобы читать/писать свои настройки через
  /// ModuleApi.storage, не имея собственной ссылки на ModuleManager
  /// внутри buildPage(). Тот же кэшированный экземпляр, что получают
  /// lifecycle-хуки — не новый объект на каждый вызов.
  ModuleApi apiFor(String moduleId) {
    final module = _requireRegistered(moduleId);
    return _apiFor(module);
  }

  ModuleApi _apiFor(Module module) {
    return _apiCache.putIfAbsent(
      module.id,
      () => _ModuleApiImpl(
        module: module,
        storage: _storageFactory(module.id),
        searchService: _searchService,
      ),
    );
  }
}

/// Реализация ModuleApi, которую ModuleManager передаёт в хуки.
///
/// Приватная — модули работают с ней только через контракт ModuleApi
/// (Этап 7), не зная о ModuleManager вообще.
class _ModuleApiImpl implements ModuleApi {
  _ModuleApiImpl({
    required this.module,
    required this.storage,
    required GlobalSearchService searchService,
  }) : _searchService = searchService;

  final Module module;
  final GlobalSearchService _searchService;

  @override
  final ModuleStorage storage;

  @override
  void registerSearchProvider(SearchProvider provider) {
    _checkPermission(ModulePermission.coreSearch);
    _searchService.registerProvider(provider);
  }

  @override
  void unregisterSearchProvider(SearchProvider provider) {
    // Отписка не требует повторной проверки разрешения — модуль,
    // у которого разрешение отозвали, всё равно должен суметь
    // убрать за собой ранее зарегистрированные результаты.
    _searchService.unregisterProvider(provider);
  }

  void _checkPermission(ModulePermission permission) {
    if (!module.manifest.permissions.contains(permission)) {
      throw ModuleLifecycleError(
        module.id,
        'нет разрешения "$permission" в манифесте',
      );
    }
  }
}
