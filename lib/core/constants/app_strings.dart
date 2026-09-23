/// Текстовые константы ядра.
///
/// Вынесены в отдельный файл, чтобы на Этапе 4 (настройки,
/// язык) их было легко заменить на систему локализации,
/// не трогая экраны.
class AppStrings {
  AppStrings._();

  static const String appName = 'Personal Hub';
  static const String homeTitle = 'Главная';
  static const String settingsTitle = 'Настройки';
  static const String noModulesYet = 'Модули пока не подключены';
  static const String comingSoon = 'Этот раздел появится на следующих этапах';
}
