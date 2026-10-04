import 'module_manager.dart';
import 'module_registry.dart';
import 'module_state.dart';
import 'module_state_store.dart';
import 'module_storage.dart';
import 'module_storage_isar.dart';

/// Состояние модуля изменилось в памяти, но не было сохранено.
///
/// Бросается из [ModuleStatePersistence.runAndFlush]. Операция (например
/// uninstall) при этом выполнена — модуль уже не активен в текущей
/// сессии, — но её состояние не переживёт перезапуск, и пользователь
/// должен узнать об этом, а не обнаружить потерянный модуль завтра.
class ModuleStatePersistenceException implements Exception {
  ModuleStatePersistenceException(this.reason);

  /// Текст для показа пользователю, без стектрейса.
  final String reason;

  @override
  String toString() => reason;
}

/// Синхронизирует состояние ModuleManager с постоянным хранилищем
/// (Isar) на каждое изменение.
///
/// НЕ содержит ни строки изменений в module_manager.dart — этот файл
/// запрещено трогать на Этапе 9. Вместо этого подписывается на уже
/// существующий ChangeNotifier: ModuleManager и так вызывает
/// notifyListeners() после install/enable/disable/uninstall/update
/// (см. Этап 8) — этого достаточно, чтобы реагировать на все пять
/// операций извне, не меняя оркестратор.
///
/// На каждое уведомление — простая полная пересинхронизация всех
/// известных менеджеру модулей, а не точечный diff одного изменения:
/// проще, корректнее, и оправдано тем, что модулей ожидается немного.
/// Точечную оптимизацию можно добавить позже, не меняя это поведение.
///
/// Записи выполняются СТРОГО ПО ОЧЕРЕДИ. Раньше каждое уведомление
/// порождало независимый fire-and-forget `_sync()`, и две записи могли
/// завершиться в обратном порядке: tombstone `uninstalled`, запущенный
/// раньше, оказывался перезаписан более поздним снимком состояния —
/// и на холодном старте модуль воскресал. Теперь каждая синхронизация
/// стартует только после завершения предыдущей, поэтому порядок
/// notifyListeners() совпадает с порядком записи в хранилище.
class ModuleStatePersistence {
  ModuleStatePersistence(
    this._manager,
    this._store, {
    ModuleStorage Function(String moduleId)? storageFactory,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _storageFactory = storageFactory ?? ModuleStorageIsar.new,
        _onError = onError {
    _manager.addListener(_onManagerChanged);
  }

  final ModuleManager _manager;
  final ModuleStateStore _store;
  final ModuleStorage Function(String moduleId) _storageFactory;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  /// Хвост очереди записей. Никогда не завершается с ошибкой: ошибка
  /// перехватывается и передаётся дальше, иначе один сбой записи
  /// сломала бы всю последующую очередь.
  ///
  /// Именно null, а не `Future<void>.value()`: готовая Future,
  /// созданная в конструкторе, «привязывает» цепочку к zone
  /// конструирования. Если объект создан вне FakeAsync-зоны
  /// (обычный setUp теста), а использоваться начинает внутри
  /// `testWidgets()`, продолжение `await` внутри _sync() уже не
  /// получает управления — такая цепочка навсегда зависает.
  /// Начиная цепочку лениво, мы всегда остаёмся в zone вызова.
  Future<void>? _tail;

  Object? _lastError;
  StackTrace? _lastErrorStack;
  int _syncCount = 0;
  int _errorCount = 0;

  /// Последняя ошибка фоновой записи, если она была.
  Object? get lastError => _lastError;

  /// Сколько раз ошибка записи была перехвачена (для диагностики).
  int get errorCount => _errorCount;

  /// Сколько раз синхронизация была поставлена в очередь.
  int get syncCount => _syncCount;

  /// Стек последней ошибки фоновой записи, если она была.
  StackTrace? get lastErrorStack => _lastErrorStack;

  void dispose() {
    _manager.removeListener(_onManagerChanged);
  }

  void _onManagerChanged() {
    // notifyListeners() у ChangeNotifier синхронный — запись в
    // хранилище идёт асинхронно "в фоне"; ошибка записи не должна
    // ронять поток, вызвавший install()/enable()/... . Ошибка не
    // теряется: она попадает в [lastError] и в [onError].
    _enqueueSync();
  }

  /// Ставит синхронизацию в конец очереди.
  ///
  /// Возвращаемое Future намеренно не ожидается: результат доступен
  /// через [flush] и [lastError].
  void _enqueueSync() {
    _syncCount++;
    final previous = _tail;
    final next = previous == null
        ? _sync()
        : previous.then((_) => _sync());
    _tail = next.catchError(_handleError);
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _lastError = error;
    _lastErrorStack = stackTrace;
    _errorCount++;
    _onError?.call(error, stackTrace);
  }

  /// Дожидается завершения всех поставленных в очередь записей.
  ///
  /// Нужен там, где результат записи обязателен: uninstall (tombstone),
  /// disable и холодный старт. Цикл, а не один await, потому что за
  /// время ожидания могут прийти новые уведомления — flush() обязан
  /// дождаться и их.
  ///
  /// Ошибки не бросаются: они уже перехвачены и доступны через
  /// [lastError], чтобы flush() можно было вызывать из обработчика
  /// отмены/уничтожения, где rethrow ничего полезного не даст.
  /// Если вызывающему важно узнать о провале записи, используйте
  /// [runAndFlush] — он это делает.
  Future<void> flush() async {
    while (true) {
      final pending = _tail;
      if (pending == null) return;
      await pending;
      if (identical(pending, _tail)) return;
    }
  }

  /// Выполняет критическую lifecycle-операцию и дожидается, пока её
  /// состояние действительно записано.
  ///
  /// Зачем это нужно: ModuleManager.notifyListeners() синхронен, а
  /// запись в хранилище — асинхронна. Поэтому `await
  /// manager.uninstall(id)` возвращался ДО того, как tombstone
  /// `uninstalled` оказался в Isar. Между этими двумя моментами
  /// процесс можно завершить (пользователь смахнул приложение, ОС
  /// убила процесс), и модуль воскресал при следующем старте.
  ///
  /// Здесь операция считается выполненной только после успешного
  /// сохранения:
  ///
  /// * [operation] выполняется как есть — её исключения (ModuleLifecycleError
  ///   и прочие) пробрасываются вызывающему без изменений;
  /// * затем [flush] дожидается ВСЕХ записей, поставленных в очередь
  ///   во время операции, — FIFO-порядок не нарушается;
  /// * если запись не удалась, бросается [ModuleStatePersistenceException]:
  ///   молчаливо «успешный» uninstall, чей tombstone не записан, хуже
  ///   явной ошибки — молчание скрыло бы потерю состояния.
  ///
  /// [operation] не должна сама вызывать [flush]: достаточно одного
  /// ожидания здесь, лишние вызовы лишь удлиняют цепочку.
  Future<void> runAndFlush(Future<void> Function() operation) async {
    final errorsBefore = _errorCount;

    await operation();
    await flush();

    if (_errorCount != errorsBefore) {
      throw ModuleStatePersistenceException(
        'состояние модуля не сохранено: ${_describe(_lastError)}. '
        'Операция выполнена в памяти, но после перезапуска приложения '
        'изменение будет потеряно.',
      );
    }
  }

  /// Человекочитаемое описание ошибки записи.
  ///
  /// Сообщение исключения попадает в текст для пользователя, поэтому
  /// приводится к типу и тексту: имя класса вроде IsarError
  /// пользователю ничего не объясняет.
  static String _describe(Object? error) {
    if (error == null) return 'причина неизвестна';
    return '${error.runtimeType}: $error';
  }

  Future<void> _sync() async {
    for (final entry in _manager.states.entries) {
      final moduleId = entry.key;
      final state = entry.value;

      if (state == ModuleState.uninstalled) {
        // Save tombstone instead of deleting — keeps uninstall information
        // for cold start (prevents auto-reinstall of builtin modules)
        // while still clearing module data.
        final module = ModuleRegistry.get(moduleId);
        final existing = await _store.load(moduleId);
        await _store.save(ModuleStateSnapshot(
          moduleId: moduleId,
          state: state.name,
          installedVersion: module?.manifest.version ?? existing?.installedVersion ?? '',
          enabled: false,
          installedAt: existing?.installedAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await _clearModuleData(moduleId);
        continue;
      }

      final module = ModuleRegistry.get(moduleId);
      final existing = await _store.load(moduleId);

      await _store.save(ModuleStateSnapshot(
        moduleId: moduleId,
        state: state.name,
        installedVersion: module?.manifest.version ?? existing?.installedVersion ?? '',
        enabled: state == ModuleState.enabled,
        installedAt: existing?.installedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// Стирает все данные модуля через уже существующий контракт
  /// ModuleStorage (Этап 7) — keys()+remove(), без отдельного
  /// bespoke-метода "очистить всё", чтобы не тянуть в этот файл
  /// зависимость от чего-то, кроме уже установленных контрактов.
  Future<void> _clearModuleData(String moduleId) async {
    final storage = _storageFactory(moduleId);
    for (final key in await storage.keys()) {
      await storage.remove(key);
    }
  }
}
