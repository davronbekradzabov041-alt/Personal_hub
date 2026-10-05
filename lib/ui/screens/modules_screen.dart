import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/design/design_system.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../core/modules/module_state_persistence.dart';
import '../../core/modules/module_state_persistence_scope.dart';
import '../../core/modules/platform/module_importer.dart';
import '../widgets/module_store/available_section.dart';
import '../widgets/module_store/installed_section.dart';
import '../widgets/module_store/update_section.dart';

/// Экран управления модулями (Module Store, Этап 12).
///
/// Три раздела — Установленные/Доступные/Обновления — как простые
/// секции одного прокручиваемого списка, а не вкладки: проще и
/// достаточно для того объёма модулей, что есть сейчас (один
/// встроенный + временный каталог из трёх записей).
/// AppBar/Drawer предоставляется AppShell.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Модули'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => _importModule(context),
            tooltip: 'Импорт модуля',
          ),
          // Обновление из файла .phm — второй пользовательский вход в
          // тот же механизм, что и импорт: те же PackageReader,
          // security-guard и ManifestValidator, только целевой модуль
          // уже установлен. Отдельное действие рядом с импортом, а не в
          // разделе «Обновления»: там перечисляются версии ВСТРОЕННОГО
          // каталога, а не файлы с диска.
          IconButton(
            icon: const Icon(Icons.upgrade),
            onPressed: () => _updateModule(context),
            tooltip: 'Обновить модуль из файла',
          ),
        ],
      ),
      body: ResponsiveBuilder(
        builder: (context, layout) {
          final padding = AppBreakpoints.screenPadding(context);
          return ListView(
            padding: padding,
            children: [
              AppComponents.sectionHeader(
                context: context,
                title: 'Установленные',
              ),
              const InstalledSection(),
              SizedBox(height: AppSpacing.xl),
              AppComponents.sectionHeader(
                context: context,
                title: 'Доступные',
              ),
              const AvailableSection(),
              SizedBox(height: AppSpacing.xl),
              AppComponents.sectionHeader(
                context: context,
                title: 'Обновления',
              ),
              const UpdateSection(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importModule(BuildContext context) async {
    final pickerResult = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите .phm файл модуля',
      type: FileType.custom,
      allowedExtensions: ['phm'],
      allowMultiple: false,
    );

    if (pickerResult == null || pickerResult.files.isEmpty) {
      // User cancelled
      return;
    }

    final file = pickerResult.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать файл')),
      );
      return;
    }

    final manager = ModuleManagerScope.of(context);

    // Импорт .phm меняет состояние модулей (регистрирует и
    // устанавливает новый модуль), поэтому через него обязано пройти
    // то же runAndFlush, что и через кнопки Module Store: без
    // ожидания записи состояния UI показывал «успешно импортирован»
    // раньше, чем состояние оказывалось в хранилище, и немедленное
    // завершение процесса теряло результат импорта.
    final persistence = ModuleStatePersistenceScope.of(context);
    final importer = ModuleImporter(moduleManager: manager);

    ModuleImportOutcome? importResult;
    try {
      await persistence.runAndFlush(() async {
        importResult = await importer.importFromBytes(bytes);
      });
    } on ModuleStatePersistenceException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.reason)),
      );
      return;
    }

    if (!context.mounted) return;

    if (importResult == null || importResult!.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: ${importResult?.error ?? 'нет результата'}')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Модуль ${importResult!.moduleId} успешно импортирован')),
    );
  }

  /// Обновление установленного модуля из .phm-файла.
  ///
  /// Отличие от импорта ровно одно и оно существенное: целевой модуль
  /// уже установлен, поэтому обновление НЕ трогает его данные и
  /// состояние (ModuleImporter.updateFromPackageBytes) и обязано дойти
  /// до записи состояния через тот же runAndFlush — версия модуля
  /// записывается как installedVersion, и без ожидания записи
  /// пользователь увидел бы «обновлён» при версии, которая не пережила
  /// бы перезапуск.
  ///
  /// stateStore передаётся импортёру не для красоты: снимок, снятый
  /// перед обновлением, обязан быть сделан тем же хранилищем, откуда
  /// приложение читает состояние при старте, иначе откат записал бы
  /// мимо.
  Future<void> _updateModule(BuildContext context) async {
    final pickerResult = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите .phm файл обновления',
      type: FileType.custom,
      allowedExtensions: ['phm'],
      allowMultiple: false,
    );

    if (pickerResult == null || pickerResult.files.isEmpty) {
      // User cancelled
      return;
    }

    final bytes = pickerResult.files.first.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать файл')),
      );
      return;
    }

    final manager = ModuleManagerScope.of(context);
    final persistence = ModuleStatePersistenceScope.of(context);
    final importer = ModuleImporter(
      moduleManager: manager,
      stateStore: persistence.stateStore,
    );

    ModuleImportOutcome? updateResult;
    try {
      await persistence.runAndFlush(() async {
        updateResult = await importer.updateFromPackageBytes(bytes);
      });
    } on ModuleStatePersistenceException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.reason)),
      );
      return;
    }

    if (!context.mounted) return;

    if (updateResult == null || updateResult!.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ошибка обновления: ${updateResult?.error ?? 'нет результата'}',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Модуль ${updateResult!.moduleId} обновлён')),
    );
  }
}
