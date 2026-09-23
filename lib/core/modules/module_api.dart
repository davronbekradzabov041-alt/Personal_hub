import '../search/search_provider.dart';
import 'module_storage.dart';

/// Точка входа модуля в ядро.
///
/// Передаётся в lifecycle-хуки Module (onInstall/onEnable/
/// onDisable/onUninstall). Модуль получает доступ к ядру ТОЛЬКО
/// через этот контракт — не напрямую к IsarService или
/// GlobalSearchService. Это даёт ядру место для проверки
/// разрешений (ModulePermission) перед выполнением действия, не
/// меняя сам контракт.
///
/// Конкретную реализацию (с проверкой permissions и настоящим
/// Isar-хранилищем) даст ModuleManager на Этапе 8 — этот файл
/// только описывает форму.
abstract class ModuleApi {
  /// Изолированное хранилище только этого модуля.
  ModuleStorage get storage;

  /// Регистрирует источник данных модуля в глобальном поиске
  /// (core/search/GlobalSearchService). Требует разрешения
  /// ModulePermission.coreSearch — саму проверку выполняет
  /// реализация (Этап 8), не этот контракт.
  void registerSearchProvider(SearchProvider provider);

  /// Убирает ранее зарегистрированный источник — модуль должен
  /// вызывать это в onDisable/onUninstall, чтобы выключенный
  /// модуль не оставался в результатах поиска.
  void unregisterSearchProvider(SearchProvider provider);
}
