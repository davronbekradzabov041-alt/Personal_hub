import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/design/design_system.dart';
import 'package:personal_hub/ui/backup/backup_file_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/backup_services_scope.dart';
import 'package:personal_hub/ui/screens/backup_screen.dart';

/// Фейковый gateway: не трогает Isar и позволяет управлять результатом
/// и задержкой каждой операции.
class _FakeGateway implements BackupGateway {
  List<String> installedIds = const ['alpha', 'beta'];

  /// Задержка операции — нужна, чтобы поймать loading-состояние.
  Duration delay = Duration.zero;

  /// Что выбросить из createGlobalBackup.
  Object? globalBackupError;

  /// Что выбросить из inspectModuleBackup.
  Object? inspectError;

  /// Что вернуть из restoreModuleBackup.
  RestoreOutcome? restoreResult;

  // Запоминаются вызовы — тесты проверяют, что UI передал нужные данные.
  GlobalBackupSelection? lastGlobalSelection;
  ModuleBackupOptions? lastModuleOptions;
  String? lastModuleId;
  String? lastRestoreModuleId;
  ModuleBackupOptions? lastRestoreOptions;
  int createGlobalCalls = 0;
  int createModuleCalls = 0;
  int restoreCalls = 0;

  Future<void> _wait() => Future<void>.delayed(delay);

  @override
  Future<List<String>> installedModuleIds() async => installedIds;

  @override
  String displayNameOf(String moduleId) =>
      moduleId == 'alpha' ? 'Альфа' : 'Бета';

  @override
  Future<BackupArtifact> createGlobalBackup(
    GlobalBackupSelection selection,
  ) async {
    createGlobalCalls++;
    lastGlobalSelection = selection;
    await _wait();
    if (globalBackupError != null) throw globalBackupError!;
    return const BackupArtifact(fileName: 'backup.pbk', bytes: [1, 2, 3]);
  }

  @override
  Future<BackupArtifact> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  ) async {
    createModuleCalls++;
    lastModuleId = moduleId;
    lastModuleOptions = options;
    await _wait();
    return const BackupArtifact(fileName: 'module.pmb', bytes: [4, 5, 6]);
  }

  @override
  Future<BackupPreview> inspectGlobalBackup(List<int> archiveBytes) async {
    await _wait();
    if (inspectError != null) throw inspectError!;
    return _preview();
  }

  @override
  Future<BackupPreview> inspectModuleBackup(List<int> archiveBytes) async {
    await _wait();
    if (inspectError != null) throw inspectError!;
    return _preview();
  }

  @override
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) async {
    restoreCalls++;
    lastRestoreModuleId = moduleId;
    lastRestoreOptions = options;
    await _wait();
    return restoreResult ??
        const RestoreOutcome(
          isSuccess: true,
          moduleId: 'alpha',
          appliedComponents: ['data'],
        );
  }

  BackupPreview _preview() => BackupPreview(
        title: 'Backup',
        createdAt: DateTime.utc(2026, 1, 1),
        appVersion: '1.0.0',
        moduleIds: const ['alpha'],
        includesSettings: false,
        includesData: true,
        includesAssets: false,
      );
}

/// Фейковый файловый сервис.
class _FakeFileService implements BackupFileService {
  /// null — пользователь отменил выбор файла.
  PickedFile? fileToPick;

  /// true — сохранение отменено.
  bool cancelSave = false;

  Object? saveError;

  int saveCalls = 0;
  int pickCalls = 0;

  @override
  Future<SaveOutcome> saveArtifact(
    BackupArtifact artifact,
    String title,
  ) async {
    saveCalls++;
    if (saveError != null) throw saveError!;
    return cancelSave
        ? const SaveOutcome.cancelled()
        : const SaveOutcome.saved('/tmp/out');
  }

  @override
  Future<PickedFile?> pickBackupFile({
    required List<String> extensions,
    required String title,
  }) async {
    pickCalls++;
    final file = fileToPick;
    if (file == null) return null;
    return file;
  }
}

void main() {
  late _FakeGateway gateway;
  late _FakeFileService fileService;

  setUp(() {
    gateway = _FakeGateway();
    fileService = _FakeFileService();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BackupServicesScope(
          gateway: gateway,
          fileService: fileService,
          child: const BackupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Экран длиннее тестового окна, а ListView ленивый: секция ниже
  /// может быть ещё не построена. Поэтому сначала прокручиваем до
  /// элемента, и только потом нажимаем.
  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tapAt(tester, find.text(text));

  group('открытие экрана', () {
    testWidgets('Backup UI открывается и показывает все секции',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Резервные копии'), findsOneWidget);
      expect(find.text('Глобальный backup'), findsOneWidget);
      expect(find.text('Backup модуля'), findsOneWidget);

      // Секция восстановления ниже по списку и лениво не построена —
      // прокручиваем до неё.
      await tester.scrollUntilVisible(
        find.text('Восстановление'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Восстановление'), findsOneWidget);
    });

    testWidgets('список установленных модулей подхватывается', (tester) async {
      await pumpScreen(tester);

      // «Все модули (2)» — оба фейковых модуля установлены.
      expect(find.textContaining('Все модули (2)'), findsOneWidget);
    });
  });

  group('Global Backup', () {
    testWidgets('можно выбрать компоненты', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Настройки приложения'), findsOneWidget);
      expect(find.text('Данные модулей'), findsOneWidget);
      expect(find.text('Файлы модулей'), findsOneWidget);

      // Выключаем данные модулей.
      await tapText(tester, 'Данные модулей');

      await tapText(tester, 'Создать глобальный backup');

      expect(gateway.lastGlobalSelection!.includeModuleData, isFalse);
      expect(gateway.lastGlobalSelection!.includeGlobalSettings, isTrue);
    });

    testWidgets('создание .pbk вызывает backend и сохраняет файл',
        (tester) async {
      await pumpScreen(tester);

      await tapText(tester, 'Создать глобальный backup');

      expect(gateway.createGlobalCalls, 1);
      expect(fileService.saveCalls, 1);
      expect(find.textContaining('Backup сохранён'), findsOneWidget);
    });

    testWidgets('можно выбрать конкретные модули', (tester) async {
      await pumpScreen(tester);

      await tapText(tester, 'Выбрать модули');

      // Чекбоксы модулей появились.
      expect(find.text('Альфа'), findsOneWidget);
      expect(find.text('Бета'), findsOneWidget);

      await tapText(tester, 'Бета');

      await tapText(tester, 'Создать глобальный backup');

      final selection = gateway.lastGlobalSelection!;
      expect(selection.allInstalled, isFalse);
      expect(selection.moduleIds, {'beta'});
    });
  });

  group('Module Backup', () {
    testWidgets('без выбранного модуля кнопка неактивна', (tester) async {
      await pumpScreen(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Создать backup модуля'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('создание .pmb передаёт выбранные компоненты', (tester) async {
      await pumpScreen(tester);

      // Выбираем модуль.
      await tapAt(tester, find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Альфа').last);
      await tester.pumpAndSettle();

      // Выключаем файлы.
      await tapText(tester, 'Файлы');

      await tapText(tester, 'Создать backup модуля');

      expect(gateway.createModuleCalls, 1);
      expect(gateway.lastModuleId, 'alpha');
      expect(gateway.lastModuleOptions!.includeAssets, isFalse);
      expect(gateway.lastModuleOptions!.includeState, isTrue);
      expect(gateway.lastModuleOptions!.includeData, isTrue);
      expect(find.textContaining('Backup сохранён'), findsOneWidget);
    });
  });

  group('Restore', () {
    testWidgets('восстановление не запускается без подтверждения',
        (tester) async {
      await pumpScreen(tester);

      fileService.fileToPick = PickedFile(
        name: 'module.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await tapText(tester, 'Выбрать .pmb файл');

      // Файл проверен, показано содержимое.
      expect(find.text('Файл проверен'), findsOneWidget);

      await tapText(tester, 'Восстановить модуль');

      // Диалог подтверждения показан, restore ещё не выполнялся.
      expect(find.text('Восстановить данные модуля?'), findsOneWidget);
      expect(gateway.restoreCalls, 0);

      // Отмена — данные не тронуты.
      await tapText(tester, 'Отмена');

      expect(gateway.restoreCalls, 0);
    });

    testWidgets('диалог показывает файл, модуль и режим', (tester) async {
      await pumpScreen(tester);

      fileService.fileToPick = PickedFile(
        name: 'my_backup.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await tapText(tester, 'Выбрать .pmb файл');
      await tapText(tester, 'Восстановить модуль');

      expect(find.text('my_backup.pmb'), findsWidgets);
      expect(find.text('Альфа'), findsWidgets);
      // Режим по умолчанию — полный, и он назван в диалоге.
      expect(find.textContaining('Полный'), findsWidgets);
    });

    testWidgets('подтверждение запускает restore с выбранным режимом',
        (tester) async {
      await pumpScreen(tester);

      fileService.fileToPick = PickedFile(
        name: 'module.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await tapText(tester, 'Выбрать .pmb файл');

      // Выбираем режим «Только данные».
      await tapAt(tester, find.widgetWithText(ChoiceChip, 'Только данные'));

      await tapText(tester, 'Восстановить модуль');
      await tapText(tester, 'Восстановить');

      expect(gateway.restoreCalls, 1);
      expect(gateway.lastRestoreModuleId, 'alpha');
      expect(gateway.lastRestoreOptions!.includeData, isTrue);
      expect(gateway.lastRestoreOptions!.includeState, isFalse);
      expect(gateway.lastRestoreOptions!.includeAssets, isFalse);
      expect(find.text('Модуль «alpha» восстановлен: data.'), findsOneWidget);
    });

    testWidgets('неудачный restore показывает ошибку без стектрейса',
        (tester) async {
      await pumpScreen(tester);

      fileService.fileToPick = PickedFile(
        name: 'module.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      gateway.restoreResult = const RestoreOutcome(
        isSuccess: false,
        moduleId: 'alpha',
        message: 'internal failure detail',
      );

      await tapText(tester, 'Выбрать .pmb файл');
      await tapText(tester, 'Восстановить модуль');
      await tapText(tester, 'Восстановить');

      expect(find.textContaining('Восстановление не удалось'), findsOneWidget);
      // Внутренний текст ошибки пользователю не показывается.
      expect(find.textContaining('internal failure detail'), findsNothing);
    });

    testWidgets('ошибка чтения файла переводится на понятный язык',
        (tester) async {
      await pumpScreen(tester);

      fileService.fileToPick = PickedFile(
        name: 'broken.pmb',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      gateway.inspectError = const ChecksumMismatchException();

      await tapText(tester, 'Выбрать .pmb файл');

      expect(find.textContaining('контрольная сумма'), findsOneWidget);
      expect(find.textContaining('ChecksumMismatchException'), findsNothing);
    });
  });

  group('состояния и защита от повторного запуска', () {
    testWidgets('отмена выбора файла — не ошибка', (tester) async {
      await pumpScreen(tester);

      // fileToPick == null → пользователь закрыл диалог.
      await tapText(tester, 'Выбрать .pmb файл');

      expect(find.textContaining('отменён'), findsOneWidget);
      expect(find.textContaining('Ошибка'), findsNothing);
    });

    testWidgets('отмена сохранения не сообщает об успехе', (tester) async {
      await pumpScreen(tester);
      fileService.cancelSave = true;

      await tapText(tester, 'Создать глобальный backup');

      expect(gateway.createGlobalCalls, 1);
      expect(find.textContaining('Сохранение отменено'), findsOneWidget);
      expect(find.textContaining('Backup сохранён'), findsNothing);
    });

    testWidgets('пока операция выполняется, повторный запуск невозможен',
        (tester) async {
      await pumpScreen(tester);
      gateway.delay = const Duration(milliseconds: 200);

      // Здесь нельзя использовать tapAt: он завершает pumpAndSettle,
      // а операция с задержкой к тому моменту уже закончилась бы и
      // loading-состояние не наблюдалось бы. Поэтому тапаем без settle.
      final button = find.widgetWithText(
        FilledButton,
        'Создать глобальный backup',
      );
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      // Операция идёт — баннер показывает прогресс, кнопка заблокирована.
      expect(find.text('Выполняется операция…'), findsOneWidget);
      final busyButton = tester.widget<FilledButton>(button);
      expect(busyButton.onPressed, isNull);

      // Повторное нажатие не запускает вторую операцию.
      await tester.tap(button, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(gateway.createGlobalCalls, 1,
          reason: 'вторая операция не должна была запускаться');
      expect(find.textContaining('Backup сохранён'), findsOneWidget);
    });

    testWidgets('после завершения кнопка снова активна', (tester) async {
      await pumpScreen(tester);

      await tapText(tester, 'Создать глобальный backup');

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Создать глобальный backup'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
