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
/// достаточно для того объёма модулей, что есть сейчас.
///
/// ## Почему заголовок не всегда AppBar
///
/// В компактной раскладке (телефон) AppBar уже показывает оболочка —
/// `_TopContextBar` в AppShell со строкой «Personal Hub». Свой AppBar
/// здесь давал ВТОРОЙ тулбар подряд, и «Модули» уезжал на второй
/// экран вниз. Поэтому на телефоне заголовок и действия лежат первым
/// блоком прокручиваемого содержимого, а на планшете/рельсе (где
/// оболочка верхней панели не даёт) — остаются в AppBar.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isCompact = AppBreakpoints.navigationType(context) ==
        NavigationType.drawer;

    if (isCompact) {
      return _buildCompactBody(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Модули'),
        actions: [
          _ImportAction(),
          const SizedBox(width: 8),
          _UpdateAction(),
        ],
      ),
      body: _buildList(context),
    );
  }

  Widget _buildCompactBody(BuildContext context) {
    return _buildList(
      context,
      header: const _ModulesHeader(isCompact: true),
    );
  }

  Widget _buildList(BuildContext context, {Widget? header}) {
    // Отступы списка: 16 dp по бокам, вверху 0 (его уже даёт AppBar
    // оболочки или наш собственный заголовок), снизу — просвет под
    // плавающий док: высота дока + его нижний отступ + системный
    // нижний inset + 16 dp. Системный inset добавляется ровно один раз:
    // док получает его через свой SafeArea и не уменьшает область
    // контента, поэтому прокрутка обязана учесть его сама.
    return ListView(
      padding: AppInsets.dockClearance(context).copyWith(
        left: 16,
        right: 16,
        top: 0,
      ),
      children: [
        if (header != null) header,
        AppComponents.sectionHeader(
          context: context,
          title: 'Установленные',
        ),
        // 4 dp здесь + 8 dp, которые `sectionHeader` уже даёт снизу,
        // = ровно 12 dp от заголовка секции до её содержимого.
        const SizedBox(height: AppSpacing.xs),
        const InstalledSection(),
        const SizedBox(height: 24),
        AppComponents.sectionHeader(
          context: context,
          title: 'Доступные',
        ),
        const SizedBox(height: AppSpacing.xs),
        const AvailableSection(),
        const SizedBox(height: 24),
        AppComponents.sectionHeader(
          context: context,
          title: 'Обновления',
        ),
        const SizedBox(height: AppSpacing.xs),
        const UpdateSection(),
      ],
    );
  }
}

/// Заголовок экрана для компактной раскладки: название и оба действия
/// в одном ряду. Кнопки те же, что и в AppBar планшетной раскладки.
class _ModulesHeader extends StatelessWidget {
  const _ModulesHeader({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Модули',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ImportAction(),
          const SizedBox(width: 8),
          _UpdateAction(),
        ],
      ),
    );
  }
}

/// Импорт модуля из .phm.
///
/// Размер задан явно (40 dp), а не подобран внутри `IconButton`: так
/// зазор между двумя кнопками заголовка равен ровно 8 dp — значению
/// [AppSpacing.space2]. По умолчанию кнопка занимала бы всю отведённую
/// ширину и «расстояние между кнопками» перестало бы быть управляемым.
class _ImportAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.file_upload_outlined),
        onPressed: () => _importModule(context),
        // Тултип оставлен прежним: он уже понятный, а тесты
        // (module_import_persistence_test) находят кнопку по нему.
        tooltip: 'Импорт модуля',
      ),
    );
  }
}

/// Обновление установленного модуля из .phm.
class _UpdateAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.upgrade),
        onPressed: () => _updateModule(context),
        tooltip: 'Обновить модуль из файла',
      ),
    );
  }
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
