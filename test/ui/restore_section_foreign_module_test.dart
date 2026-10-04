import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/ui/backup/backup_file_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/backup_operation_controller.dart';
import 'package:personal_hub/ui/widgets/backup/restore_section.dart';

/// UI-04: .pmb может принадлежать модулю, которого в приложении нет.
///
/// Backup переносится между устройствами и не обязан совпадать с текущим
/// набором модулей. Раньше `archiveModuleId` из preview без проверки
/// попадал в `_targetModuleId`, а тот — в `DropdownButtonFormField.value`.
/// Такого значения среди `items` нет, и Flutter падал с assertion.
/// Теперь неустановленный модуль оставляет выбор пустым, а пользователь
/// получает объяснение.
void main() {
  late _StubGateway gateway;
  late _StubFileService fileService;
  late BackupOperationController globalController;
  late BackupOperationController moduleController;

  setUp(() {
    gateway = _StubGateway();
    fileService = _StubFileService(
      picked: PickedFile(
        name: 'foreign-module.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    globalController = BackupOperationController(
      gateway: gateway,
      fileService: fileService,
    );
    moduleController = BackupOperationController(
      gateway: gateway,
      fileService: fileService,
    );
  });

  Widget app({required List<String> installedModuleIds}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RestoreSection(
            globalController: globalController,
            moduleController: moduleController,
            installedModuleIds: installedModuleIds,
            displayNameOf: gateway.displayNameOf,
          ),
        ),
      ),
    );
  }

  testWidgets('UI-04: .pmb чужого модуля не ломает секцию и не ставится в dropdown',
      (tester) async {
    // Модуль из архива ('foreign-module') отсутствует среди установленных.
    await tester.pumpWidget(app(installedModuleIds: ['installed-module']));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать .pmb файл'));
    await tester.pumpAndSettle();

    // Секция жива: Flutter-assertion на отсутствующий value не возник.
    expect(tester.takeException(), isNull);
    expect(find.byType(RestoreSection), findsOneWidget);

    // Dropdown существует и не содержит несуществующего значения.
    // Проверяем внутренний DropdownButton: у DropdownButtonFormField
    // параметр value — устаревший конструкторный аргумент, а не поле.
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, isNull,
        reason: 'неустановленный модуль не может быть выбран');
    expect(
      dropdown.items!.map((i) => i.value),
      ['installed-module'],
      reason: 'в dropdown только реально установленные модули',
    );

    // Пользователь получает понятное объяснение.
    expect(find.textContaining('не установлен'), findsOneWidget);

    // Восстановление невозможно: выбор пуст, значит кнопка заблокирована.
    final restoreButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Восстановить модуль'),
    );
    expect(restoreButton.onPressed, isNull,
        reason: 'без выбранного модуля восстановление запускаться не должно');
  });

  testWidgets('UI-04: установленный модуль выбирается автоматически',
      (tester) async {
    gateway.previewModuleIds = ['installed-module'];
    fileService.picked = PickedFile(
      name: 'installed-module.pmb',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    await tester.pumpWidget(app(installedModuleIds: ['installed-module']));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать .pmb файл'));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'installed-module',
        reason: 'для установленного модуля автовыбор обязан сохраниться');
    expect(find.textContaining('не установлен'), findsNothing);

    final restoreButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Восстановить модуль'),
    );
    expect(restoreButton.onPressed, isNotNull,
        reason: 'с выбранным модулем восстановление доступно');
  });

  testWidgets('UI-04: предупреждение исчезает после выбора «своего» backup',
      (tester) async {
    await tester.pumpWidget(app(installedModuleIds: ['installed-module']));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать .pmb файл'));
    await tester.pumpAndSettle();
    expect(find.textContaining('не установлен'), findsOneWidget);

    // Второй выбор — уже установленный модуль.
    gateway.previewModuleIds = ['installed-module'];
    fileService.picked = PickedFile(
      name: 'installed-module.pmb',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    await tester.tap(find.text('Выбрать .pmb файл'));
    await tester.pumpAndSettle();

    expect(find.textContaining('не установлен'), findsNothing,
        reason: 'старое предупреждение не должно сохраняться');
  });

  testWidgets('UI-04: модуль исчез из списка — значение сбрасывается без падения',
      (tester) async {
    // Начинаем с .pmb установленного модуля, чтобы значение было задано.
    gateway.previewModuleIds = ['installed-module'];
    fileService.picked = PickedFile(
      name: 'installed-module.pmb',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    await tester.pumpWidget(app(installedModuleIds: ['installed-module']));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать .pmb файл'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          ).value,
      'installed-module',
    );

    // Модуль удалён из приложения, пока секция ещё на экране.
    await tester.pumpWidget(app(installedModuleIds: ['other-module']));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'сброс неустановленного значения не должен давать assertion');
  });
}

/// Заглушка gateway: методы реализованы явно с `@override`, чтобы
/// изменение контракта ломало компиляцию, а не выполнение теста.
class _StubGateway implements BackupGateway {
  List<String> previewModuleIds = ['foreign-module'];

  @override
  Future<List<String>> installedModuleIds() async => const ['installed-module'];

  @override
  String displayNameOf(String moduleId) {
    switch (moduleId) {
      case 'installed-module':
        return 'Установленный модуль';
      case 'foreign-module':
        return 'Чужой модуль';
      default:
        return moduleId;
    }
  }

  @override
  Future<BackupArtifact> createGlobalBackup(GlobalBackupSelection selection) {
    throw UnimplementedError();
  }

  @override
  Future<BackupArtifact> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<BackupPreview> inspectGlobalBackup(List<int> archiveBytes) async {
    return BackupPreview(
      title: 'Глобальный backup',
      createdAt: DateTime(2026, 3, 10),
      appVersion: '1.0.0',
      moduleIds: previewModuleIds,
      includesSettings: true,
      includesData: true,
      includesAssets: false,
    );
  }

  @override
  Future<BackupPreview> inspectModuleBackup(List<int> archiveBytes) async {
    return BackupPreview(
      title: 'Резервная копия модуля',
      createdAt: DateTime(2026, 3, 10),
      appVersion: '1.0.0',
      moduleIds: previewModuleIds,
      includesSettings: false,
      includesData: true,
      includesAssets: false,
    );
  }

  @override
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) async {
    return const RestoreOutcome(isSuccess: true, moduleId: 'installed-module');
  }
}

/// Файловый сервис, отдающий заранее заданный файл.
class _StubFileService implements BackupFileService {
  _StubFileService({this.picked});

  PickedFile? picked;

  @override
  Future<SaveOutcome> saveArtifact(BackupArtifact artifact, String title) async {
    return const SaveOutcome.cancelled();
  }

  @override
  Future<PickedFile?> pickBackupFile({
    required List<String> extensions,
    String? title,
  }) async {
    return picked;
  }
}