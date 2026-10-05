/// Проверка обновления модуля (Этап 8.1-А).
///
/// Проверяется не «сработает ли», а какие именно причины отказа
/// называются: по типизированному коду UI обновления будет
/// показывать пользователю, что не так, не начиная обновления.
library module_update_validator_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_update_plan.dart';
import 'package:personal_hub/core/modules/module_update_validator.dart';
import 'package:personal_hub/core/modules/module_version.dart';

ModuleManifest _manifest({
  String id = 'notes',
  String version = '1.0.0',
  int apiVersion = 1,
  List<ModuleDependency> dependencies = const [],
}) {
  return ModuleManifest(
    id: id,
    name: 'Заметки',
    version: version,
    apiVersion: apiVersion,
    author: 'Test',
    dependencies: dependencies,
  );
}

ModuleUpdatePlan _validate({
  ModuleManifest? current,
  ModuleManifest? next,
  ModuleState? state,
  List<ModuleManifest> installed = const [],
  ModuleUpdatePolicy policy = const ModuleUpdatePolicy(),
}) {
  return ModuleUpdateValidator(policy: policy).validate(
    newManifest: next ?? _manifest(version: '1.1.0'),
    currentManifest: current ?? _manifest(),
    currentState: state ?? ModuleState.enabled,
    installedManifests: installed,
  );
}

List<ModuleUpdateViolationCode> _codes(ModuleUpdatePlan plan) =>
    plan.violations.map((v) => v.code).toList();

void main() {
  group('принимается', () {
    test('обычное обновление вперёд', () {
      final plan = _validate();

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
      expect(plan.fromVersion, const ModuleVersion(major: 1, minor: 0, patch: 0));
      expect(plan.toVersion, const ModuleVersion(major: 1, minor: 1, patch: 0));
      expect(plan.isDowngrade, isFalse);
      expect(plan.violations, isEmpty);
    });

    test('свой id среди занятых не считается конфликтом', () {
      // ManifestValidator считает занятый id конфликтом — у обновления
      // он занят по определению, им же. Без этого исключения каждое
      // обновление отказывалось бы с «id уже занят».
      final plan = _validate(installed: [_manifest()]);

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('выключенный модуль обновляется — update не включает его', () {
      final plan = _validate(state: ModuleState.disabled);

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('установленная, но ещё не включённая — тоже', () {
      final plan = _validate(state: ModuleState.installed);

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('откат разрешён политикой и помечен как откат', () {
      final plan = _validate(
        current: _manifest(version: '2.0.0'),
        next: _manifest(version: '1.9.0'),
        policy: const ModuleUpdatePolicy(allowDowngrade: true),
      );

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
      expect(plan.isDowngrade, isTrue);
    });
  });

  group('отклоняется', () {
    test('та же версия', () {
      final plan = _validate(next: _manifest(version: '1.0.0'));

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.versionNotHigher));
      expect(plan.reason, isNotNull);
    });

    test('откат запрещён по умолчанию', () {
      final plan = _validate(
        current: _manifest(version: '2.0.0'),
        next: _manifest(version: '1.9.0'),
      );

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.downgradeNotAllowed));
      expect(plan.isDowngrade, isTrue,
          reason: 'отказ не отменяет того, что версия действительно ниже');
    });

    test('числовой откат, а не лексикографический', () {
      // '0.10.0' по алфавиту МЕНЬШЕ '0.9.0' — сравнение строк решило
      // бы, что это обновление.
      final plan = _validate(
        current: _manifest(version: '0.9.0'),
        next: _manifest(version: '0.10.0'),
      );

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('неразбираемая текущая версия: обновление не доказуемо', () {
      final plan = _validate(
        current: _manifest(version: 'legacy'),
        next: _manifest(version: '99.0.0'),
      );

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.invalidCurrentVersion),
      );
    });

    test('неразбираемая новая версия', () {
      final plan = _validate(next: _manifest(version: 'latest'));

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.invalidNewVersion));
    });

    test('чужой moduleId', () {
      final plan = _validate(next: _manifest(id: 'other'));

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.moduleIdMismatch));
    });

    test('небезопасный moduleId', () {
      final plan = _validate(next: _manifest(id: '../escape', version: '1.1.0'));

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.moduleIdMismatch));
    });

    test('apiVersion вне диапазона ядра', () {
      final plan = _validate(next: _manifest(version: '1.1.0', apiVersion: 99));

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.apiVersionNotSupported),
      );
    });

    test('понижение apiVersion запрещено по умолчанию', () {
      // Модуль собран под apiVersion 2 (например, ядро обновилось),
      // а «новый» пакет прислали под 1. Ядро такое ещё понимает, но
      // понижение контракта без явного решения не допускается.
      final plan = _validate(
        current: _manifest(version: '1.0.0', apiVersion: 2),
        next: _manifest(version: '1.1.0', apiVersion: 1),
      );

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.apiVersionDowngradeNotAllowed),
      );
    });

    test('понижение apiVersion разрешённое политикой', () {
      final plan = _validate(
        current: _manifest(version: '1.0.0', apiVersion: 2),
        next: _manifest(version: '1.1.0', apiVersion: 1),
        policy: const ModuleUpdatePolicy(allowApiVersionDowngrade: true),
      );

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('удалённый модуль', () {
      final plan = _validate(state: ModuleState.uninstalled);

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.moduleNotInstalled),
      );
    });

    test('неустановленная зависимость', () {
      final plan = _validate(
        next: _manifest(
          version: '1.1.0',
          dependencies: const [
            ModuleDependency(moduleId: 'calendar', minVersion: '1.0.0'),
          ],
        ),
      );

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.dependencyNotInstalled),
      );
    });

    test('зависимость старше требуемой — minVersion проверяется', () {
      // minVersion существовал в манифесте, но не читался НИГДЕ:
      // модуль мог тихо понизить требования к зависимости.
      final plan = _validate(
        next: _manifest(
          version: '1.1.0',
          dependencies: const [
            ModuleDependency(moduleId: 'calendar', minVersion: '2.0.0'),
          ],
        ),
        installed: [_manifest(id: 'calendar', version: '1.9.0')],
      );

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.dependencyVersionTooLow),
      );
    });

    test('зависимость подходит', () {
      final plan = _validate(
        next: _manifest(
          version: '1.1.0',
          dependencies: const [
            ModuleDependency(moduleId: 'calendar', minVersion: '1.5.0'),
          ],
        ),
        installed: [_manifest(id: 'calendar', version: '1.9.0')],
      );

      expect(plan.isAccepted, isTrue, reason: plan.violationsText);
    });

    test('неразбираемый minVersion у зависимости', () {
      final plan = _validate(
        next: _manifest(
          version: '1.1.0',
          dependencies: const [
            ModuleDependency(moduleId: 'calendar', minVersion: 'latest'),
          ],
        ),
        installed: [_manifest(id: 'calendar', version: '1.9.0')],
      );

      expect(plan.isAccepted, isFalse);
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.dependencyVersionTooLow),
      );
    });

    test('цикл в графе зависимостей', () {
      final plan = _validate(
        next: _manifest(
          version: '1.1.0',
          dependencies: const [ModuleDependency(moduleId: 'calendar')],
        ),
        installed: [
          _manifest(
            id: 'calendar',
            version: '1.0.0',
            dependencies: const [ModuleDependency(moduleId: 'notes')],
          ),
        ],
      );

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.dependencyCycle));
    });

    test('несколько причин сразу — показываются все', () {
      // Четыре независимые причины в одном пакете: пользователь должен
      // увидеть их все, а не чинить по одной за попытку.
      final plan = _validate(
        next: _manifest(
          version: '0.1.0',
          apiVersion: 99,
          dependencies: const [
            ModuleDependency(moduleId: 'calendar'),
            ModuleDependency(moduleId: 'absent'),
          ],
        ),
        installed: [
          _manifest(
            id: 'calendar',
            version: '1.0.0',
            dependencies: const [ModuleDependency(moduleId: 'notes')],
          ),
        ],
      );

      expect(plan.isAccepted, isFalse);
      expect(_codes(plan), contains(ModuleUpdateViolationCode.downgradeNotAllowed));
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.apiVersionNotSupported),
      );
      expect(
        _codes(plan),
        contains(ModuleUpdateViolationCode.dependencyNotInstalled),
      );
      expect(_codes(plan), contains(ModuleUpdateViolationCode.dependencyCycle));
      expect(plan.violationsText, isNotEmpty);
    });
  });

  group('план → исключение', () {
    test('отказ разворачивается в ModuleLifecycleError с причинами', () {
      final plan = _validate(next: _manifest(version: '1.0.0'));

      final error = updateRejectionToError(plan);

      expect(error, isA<ModuleLifecycleError>());
      expect(error.moduleId, 'notes');
      expect(error.reason, contains('версия не изменилась'));
    });

    test('принятый план не разворачивается в ошибку', () {
      final plan = _validate();

      // Разворачивать нечего: нарушений нет, и исключение вводило бы
      // в заблуждение.
      expect(plan.violations, isEmpty);
      expect(updateRejectionToError(plan).reason, isNotEmpty,
          reason: 'для принятого плана причина не важна — он не отказ');
    });
  });
}