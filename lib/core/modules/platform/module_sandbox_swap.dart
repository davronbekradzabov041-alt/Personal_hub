/// Подготовка безопасного обмена песочницы внешнего модуля
/// (Этап 8.1-А, механизм; подключение к импорту — Этап 8.1-Б).
///
/// Почему не `delete old → rename new`, как было в
/// ModuleImporter._commitSandbox: между удалением и переносом
/// модуля нет вообще ничего — прерывание процесса в эту секунду
/// оставляет модуль без песочницы навсегда, а восстановить его можно
/// только переустановкой. Здесь последовательность обратная: старый
/// каталог ПЕРЕНОСИТСЯ в сторону (rename атомарен в пределах тома), и
/// только потом на его место приходит новый. Значит, в любой момент
/// либо жив старый модуль, либо живой новый, либо оба рядом в
/// восстанавливаемом виде.
///
/// Раскладка каталогов deliberately разделена, а не сделана внутри
/// `modules/`:
///   <support>/modules/<id>            — живой модуль
///   <support>/modules_staging/<id>_*  — подготовленная новая версия
///   <support>/modules_previous/<id>_* — предыдущая версия, до уборки
///
/// Каталог-бэкап лежит РЯДОМ с `modules/`, а не внутри него, потому
/// что ModuleSandbox.listModuleIds() перечисляет содержимое
/// `modules/` и выдал бы `notes.update_backup_123` за ещё один
/// установленный модуль.
library module_sandbox_swap;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'module_sandbox.dart';
import 'sandbox_exceptions.dart';

/// Каталог подготовленных версий рядом с `modules/`.
const String kModuleStagingDirName = 'modules_staging';

/// Каталог предыдущих версий рядом с `modules/`.
const String kModulePreviousDirName = 'modules_previous';

/// Итог обмена песочницей.
class ModuleSandboxSwapResult {
  final String moduleId;

  /// Каталог, который теперь живёт на месте модуля.
  final Directory permanentDirectory;

  /// Каталог предыдущей версии, если она была. Не удаляется
  /// автоматически: старый модуль обязан остаться восстанавливаемым
  /// до тех пор, пока обновление не завершилось успешно.
  final Directory? previousDirectory;

  /// Модуля раньше не было — это первая установка, а не обновление.
  final bool isFirstInstall;

  const ModuleSandboxSwapResult({
    required this.moduleId,
    required this.permanentDirectory,
    required this.previousDirectory,
    required this.isFirstInstall,
  });
}

class ModuleSandboxSwap {
  ModuleSandboxSwap({Future<Directory> Function()? supportDirectoryResolver})
      : _supportDirectoryResolver = supportDirectoryResolver;

  /// Куда смотреть за корнем песочниц. По умолчанию — боевое
  /// расположение; совпадает с тем, что использует ModuleImporter и
  /// ModuleSandbox.
  final Future<Directory> Function()? _supportDirectoryResolver;

  /// Создаёт ПУСТОЙ каталог для подготовки новой версии.
  ///
  /// Содержимое сюда распаковывает вызывающий (Этап 8.1-Б). Имя
  /// содержит микросекунды эпохи, поэтому два параллельных вызова не
  /// столкнутся, а порядок имён совпадает с порядком создания.
  Future<Directory> createStaging({required String moduleId}) async {
    ModuleSandbox.validateModuleId(moduleId);
    final root = await _stagingRoot();
    final dir = Directory(path.join(
      root.path,
      '${moduleId}_${DateTime.now().microsecondsSinceEpoch}',
    ));
    await dir.create(recursive: true);
    return dir;
  }

  /// Живой каталог модуля (может не существовать).
  Future<Directory> permanentDirectory(String moduleId) async {
    ModuleSandbox.validateModuleId(moduleId);
    final root = await _modulesRoot();
    return Directory(path.join(root.path, moduleId));
  }

  /// Каталог предыдущей версии, если обмен уже выполнялся.
  ///
  /// Из нескольких выбирается самый свежий по имени: суффикс —
  /// микросекунды эпохи, одинаковой длины, поэтому порядок имён
  /// совпадает с порядком создания.
  ///
  /// Владелец каталога определяется РАЗБОРОМ имени ([_moduleIdOf]), а не
  /// сравнением с префиксом '${moduleId}_': префикс не различает
  /// `notes` и `notes_lite`, и поиск прежней версии `notes` нашёл бы
  /// каталог чужого модуля.
  Future<Directory?> findPreviousDirectory(String moduleId) async {
    ModuleSandbox.validateModuleId(moduleId);
    final root = await _previousRoot();
    if (!await root.exists()) return null;

    final candidates = <String>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      if (_moduleIdOf(entity.path) == moduleId) candidates.add(entity.path);
    }
    if (candidates.isEmpty) return null;
    candidates.sort();
    return Directory(candidates.last);
  }

  /// Ставит подготовленную версию на место модуля.
  ///
  /// Порядок (каждый шаг — отдельная атомарная операция ФС):
  /// 1. `modules/<id>` → `modules_previous/<id>_<ts>`;
  /// 2. `<staging>` → `modules/<id>`;
  /// 3. при сбое шага 2 старый каталог возвращается на место.
  ///
  /// Ничего не удаляется: результат возвращает путь к каталогу
  /// предыдущей версии, который убирает вызывающий (discardPrevious)
  /// только после успешного завершения обновления.
  Future<ModuleSandboxSwapResult> commit({
    required String moduleId,
    required Directory stagedDirectory,
  }) async {
    ModuleSandbox.validateModuleId(moduleId);

    if (!await stagedDirectory.exists()) {
      throw SandboxStagingMissingException(
        moduleId: moduleId,
        path: stagedDirectory.path,
      );
    }

    final permanent = await permanentDirectory(moduleId);
    await permanent.parent.create(recursive: true);

    final hadPermanent = await permanent.exists();
    Directory? previous;
    if (hadPermanent) {
      final previousRoot = await _previousRoot();
      await previousRoot.create(recursive: true);
      previous = await _uniqueDirectory(
        parent: previousRoot,
        name: '${moduleId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      // Атомарно: после этого шага модуля нет ровно на микросекунды,
      // и даже при сбое здесь он лежит целым в previousDirectory.
      await permanent.rename(previous.path);
    }

    try {
      await stagedDirectory.rename(permanent.path);
    } catch (error) {
      // Старый модуль возвращается на место. Если и это не удалось —
      // сообщение обязано содержать путь к каталогу-бэкапу: иначе
      // после сбоя невозможно понять, где искать выжившую версию.
      if (previous != null) {
        try {
          await previous.rename(permanent.path);
        } catch (rollbackError) {
          throw SandboxSwapException(
            moduleId: moduleId,
            message: 'обмен песочницы не удался ($error), откат тоже '
                'не удался ($rollbackError). Прежняя версия сохранена в '
                '"${previous.path}"',
            backupPath: previous.path,
          );
        }
      }
      throw SandboxSwapException(
        moduleId: moduleId,
        message: 'обмен песочницы не удался: $error'
            '${previous == null ? '' : '. Прежняя версия возвращена на место'}',
      );
    }

    return ModuleSandboxSwapResult(
      moduleId: moduleId,
      permanentDirectory: permanent,
      previousDirectory: previous,
      isFirstInstall: !hadPermanent,
    );
  }

  /// Возвращает предыдущую версию на место модуля.
  ///
  /// [discardCurrent] (по умолчанию true) уводит текущую песочницу в
  /// staging, а не удаляет: только что установленная версия может
  /// оказаться причиной отката, и уничтожать её до выяснения —
  /// последнее, чего хочется от механизма отката.
  ///
  /// false — вернёт false: восстанавливать нечего.
  Future<bool> restorePrevious({
    required String moduleId,
    Directory? previousDirectory,
    bool discardCurrent = true,
  }) async {
    ModuleSandbox.validateModuleId(moduleId);

    final backup = previousDirectory ?? await findPreviousDirectory(moduleId);
    if (backup == null || !await backup.exists()) return false;

    final permanent = await permanentDirectory(moduleId);
    if (await permanent.exists()) {
      if (!discardCurrent) return false;
      final stagingRoot = await _stagingRoot();
      await stagingRoot.create(recursive: true);
      final discarded = await _uniqueDirectory(
        parent: stagingRoot,
        name: '${moduleId}_${_discardedMarker}_'
            '${DateTime.now().microsecondsSinceEpoch}',
      );
      await permanent.rename(discarded.path);
    }

    await backup.rename(permanent.path);
    return true;
  }

  /// Убирает каталог предыдущей версии после успешного обновления.
  Future<void> discardPrevious({
    required String moduleId,
    required Directory previousDirectory,
  }) async {
    ModuleSandbox.validateModuleId(moduleId);
    if (await previousDirectory.exists()) {
      await previousDirectory.delete(recursive: true);
    }
  }

  /// Убирает каталог подготовки (staging), который больше не нужен.
  Future<void> discardStaging(Directory stagedDirectory) async {
    if (await stagedDirectory.exists()) {
      await stagedDirectory.delete(recursive: true);
    }
  }

  /// Убирает ВСЕ каталоги подготовки и отката, принадлежащие модулю.
  ///
  /// [restorePrevious] по требованию Этапа 8.1-А уводит неудачную версию
  /// в сторону, а не удаляет: сбой надо уметь разбирать. Но это
  /// относится к самому механизму обмена. Вызывающий, который уже
  /// решил, что обновление провалилось и откат состоялся (ModuleImporter),
  /// обязан прибрать за собой, иначе каждая неудачная попытка оставляла
  /// бы на диске очередной мусорный каталог.
  ///
  /// Принадлежность определяется разбором имени ([_moduleIdOf]), а не
  /// сравнением с префиксом: префикс `${moduleId}_` не отличает `notes`
  /// от `notes_lite`, и уборка одного модуля снесла бы подготовку
  /// другого.
  Future<void> discardStagedVersions({required String moduleId}) async {
    ModuleSandbox.validateModuleId(moduleId);

    final root = await _stagingRoot();
    if (!await root.exists()) return;

    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      if (_moduleIdOf(entity.path) == moduleId) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// Восстановление после сбоя ПРОЦЕССА (а не обработчика ошибок).
  ///
  /// Между шагами commit процесс может быть убит. Тогда на диске
  /// лежат каталог-бэкап и, возможно, новый модуль. Вызывать это надо
  /// при старте приложения ДО любых операций с песочницами:
  ///
  /// * модуля нет, бэкап есть — вернуть бэкап на место (обновление не
  ///   завершилось, старая версия обязана продолжить работу);
  /// * модуль есть — ничего не трогать: новая версия уже встала, а
  ///   бэкап уберёт вызывающий после успеха.
  Future<bool> recoverInterrupted({required String moduleId}) async {
    ModuleSandbox.validateModuleId(moduleId);

    final permanent = await permanentDirectory(moduleId);
    if (await permanent.exists()) return false;

    final previous = await findPreviousDirectory(moduleId);
    if (previous == null) return false;

    await permanent.parent.create(recursive: true);
    await previous.rename(permanent.path);
    return true;
  }

  /// Восстановление после сбоя ПРОЦЕССА для ВСЕХ модулей разом.
  ///
  /// Вызывается при старте приложения (см. composition root в main.dart),
  /// потому что перечислить модули для проверки иначе нечем: реестр в
  /// этот момент пуст — его наполняет регистрация встроенных модулей,
  /// а пострадавший от сбоя модуль может быть внешним и в реестре ещё
  /// не появиться. Перебирать каталоги `modules/` нельзя по той же
  /// причине: именно он после сбоя может быть неполным.
  ///
  /// Перебор идёт по `modules_previous/`: там лежат каталоги, чей
  /// обмен не был доведён до конца, и их владельцы — ровно те модули,
  /// которые надо проверить.
  ///
  /// Что делать с каталогом прежней версии, определяет наличие песочницы
  /// модуля, и это не «мелочь уборки», а часть восстановления:
  ///
  /// * песочницы НЕТ — обмен оборвался между двумя переносами, прежняя
  ///   версия возвращается на место;
  /// * песочница ЕСТЬ — новый модуль уже встал, а уборка прежней версии
  ///   не произошла, и каталог прежней версии больше не нужен.
  ///
  /// Второй случай важен не только для порядка на диске. Пока лишний
  /// каталог лежит, «каталог прежней версии существует» перестаёт
  /// означать «обмен этого модуля не доведён до конца»: откат
  /// обновления (ModuleImporter) опирается на это, чтобы понять, надо ли
  /// возвращать прежнюю версию. Нормализация раскладки при старте
  /// делает такое толкование однозначным.
  Future<({List<String> recovered, List<String> discarded})>
      recoverAllInterrupted() async {
    final root = await _previousRoot();
    if (!await root.exists()) {
      return (recovered: const <String>[], discarded: const <String>[]);
    }

    final recovered = <String>[];
    final discarded = <String>[];

    // Один и тот же модуль может встречаться в каталоге дважды (два
    // прерванных обновления подряд), поэтому решения принимаются по
    // модулю, а не по каталогу.
    final seen = <String, bool>{};
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final moduleId = _moduleIdOf(entity.path);
      // Мусор в каталоге бэкапов (или нечто, чьё имя не разбирается как
      // "<id>_<метка>") не должно ронять запуск приложения: здесь
      // нечего восстанавливать, и единственная цена пропуска — остатки
      // на диске, разбирать которые можно и позже.
      if (moduleId == null || seen.containsKey(moduleId)) continue;

      seen[moduleId] = true;
      if (await recoverInterrupted(moduleId: moduleId)) {
        recovered.add(moduleId);
        continue;
      }

      if (await findPreviousDirectory(moduleId) == null) continue;
      final permanent = await permanentDirectory(moduleId);
      if (!await permanent.exists()) continue;
      await discardPrevious(
        moduleId: moduleId,
        previousDirectory: (await findPreviousDirectory(moduleId))!,
      );
      discarded.add(moduleId);
    }

    return (recovered: recovered, discarded: discarded);
  }

  // --- Внутреннее ---

  /// Метка версии, которую restorePrevious увёл в сторону.
  ///
  /// Отдельная константа, а не литерал в имени: её обязаны понимать и
  /// создатель имени ([restorePrevious]), и разбор имени
  /// ([_moduleIdOf]) — иначе каталог «notes_discarded_…» был бы
  /// приписан модулю с именем `notes_discarded`.
  static const String _discardedMarker = 'discarded';

  /// Владелец каталога `modules_previous/<id>_<метка>` или
  /// `modules_staging/<id>[_discarded]_<метка>`. null — если имя не
  /// наше и разбирать его как наше нельзя.
  ///
  /// Метка времени — микросекунды эпохи, то есть цифры. Ищется ПЕРВОЕ
  /// подчёркивание, за которым идут только цифры до конца имени: это
  /// однозначно отделяет moduleId от метки, даже когда сам moduleId
  /// содержит подчёркивания (`my_notes_1699…` → `my_notes`, не `my`).
  ///
  /// Разбор по префиксу здесь не годился дважды: `notes_lite_…` начинается
  /// с `notes_`, а мусор в каталоге бэкапов выдавал бы себя за модуль с
  /// именем из своей первой части.
  static String? _moduleIdOf(String directoryPath) {
    final name = path.basename(directoryPath);

    for (var i = 0; i < name.length; i++) {
      if (name.codeUnitAt(i) != 0x5F) continue; // '_'
      final suffix = name.substring(i + 1);
      if (suffix.isEmpty) continue;
      if (!suffix.runes.every((r) => r >= 0x30 && r <= 0x39)) continue;

      var moduleId = name.substring(0, i);
      if (moduleId.endsWith('$_discardedMarker')) {
        moduleId =
            moduleId.substring(0, moduleId.length - _discardedMarker.length - 1);
      }

      try {
        ModuleSandbox.validateModuleId(moduleId);
      } on InvalidModuleIdException {
        return null;
      }
      return moduleId;
    }
    return null;
  }

  Future<Directory> _modulesRoot() async {
    final support = await _supportDirectory();
    return Directory(path.join(support.path, 'modules'));
  }

  Future<Directory> _stagingRoot() async {
    final support = await _supportDirectory();
    return Directory(path.join(support.path, kModuleStagingDirName));
  }

  Future<Directory> _previousRoot() async {
    final support = await _supportDirectory();
    return Directory(path.join(support.path, kModulePreviousDirName));
  }

  Future<Directory> _supportDirectory() async {
    final resolver = _supportDirectoryResolver;
    if (resolver != null) return resolver();
    final appDocDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDocDir.path, 'personal_hub_modules'));
  }

  /// Имя, которого ещё не заняли: микросекунды могут совпасть при двух
  /// вызовах в одном тике на некоторых платформах.
  Future<Directory> _uniqueDirectory({
    required Directory parent,
    required String name,
  }) async {
    var candidate = Directory(path.join(parent.path, name));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = Directory(path.join(parent.path, '$name.$suffix'));
      suffix++;
    }
    return candidate;
  }
}