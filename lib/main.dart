import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app.dart';
import 'core/database/isar_service.dart';
import 'core/database/models/core_test_item.dart';
import 'core/database/repositories/app_settings_repository.dart';
import 'core/database/repositories/core_test_item_repository.dart';
import 'core/database/repositories/module_state_repository.dart';
import 'core/modules/builtin_module_installer.dart';
import 'core/modules/module_bootstrap.dart';
import 'core/modules/module_manager.dart';
import 'core/modules/module_state_persistence.dart';
import 'core/modules/module_state_restorer.dart';
import 'core/search/global_search_service.dart';
import 'core/search/providers/core_test_item_search_provider.dart';
import 'core/settings/app_settings_controller.dart';

/// Точка входа приложения.
///
/// Файл намеренно минимален: вся настройка (тема, навигация,
/// инициализация сервисов) вынесена в app.dart и core/.
/// Порядок здесь важен: база данных → регистрация модулей → настройки
/// → поиск → менеджер модулей → восстановление их состояния из Isar →
/// автоустановка встроенных модулей, которые видят Isar впервые
/// (Этап 10), всё до runApp(), чтобы первый кадр UI уже был готов.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Отключить загрузку шрифтов из сети — приложение офлайн-first.
  // Шрифты используются через кэш GoogleFonts или системный fallback.
  GoogleFonts.config.allowRuntimeFetching = false;

  await IsarService.init();
  registerCoreModules();

  final settingsController = AppSettingsController(AppSettingsRepository());
  await settingsController.load();

  final testItemRepository = CoreTestItemRepository();
  await _seedDemoDataIfEmpty(testItemRepository);

  final searchService = GlobalSearchService()
    ..registerProvider(CoreTestItemSearchProvider(testItemRepository));

  // ModuleManager (Этап 8) + постоянное хранение (Этап 9) + автоустановка
  // встроенных модулей при первом запуске (Этап 10). Порядок: сначала
  // слушатель персистентности (ничего не пропустить), потом
  // восстановление уже известных модулей, и только потом — установка
  // тех, кого раньше не было ни разу (первый запуск для этого модуля).
  final moduleManager = ModuleManager(searchService: searchService);
  final moduleStateRepository = ModuleStateRepository();
  ModuleStatePersistence(moduleManager, moduleStateRepository);
  await ModuleStateRestorer(moduleManager, moduleStateRepository).restore();
  await ensureBuiltinModulesInstalled(moduleManager, moduleStateRepository);

  runApp(PersonalHubApp(
    settingsController: settingsController,
    searchService: searchService,
    moduleManager: moduleManager,
  ));
}

/// Заполняет тестовую коллекцию ядра парой записей при самом
/// первом запуске, чтобы было что искать на Этапе 5. Чисто
/// демонстрационные данные — как и сам CoreTestItem, их можно
/// будет удалить, когда появятся настоящие модули.
Future<void> _seedDemoDataIfEmpty(CoreTestItemRepository repository) async {
  final existing = await repository.getAll();
  if (existing.isNotEmpty) return;

  await repository.add(CoreTestItem()
    ..title = 'Пример записи'
    ..description = 'Тестовые данные ядра для проверки поиска');
  await repository.add(CoreTestItem()
    ..title = 'Вторая запись'
    ..description = 'Ещё одна запись — чтобы проверить фильтрацию');
  await repository.add(CoreTestItem()
    ..title = 'Заметка про Isar'
    ..description = 'Показывает, что поиск ищет и по заголовку, и хранит описание');
}
