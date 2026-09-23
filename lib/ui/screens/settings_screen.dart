import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/settings/app_settings_scope.dart';
import '../../core/design/design_system.dart';
import '../widgets/app_drawer.dart';

/// Экран настроек приложения.
///
/// Заменяет заглушку Этапа 1. Читает и меняет состояние через
/// AppSettingsScope.of(context) (core/settings/) — каждое
/// изменение сразу сохраняется в Isar, отдельной кнопки
/// "Сохранить" не требуется.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppSettingsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      drawer: const AppDrawer(),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            padding: AppInsets.md,
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
