import 'package:flutter/material.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/settings/app_settings_scope.dart';
import '../../core/design/design_system.dart';
import '../../core/navigation/app_routes.dart';

/// Экран настроек приложения.
///
/// Заменяет заглушку Этапа 1. Читает и меняет состояние через
/// AppSettingsScope.of(context) (core/settings/) — каждое
/// изменение сразу сохраняется в Isar, отдельной кнопки
/// "Сохранить" не требуется.
///
/// Экран открывается как корневой именованный маршрут
/// (AppRoutes.settings), то есть поверх AppShell, поэтому свой
/// AppBar он не строит: оболочка остаётся под ним, а не оборачивает
/// его. Раздел «Данные» ведёт на Backup через именованный маршрут
/// AppRoutes.backup — единственный способ навигации к этому экрану.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppSettingsScope.of(context);

    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            padding: AppInsets.screenBody(context),
            children: [
              AppComponents.sectionHeader(
                context: context,
                title: 'Тема оформления',
              ),
              SizedBox(height: AppSpacing.sm),
              _ThemeRadioGroup(
                controller: controller,
              ),
              SizedBox(height: AppSpacing.lg),
              Divider(),
              SizedBox(height: AppSpacing.lg),
              AppComponents.sectionHeader(
                context: context,
                title: 'Язык',
              ),
              SizedBox(height: AppSpacing.sm),
              _LanguageRadioGroup(
                controller: controller,
              ),
              SizedBox(height: AppSpacing.xl),
              Divider(),
              SizedBox(height: AppSpacing.lg),
              AppComponents.sectionHeader(
                context: context,
                title: 'Данные',
              ),
              SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Резервные копии'),
                subtitle: const Text(
                  'Создать backup приложения или модуля и восстановить данные',
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(context).pushNamed(AppRoutes.backup);
                },
              ),
              SizedBox(height: AppSpacing.xl),
              Text(
                'Выбор языка пока только сохраняется. Перевод '
                'интерфейса подключится, когда появится система '
                'локализации строк — это отдельная задача за '
                'пределами Этапа 4.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeRadioGroup extends StatelessWidget {
  final AppSettingsController controller;

  const _ThemeRadioGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    return RadioGroup<ThemeMode>(
      groupValue: controller.themeMode,
      onChanged: (mode) => controller.setThemeMode(mode!),
      child: Column(
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('Как в системе'),
            value: ThemeMode.system,
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Светлая'),
            value: ThemeMode.light,
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Тёмная'),
            value: ThemeMode.dark,
          ),
        ],
      ),
    );
  }
}

class _LanguageRadioGroup extends StatelessWidget {
  final AppSettingsController controller;

  const _LanguageRadioGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: controller.language,
      onChanged: (lang) => controller.setLanguage(lang!),
      child: Column(
        children: [
          RadioListTile<String>(
            title: const Text('Русский'),
            value: 'ru',
          ),
          RadioListTile<String>(
            title: const Text('Oʻzbekcha'),
            value: 'uz',
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
          ),
        ],
      ),
    );
  }
}
