/// Обновление внешнего модуля из .phm (Этап 8.1-Б).
///
/// Проверяется то, ради чего обновление и выделено в отдельный путь:
/// реализация и ассеты меняются, а ДАННЫЕ ПОЛЬЗОВАТЕЛЯ и состояние
/// модуля — нет; отказ проверок не трогает ничего; сбой на любом шаге
/// после снимка возвращает всё как было.
library module_importer_update_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/module_importer.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox_swap.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/modules/platform/sandbox_exceptions.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

const String _moduleId = 'notes';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late _FailingUpdateManager manager;
  late Map<String, _FakeStorage> storages;
  late _FakeStateStore stateStore;

  ModuleImporter importer({ModuleSandboxSwap? sandboxSwap}) => ModuleImporter(
        moduleManager: manager,
        testSupportDir: support,
        stateStore: stateStore,
        sandboxSwap: sandboxSwap ??
            ModuleSandboxSwap(supportDirectoryResolver: () async => support),
      );

  Directory sandboxDir() =>
      Directory(path.join(support.path, 'modules', _moduleId));

  File assetFile(String name) =>
      File(path.join(sandboxDir().path, 'assets', name));

  List<String> assetNames() {
    final assets = Directory(path.join(sandboxDir().path, 'assets'));
    if (!assets.existsSync()) return const [];
    return assets
        .listSync()
        .whereType<File>()
        .map((f) => path.basename(f.path))
        .toList()
      ..sort();
  }

  /// Каталоги, оставшиеся рядом с `modules/`: подготовка и прежние
  /// версии. После успешного обновления их быть не должно.
  ({int staging, int previous}) sandboxResidue() {
    int count(String name) {
      final dir = Directory(path.join(support.path, name));
      if (!dir.existsSync()) return 0;
      return dir.listSync().length;
    }

    return (
      staging: count(kModuleStagingDirName),
      previous: count(kModulePreviousDirName),
    );
  }

  /// Устанавливает внешний модуль 1.0.0 и кладёт в его хранилище
  /// пользовательские данные, которых нет ни в одном пакете.
  Future<void> installBaseline({bool enable = false}) async {
    final result = await importer().importFromBytes(
      _phm(
        version: '1.0.0',
        assets: {'logo.png': 'старая иконка'},
        storage: {'seed': 'из пакета 1.0.0'},
      ),
    );
    expect(result.isSuccess, isTrue, reason: result.error);

    if (enable) {
      await manager.enable(_moduleId);
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
    }

    final storage = storages[_moduleId]!;
    await storage.setString('note:1', 'черновик пользователя');
    await storage.setString('schema:version', '3');
  }

  setUp(() {
    ModuleRegistry.clear();
    storages = <String, _FakeStorage>{};
    manager = _FailingUpdateManager(
      searchService: GlobalSearchService(),
      storageFactory: (moduleId) =>
          storages[moduleId] ??= _FakeStorage(),
    );
    stateStore = _FakeStateStore();
    support = Directory.systemTemp.createTempSync('phm_update_');
  });

  tearDown(() {
    ModuleRegistry.clear();
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  group('успешное обновление', () {
    test('реализация и ассеты меняются, данные и состояние — нет', () async {
      await installBaseline(enable: true);
      final storageBefore = storages[_moduleId]!;

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка', 'data.json': '{"схема":2}'},
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      expect(result.isUpdate, isTrue);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
      expect(ModuleRegistry.get(_moduleId), isA<ExternalModuleAdapter>());

      // Данные пользователя целы — включая ключ, которого в новом пакете
      // нет, и значения, которых в пакете не было вообще.
      expect(await storageBefore.getString('note:1'), 'черновик пользователя');
      expect(await storageBefore.getString('schema:version'), '3');
      expect(await storageBefore.getString('seed'), 'из пакета 1.0.0',
          reason: 'обновление не должно вытирать данные, засеянные установкой');

      // Состояние не изменилось: обновление не включает и не выключает.
      expect(manager.stateOf(_moduleId), ModuleState.enabled);

      // Ассеты новой версии на месте, ассетов прежней версии нет:
      // обмен песочницы заменяет каталог целиком.
      expect(assetNames(), ['data.json', 'logo.png']);
      expect(assetFile('logo.png').readAsStringSync(), 'новая иконка');

      // Ни подготовки, ни прежней версии не осталось.
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('выключенный модуль обновляется и остаётся выключенным', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '2.0.0'),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      expect(manager.stateOf(_moduleId), ModuleState.installed);
    });

    test('ModuleApi и хранилище те же: uninstall + install не происходит', () async {
      await installBaseline(enable: true);
      final storageBefore = manager.apiFor(_moduleId).storage;

      await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(identical(manager.apiFor(_moduleId).storage, storageBefore),
          isTrue,
          reason: 'через uninstall+install кэш ModuleApi был бы сброшен');
      expect(await storageBefore.getString('note:1'), 'черновик пользователя');
    });

    test('хранилище новой версии НЕ переносится поверх данных', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          storage: {
            'note:1': 'текст из нового пакета',
            'new:key': 'ключ новой версии',
          },
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      final storage = storages[_moduleId]!;
      // data/storage.json новой версии — данные для ЧИСТОЙ установки;
      // перенос поверх пользовательских затирал бы их.
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(await storage.getString('new:key'), isNull);
    });
  });

  group('отказы проверок ничего не меняют', () {
    test('откат версии запрещён и назван кодом', () async {
      await installBaseline(enable: true);

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '0.9.0'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('downgradeNotAllowed'));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('та же версия — отказ', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.0.0'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('versionNotHigher'));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    });

    test('неустановленный модуль обновить нельзя', () async {
      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('module_not_installed'));
      expect(
        Directory(path.join(support.path, 'modules')).existsSync(),
        isFalse,
        reason: 'проверки обязаны отбить пакет до файловых операций',
      );
    });

    test('встроенный модуль нельзя обновить из внешнего пакета', () async {
      ModuleRegistry.register(_FakeBuiltin());
      await manager.tryInstall('example');

      final result = await importer().updateFromBytes(
        moduleId: 'example',
        archiveBytes: _phm(version: '9.9.9'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('builtin_module_id'));
      expect(ModuleRegistry.get('example'), isA<_FakeBuiltin>());
    });

    test('пакет с чужим moduleId отклоняется', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(id: 'other', version: '1.1.0'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('module_id_mismatch'));
      expect(ModuleRegistry.contains('other'), isFalse,
          reason: 'иначе «обновление notes» установило бы другой модуль');
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
    });

    test('зависимость новой версии не установлена — обновление отказ', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          dependencies: ['missing-dep:1.0.0'],
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('dependencyNotInstalled'));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    });
  });

  group('сбой на шаге после снимка откатывается целиком', () {
    test('сбой сразу после обмена песочницы возвращает всё', () async {
      await installBaseline(enable: true);
      final storage = storages[_moduleId]!;
      final originalModule = ModuleRegistry.get(_moduleId);

      final result = await importer(
        sandboxSwap: _CommitThenFailSwap(
          supportDirectoryResolver: () async => support,
        ),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, isNot(contains('rollback_failed')),
          reason: 'откат обязан удаться: ${result.error}');

      // Реестр: прежний объект модуля, а не новая реализация.
      expect(ModuleRegistry.get(_moduleId), same(originalModule));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');

      // Песочница: прежние ассеты на месте, ассетов новой версии нет.
      expect(assetNames(), ['logo.png']);
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');

      // Данные и состояние — как до обновления.
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);

      // Ни подготовки, ни прежней версии не осталось: прежняя версия
      // вернулась на место, подготовка убрана.
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('сбой ДО обмена песочницы не трогает ничего', () async {
      await installBaseline(enable: true);
      final originalModule = ModuleRegistry.get(_moduleId);

      final result = await importer(
        sandboxSwap: _FailBeforeCommitSwap(
          supportDirectoryResolver: () async => support,
        ),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId), same(originalModule));
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(sandboxResidue(), (staging: 0, previous: 0),
          reason: 'подготовка не должна оставаться после отката');
    });

    test('сбой после обмена песочницы не стирает данные пользователя', () async {
      // Отдельная проверка от «состояния»: снимок обязан вернуть
      // хранилище, потому что к этому моменту новый модуль уже мог
      // что-то записать (например, свои lifecycle-хуки).
      await installBaseline();
      final storage = storages[_moduleId]!;
      final swap = _CommitThenFailSwap(
        supportDirectoryResolver: () async => support,
        onCommit: () async {
          // Имитация того, что запись уже успела произойти.
          await storage.setString('note:1', 'испорчено');
          await storage.setString('note:2', 'лишний ключ');
        },
      );

      final result = await importer(sandboxSwap: swap).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(result.isFailure, isTrue);
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(await storage.getString('note:2'), isNull,
          reason: 'ключ, которого не было до обновления, обязан исчезнуть');
    });
  });

  group('сбой на каждой критической фазе', () {
    test('сбой снятия снимка останавливает обновление до первой записи',
        () async {
      await installBaseline();
      final originalModule = ModuleRegistry.get(_moduleId);
      // Снимок читает хранилище и assets. Если он не снят, откатывать
      // нечего, и обновление обязано остановиться ДО обмена песочницей:
      // иначе «откат» был бы фикцией.
      storages[_moduleId]!.failOnKeys = true;

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId), same(originalModule));
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('сбой подготовки не трогает ничего', () async {
      await installBaseline(enable: true);
      final originalModule = ModuleRegistry.get(_moduleId);

      final result = await importer(
        sandboxSwap: _FailStagingSwap(
          supportDirectoryResolver: () async => support,
        ),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId), same(originalModule));
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('сбой обмена реестра возвращает песочницу прежней версии',
        () async {
      await installBaseline(enable: true);
      final originalModule = ModuleRegistry.get(_moduleId);
      // Песочница к этому моменту уже новая, а реестр — старый. Откат
      // обязан вернуть и то, и другое: иначе модуль заявил бы прежнюю
      // версию с файлами новой.
      manager.failOnUpdate = true;

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId), same(originalModule),
          reason: 'реестр обязан вернуть прежний объект модуля');
      expect(assetNames(), ['logo.png']);
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка',
          reason: 'файлы новой версии не должны остаться на месте');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });
  });

  group('прерванный обмен песочницы восстанавливается при старте', () {
    test('после сбоя процесса модуль возвращается, обновление повторяется',
        () async {
      await installBaseline();

      // Процесс убит ПОСЛЕ первого переноса и ДО отката: песочницы
      // модуля нет, прежняя версия лежит рядом. Откат не выполнился и
      // уже не выполнится — это состояние восстанавливает запуск
      // приложения, а не операция.
      final result = await importer(
        sandboxSwap: _CrashingSwap(
          supportDirectoryResolver: () async => support,
        ),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );

      expect(result.isFailure, isTrue);
      expect(sandboxDir().existsSync(), isFalse,
          reason: 'именно это состояние и восстанавливается при старте');

      // Восстановление при старте приложения.
      final report = await ModuleSandboxSwap(
        supportDirectoryResolver: () async => support,
      ).recoverAllInterrupted();
      expect(report.recovered, [_moduleId]);
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');

      // Повтор того же обновления после восстановления проходит.
      final retry = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'новая иконка'},
        ),
      );
      expect(retry.isSuccess, isTrue, reason: retry.error);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
      expect(assetFile('logo.png').readAsStringSync(), 'новая иконка');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });
  });

  group('повторное и повторяющееся обновление', () {
    test('модуль обновляется несколько раз подряд', () async {
      await installBaseline(enable: true);

      for (final version in ['1.1.0', '1.2.0', '2.0.0']) {
        final result = await importer().updateFromBytes(
          moduleId: _moduleId,
          archiveBytes: _phm(version: version, assets: {'logo.png': version}),
        );
        expect(result.isSuccess, isTrue, reason: '$version: ${result.error}');
        expect(ModuleRegistry.get(_moduleId)!.manifest.version, version);
      }

      expect(assetFile('logo.png').readAsStringSync(), '2.0.0');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(sandboxResidue(), (staging: 0, previous: 0),
          reason: 'каждое обновление обязано убирать прежнюю версию');
    });

    test('тот же пакет второй раз — отказ, модуль не трогается', () async {
      await installBaseline();
      final first = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0', assets: {'logo.png': '1.1.0'}),
      );
      expect(first.isSuccess, isTrue, reason: first.error);

      final second = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0', assets: {'logo.png': '1.1.0'}),
      );

      expect(second.isFailure, isTrue);
      expect(second.violations, contains('versionNotHigher'));
      expect(assetFile('logo.png').readAsStringSync(), '1.1.0');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
    });
  });

  group('совместимость новой версии', () {
    test('apiVersion новее поддерживаемого отклоняется', () async {
      await installBaseline();

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0', apiVersion: 99),
      );

      // Отказ приходит от ОБЩЕЙ проверки манифеста (ManifestValidator
      // через PackageReader), а не от проверок обновления: модуль под
      // неподдерживаемым API не проходит валидацию сам по себе, и до
      // сравнения версий дело не доходит. Проверки обновления для
      // apiVersion живут в ModuleUpdateValidator и покрыты там отдельно.
      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
      expect(await storages[_moduleId]!.getString('note:1'),
          'черновик пользователя');
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });

    test('зависимость старше требуемой отклоняется', () async {
      await installBaseline();
      // Зависимость стоит в реестре версией 1.0.0, а новая версия
      // модуля требует от неё 2.0.0: подставить свою реализацию вместо
      // чужой нельзя.
      ModuleRegistry.register(
        ExternalModuleAdapter(_manifestOf('dep', version: '1.0.0')),
      );

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          dependencies: ['dep:2.0.0'],
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('dependencyVersionTooLow'));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    });

    test('зависимость подходящей версии пропускает обновление', () async {
      await installBaseline();
      ModuleRegistry.register(
        ExternalModuleAdapter(_manifestOf('dep', version: '1.2.0')),
      );

      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          dependencies: ['dep:1.0.0'],
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
    });
  });

  group('согласованность двух путей обновления', () {
    test('откат версии отклоняется одинаково', () async {
      await installBaseline(enable: true);

      // Путь менеджера (раздел «Обновления» каталога).
      await expectLater(
        manager.update(ExternalModuleAdapter(_manifestOf(_moduleId, version: '0.9.0'))),
        throwsA(isA<ModuleLifecycleError>()),
        reason: 'обмен манифеста в реестре обязан подчиняться тем же правилам',
      );

      // Путь пакета (файл .phm) — с тем же кодом нарушения.
      final result = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '0.9.0'),
      );

      expect(result.isFailure, isTrue);
      expect(result.violations, contains('downgradeNotAllowed'));
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(assetFile('logo.png').readAsStringSync(), 'старая иконка');
    });

    test('успех обновления одинаков: версия, данные и состояние', () async {
      await installBaseline(enable: true);
      final storage = storages[_moduleId]!;

      // Путь пакета: версия 1.1.0 вместе с файлами новой версии.
      final viaPackage = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': '1.1.0'},
        ),
      );
      expect(viaPackage.isSuccess, isTrue, reason: viaPackage.error);

      // Путь менеджера: следующая версия, файлов у неё нет — обмен
      // реестра меняет только манифест.
      await manager.update(ExternalModuleAdapter(_manifestOf(_moduleId, version: '1.2.0')));

      // Итог у обоих путей одинаков по смыслу: версия новая, данные
      // пользователя целы, состояние прежнее. Различается только то,
      // принесли ли с собой файлы.
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.2.0');
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(await storage.getString('schema:version'), '3');
      expect(manager.stateOf(_moduleId), ModuleState.enabled);
      expect(assetFile('logo.png').readAsStringSync(), '1.1.0',
          reason: 'обмен реестра не трогает песочницу — это работа пакета');
      expect(sandboxResidue(), (staging: 0, previous: 0));
    });
  });

  group('границы обновления', () {
    test('обновление не трогает песочницы других модулей', () async {
      await installBaseline();
      final other = Directory(path.join(support.path, 'modules', 'other'));
      await other.create(recursive: true);
      File(path.join(other.path, 'keep.txt')).writeAsStringSync('чужое');

      await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '1.1.0'),
      );

      expect(File(path.join(other.path, 'keep.txt')).readAsStringSync(),
          'чужое');
    });

    test('импорт установленного moduleId по-прежнему отказ', () async {
      // Импорт и обновление — разные операции с разными правами:
      // «импортировать» не должно молча превращаться в обновление.
      await installBaseline();

      final result = await importer().importFromBytes(
        _phm(version: '3.0.0'),
      );

      expect(result.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
    });
  });
}

// =========================================================================
// Пакеты и подмены
// =========================================================================

/// Собирает .phm тем же писателем, что иModuleExporter: тест не должен
/// зависеть от того, как именно устроен архив.
List<int> _phm({
  String id = _moduleId,
  required String version,
  int apiVersion = 1,
  Map<String, String>? assets,
  Map<String, String>? storage,
  List<String> dependencies = const [],
}) {
  return ModulePackageWriter.write(PackageContent(
    manifest: ModuleManifest.fromJson(<String, dynamic>{
      'id': id,
      'name': 'Заметки',
      'version': version,
      'apiVersion': apiVersion,
      'author': 'Test',
      'permissions': <String>[],
      'dependencies': [
        for (final dependency in dependencies)
          () {
            // Формат "id:minVersion" — только чтобы тест не тащил
            // конструктор модуля-по-зависимости в каждый вызов.
            final parts = dependency.split(':');
            return <String, dynamic>{
              'id': parts.first,
              if (parts.length > 1) 'minVersion': parts[1],
            };
          }(),
      ],
      'description': '',
      'icon': '',
    }),
    assets: [
      for (final entry in (assets ?? const <String, String>{}).entries)
        PackageAsset(
          path: 'assets/${entry.key}',
          bytes: utf8.encode(entry.value),
        ),
    ],
    data: storage == null
        ? null
        : PackageData(
            jsonDecode(jsonEncode(storage)) as Map<String, dynamic>,
          ),
  ));
}

/// Обмен, который доводит дело до конца и падает сразу после этого —
/// худший момент для сбоя, и именно его обязан пережить откат.
class _CommitThenFailSwap extends ModuleSandboxSwap {
  _CommitThenFailSwap({
    required super.supportDirectoryResolver,
    this.onCommit,
  });

  final Future<void> Function()? onCommit;

  @override
  Future<ModuleSandboxSwapResult> commit({
    required String moduleId,
    required Directory stagedDirectory,
  }) async {
    final result = await super.commit(
      moduleId: moduleId,
      stagedDirectory: stagedDirectory,
    );
    // Каталог прежней версии не должен остаться лежать после отката —
    // тест проверяет это по содержимому modules_previous.
    expect(result.previousDirectory, isNotNull);
    await onCommit?.call();
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'сбой сразу после обмена песочницы (тест)',
    );
  }
}

/// Обмен, который падает, не начав перемещений.
class _FailBeforeCommitSwap extends ModuleSandboxSwap {
  _FailBeforeCommitSwap({required super.supportDirectoryResolver});

  @override
  Future<ModuleSandboxSwapResult> commit({
    required String moduleId,
    required Directory stagedDirectory,
  }) {
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'сбой до обмена песочницы (тест)',
    );
  }
}

/// Обмен, который падает на подготовке, не начав перемещений.
class _FailStagingSwap extends ModuleSandboxSwap {
  _FailStagingSwap({required super.supportDirectoryResolver});

  @override
  Future<Directory> createStaging({required String moduleId}) {
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'сбой подготовки (тест)',
    );
  }
}

/// Обмен, который имитирует СБОЙ ПРОЦЕССА: песочница уже уведена в
/// сторону, а вернуть её не удалось (процесс убит до отката).
///
/// Отличие от [_CommitThenFailSwap] принципиально: там откат выполняется и
/// обязан всё вернуть, здесь отката нет и не будет — остаётся состояние,
/// из которого выкарабкивается только запуск приложения.
class _CrashingSwap extends ModuleSandboxSwap {
  _CrashingSwap({required super.supportDirectoryResolver});

  @override
  Future<ModuleSandboxSwapResult> commit({
    required String moduleId,
    required Directory stagedDirectory,
  }) async {
    await super.commit(moduleId: moduleId, stagedDirectory: stagedDirectory);
    // Падение между двумя переносами обмена: прежняя версия уже уведена
    // в сторону, а новая на место ещё не встала. Именно это состояние
    // остаётся на диске при убийстве процесса.
    final permanent = await permanentDirectory(moduleId);
    if (await permanent.exists()) {
      await permanent.delete(recursive: true);
    }
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'процесс убит между переносами обмена песочницы (тест)',
    );
  }

  @override
  Future<bool> restorePrevious({
    required String moduleId,
    Directory? previousDirectory,
    bool discardCurrent = true,
  }) {
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'откат не успел выполниться (тест)',
    );
  }

  @override
  Future<void> discardStagedVersions({required String moduleId}) {
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'уборка не успел выполниться (тест)',
    );
  }
}

/// Менеджер, у которого обмен реестра можно заставить падать. Фаза
/// обмена реестра идёт ПОСЛЕ обмена песочниц, поэтому это худший момент
/// для отката: песочница уже новая, а реестр — старый.
///
/// Остальные фазы (установка, enable/disable) работают как обычно: иначе
/// нельзя было бы подготовить исходное состояние модуля.
class _FailingUpdateManager extends ModuleManager {
  _FailingUpdateManager({
    required super.searchService,
    required super.storageFactory,
  });

  bool failOnUpdate = false;

  @override
  Future<void> update(Module newVersion) {
    if (!failOnUpdate) return super.update(newVersion);
    throw ModuleLifecycleError(newVersion.id, 'сбой обмена реестра (тест)');
  }
}

ModuleManifest _manifestOf(String id, {required String version}) =>
    ModuleManifest.fromJson(<String, dynamic>{
      'id': id,
      'name': 'Модуль $id',
      'version': version,
      'apiVersion': 1,
      'author': 'Test',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': '',
    });

class _FakeStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  /// Снимок читает хранилище первым делом; этот флаг делает чтение
  /// невозможным, чтобы проверить отказ на фазе снимка.
  bool failOnKeys = false;

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<List<String>> keys() async {
    if (failOnKeys) {
      throw StateError('хранилище недоступно (тест)');
    }
    return data.keys.toList();
  }
}

class _FakeStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> snapshots =
      <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => snapshots.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async =>
      snapshots[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    snapshots[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    snapshots.remove(moduleId);
  }
}

/// Встроенный модуль: обновлять его из внешнего пакета нельзя, и отказ
/// обязан наступить ДО чтения пакета, иначе проверка была бы
/// формальностью.
class _FakeBuiltin extends Module {
  @override
  ModuleManifest get manifest => const ModuleManifest(
        id: 'example',
        name: 'Пример',
        version: '1.0.0',
        apiVersion: 1,
        author: 'Core',
      );

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {}
}