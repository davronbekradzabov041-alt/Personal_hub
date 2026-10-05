/// Проверка обновления модуля (Этап 8).
///
/// Проверка возвращает ЗНАЧЕНИЕ ([ModuleUpdatePlan]), а не бросает
/// исключение: входные данные — манифест НОВОГО пакета, то есть ввод,
/// и «пакет не подходит» это отказ, а не авария (тот же принцип, что
/// в tryInstall/ModuleInstallResult и в ModuleImporter.importFromBytes).
///
/// Базовые правила манифеста НЕ дублируются, а берутся из уже
/// существующей ManifestValidator (Этап 11): id, формат версии,
/// диапазон apiVersion. Свои проверки здесь — только те, чего у
/// установки нет по определению: сравнение версий, политика отката,
/// совместимость зависимостей. Если бы правила id/version/apiVersion
/// жили в двух местах, они разошлись бы при первой же правке одного
/// из них, и «валидный модуль» стал бы означать разное в импорте и в
/// обновлении.
library module_update_validator;

import 'external/manifest_validator.dart';
import 'module_lifecycle_error.dart';
import 'module_manifest.dart';
import 'module_state.dart';
import 'module_update_plan.dart';
import 'module_version.dart';

class ModuleUpdateValidator {
  ModuleUpdateValidator({
    this.policy = const ModuleUpdatePolicy(),
    ManifestValidator? manifestValidator,
  }) : _manifests = manifestValidator ?? ManifestValidator();

  final ModuleUpdatePolicy policy;
  final ManifestValidator _manifests;

  /// Проверяет, можно ли заменить [currentManifest] на [newManifest].
  ///
  /// [installedManifests] — манифесты модулей, доступных в приложении
  /// (то, что в ModuleRegistry). Нужны для проверки зависимостей и
  /// циклов: «зависимость не установлена» иначе была бы проверкой
  /// воздуха.
  ///
  /// Состояние модуля передаётся отдельно ([currentState]). null означает
  /// «состояние неизвестно» — например, валидатор вызывают до того, как
  /// состояние прочитано. Проверяется только явно известный
  /// [ModuleState.uninstalled]: обновлять нечего у удалённого модуля.
  ModuleUpdatePlan validate({
    required ModuleManifest newManifest,
    required ModuleManifest currentManifest,
    ModuleState? currentState,
    List<ModuleManifest> installedManifests = const <ModuleManifest>[],
  }) {
    final moduleId = newManifest.id;
    final violations = <ModuleUpdateViolation>[];

    // --- Идентичность ---
    //
    // Раньше: id нового пакета просто подставлялся в реестр. Теперь
    // подмена id отказом: иначе «обновление» установило бы другой
    // модуль, а данные прежнего остались бы в его хранилище навсегда.
    if (moduleId != currentManifest.id) {
      violations.add(ModuleUpdateViolation(
        ModuleUpdateViolationCode.moduleIdMismatch,
        'moduleId не совпадает с установленным: '
        '"$moduleId" вместо "${currentManifest.id}"',
      ));
    }

    if (currentState == ModuleState.uninstalled) {
      violations.add(const ModuleUpdateViolation(
        ModuleUpdateViolationCode.moduleNotInstalled,
        'модуль удалён, обновлять нечего',
      ));
    }

    // --- Базовые правила манифеста (переиспользуются) ---
    //
    // Свой id исключается из списка занятых: у обновляемого модуля он
    // по определению занят — им же. ManifestValidator считает такой
    // случай конфликтом, и без этого исключения КАЖДОЕ обновление
    // отказывалось бы с «id уже занят».
    final occupiedIds = <String>{
      for (final manifest in installedManifests)
        if (manifest.id != moduleId) manifest.id,
    };
    for (final error in _manifests.validate(
      newManifest,
      existingModuleIds: occupiedIds,
    )) {
      violations.add(ModuleUpdateViolation(
        _codeForManifestError(error),
        error,
      ));
    }

    // --- Сравнение версий ---
    final from = ModuleVersion.tryParse(currentManifest.version);
    final to = ModuleVersion.tryParse(newManifest.version);

    if (to != null) {
      if (from == null) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.invalidCurrentVersion,
          'установленная версия "${currentManifest.version}" не разбирается '
          'как major.minor.patch — обновление отменено, чтобы не поставить '
          'заведомо более старый пакет',
        ));
      } else if (to == from) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.versionNotHigher,
          'версия не изменилась ($from)',
        ));
      } else if (to < from && !policy.allowDowngrade) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.downgradeNotAllowed,
          'откат версии запрещён: $from → $to',
        ));
      }
    }

    final isDowngrade =
        from != null && to != null && to < from;

    // --- apiVersion ---
    //
    // Диапазон, который понимает ядро, уже проверен ManifestValidator.
    // Здесь — понижение контракта относительно установленного: модуль,
    // собранный под apiVersion 1, не должен «обновляться» пакетом,
    // собранным под более старый контракт, даже если ядро такое ещё
    // понимает.
    if (!policy.allowApiVersionDowngrade &&
        newManifest.apiVersion < currentManifest.apiVersion) {
      violations.add(ModuleUpdateViolation(
        ModuleUpdateViolationCode.apiVersionDowngradeNotAllowed,
        'понижение версии Module API запрещено: '
        '${currentManifest.apiVersion} → ${newManifest.apiVersion}',
      ));
    }

    violations.addAll(
      _dependencyViolations(newManifest, installedManifests),
    );

    if (violations.isEmpty) {
      return ModuleUpdatePlan.accepted(
        moduleId: moduleId,
        fromVersion: from!,
        toVersion: to!,
        isDowngrade: isDowngrade,
      );
    }

    return ModuleUpdatePlan.rejected(
      moduleId: moduleId,
      reason: 'обновление отклонено проверками совместимости',
      violations: List.unmodifiable(violations),
      fromVersion: from,
      toVersion: to,
      isDowngrade: isDowngrade,
    );
  }

  /// Проверки зависимостей: модуль должен быть установлен, и его
  /// версия должна быть не ниже minVersion.
  ///
  /// Отличие от проверки при установке: там требуется ВКЛЮЧЁНная
  /// зависимость, потому что модуль сейчас начинает работать и должен
  /// найти её живой. При обновлении модуль может оставаться
  /// выключенным, и требование «включена» отклонило бы обновление
  /// выключенного модуля с зависимостями — бессмысленно.
  ///
  /// minVersion до сих пор не проверялся нигде (ModuleDependency.minVersion
  /// существовал, но никем не читался). Здесь он читается: иначе
  /// обновление понизило бы требования к зависимости молча.
  List<ModuleUpdateViolation> _dependencyViolations(
    ModuleManifest manifest,
    List<ModuleManifest> installedManifests,
  ) {
    final byId = <String, ModuleManifest>{
      for (final installed in installedManifests) installed.id: installed,
    };
    final violations = <ModuleUpdateViolation>[];

    for (final dependency in manifest.dependencies) {
      final installed = byId[dependency.moduleId];
      if (installed == null) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.dependencyNotInstalled,
          'зависимость "${dependency.moduleId}" не установлена',
        ));
        continue;
      }

      final minVersion = dependency.minVersion;
      if (minVersion == null) continue;

      final required = ModuleVersion.tryParse(minVersion);
      if (required == null) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.dependencyVersionTooLow,
          'недопустимый minVersion "$minVersion" у зависимости '
          '"${dependency.moduleId}"',
        ));
        continue;
      }

      final actual = ModuleVersion.tryParse(installed.version);
      if (actual == null) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.dependencyVersionTooLow,
          'версия зависимости "${dependency.moduleId}" ("${installed.version}") '
          'не разбирается как major.minor.patch, требуется >= $required',
        ));
        continue;
      }

      if (actual < required) {
        violations.add(ModuleUpdateViolation(
          ModuleUpdateViolationCode.dependencyVersionTooLow,
          'зависимость "${dependency.moduleId}" версии $actual старше '
          'требуемых $required',
        ));
      }
    }

    violations.addAll(_cycleViolations(manifest, installedManifests));
    return violations;
  }

  /// Цикл в графе зависимостей с новыми требованиями обновляемого
  /// модуля. Сам граф строится из установленных модулей, а запись
  /// обновляемого модуля ЗАМЕНЯЕТСЯ новой — иначе цикл, возникший
  /// именно из-за обновления, не был бы виден.
  List<ModuleUpdateViolation> _cycleViolations(
    ModuleManifest manifest,
    List<ModuleManifest> installedManifests,
  ) {
    if (manifest.dependencies.isEmpty &&
        !installedManifests.any((m) => m.dependencies.isNotEmpty)) {
      return const [];
    }

    final graph = <String, List<String>>{
      for (final installed in installedManifests)
        installed.id: installed.dependencies.map((d) => d.moduleId).toList(),
    };
    graph[manifest.id] =
        manifest.dependencies.map((d) => d.moduleId).toList();

    return _manifests
        .findDependencyCycles(graph)
        .map((cycle) => ModuleUpdateViolation(
              ModuleUpdateViolationCode.dependencyCycle,
              'циклические зависимости: $cycle',
            ))
        .toList();
  }

  /// Переводит текст нарушения ManifestValidator в код.
  ///
  /// Сопоставление по тексту — не красота, а компромисс: правила
  /// ManifestValidator не типизированы, а дублировать их здесь
  /// нельзя. Неопознанный текст НЕ игнорируется, а попадает в
  /// [ModuleUpdateViolationCode.manifestInvalid] — новое правило
  /// внешнего валидатора не сможет молча исчезнуть из отчёта.
  static ModuleUpdateViolationCode _codeForManifestError(String error) {
    if (error == 'id пустой') {
      return ModuleUpdateViolationCode.moduleIdMismatch;
    }
    if (error.startsWith('недопустимый moduleId')) {
      return ModuleUpdateViolationCode.moduleIdMismatch;
    }
    if (error.startsWith('неверный формат версии')) {
      return ModuleUpdateViolationCode.invalidNewVersion;
    }
    if (error.startsWith('неподдерживаемая версия Module API')) {
      return ModuleUpdateViolationCode.apiVersionNotSupported;
    }
    if (error.startsWith('id "') && error.contains('уже занят')) {
      return ModuleUpdateViolationCode.moduleIdMismatch;
    }
    return ModuleUpdateViolationCode.manifestInvalid;
  }
}

/// Разворачивает отказ плана в исключение жизненного цикла.
///
/// Существует ради `ModuleManager.update()`, который по контракту
/// бросает ModuleLifecycleError: менять его сигнатуру на типизированный
/// результат запрещено без необходимости — от него зависят вызывающие
/// Этапов 10/12. Новый код может читать [ModuleUpdateValidator]
/// напрямую.
ModuleLifecycleError updateRejectionToError(ModuleUpdatePlan plan) {
  final details = plan.violationsText;
  return ModuleLifecycleError(
    plan.moduleId,
    details.isEmpty
        ? (plan.reason ?? 'обновление отклонено')
        : '${plan.reason ?? "обновление отклонено"}: $details',
  );
}