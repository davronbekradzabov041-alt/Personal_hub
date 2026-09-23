import 'package:flutter/material.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_api.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_permission.dart';
import 'schedule_repository.dart';
import 'schedule_search_provider.dart';
import 'ui/schedule_screen.dart';

/// Первый полноценный функциональный модуль — Schedule.
///
/// Базовая версия: без ИИ, без автоматического распределения нагрузки,
/// без уведомлений, без синхронизации, без облака (прямой запрет
/// Этапа 14). Построен целиком на уже существующей модульной системе:
/// ModuleManifest/Module (Этап 7), ModuleManager (Этап 8, без
/// изменений — жизненный цикл Schedule ничем не отличается от
/// ExampleModule), ModuleStorage (Этап 9, никакой отдельной Isar-
/// коллекции под Schedule), SearchProvider (Этап 5/7).
class ScheduleModule extends Module {
  static const ModuleManifest _manifest = ModuleManifest(
    id: 'schedule',
    name: 'Расписание',
    version: '0.1.0',
    apiVersion: kCoreModuleApiVersion,
    author: 'Personal Hub',
    description: 'Планирование событий по дням: список на сегодня, '
        'календарь, создание/редактирование/удаление событий.',
    permissions: [ModulePermission.coreSearch],
  );

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.event_note_outlined;

  @override
  int get order => 100;

  ScheduleSearchProvider? _searchProvider;

  @override
  Future<void> onEnable(ModuleApi api) async {
    final provider = ScheduleSearchProvider(ScheduleRepository(api.storage));
    _searchProvider = provider;
    api.registerSearchProvider(provider);
  }

  @override
  Future<void> onDisable(ModuleApi api) async {
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Future<void> onUninstall(ModuleApi api) async {
    // Защитный дубль — см. тот же приём в ExampleModule (Этап 10):
    // по правилам ModuleManager до uninstall модуль обязательно
    // проходит через disable(), так что здесь это лишняя, но дешёвая
    // подстраховка, а не обязательная логика.
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Widget buildPage(BuildContext context) => ScheduleScreen(moduleId: id);
}
