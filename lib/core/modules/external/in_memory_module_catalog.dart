/// Временный встроенный каталог "доступных" модулей для Module Store
/// (Этап 12).
///
/// Каждая запись — сырая строка manifest.json, в точности такого же
/// формата, что и настоящий внешний пакет (Этап 11) — чтобы установка
/// из каталога проходила через тот же ManifestParser/ManifestValidator/
/// ModuleImportResult, что и реальный внешний модуль будет проходить
/// в будущем. Разница только в источнике строки: здесь это константа
/// в коде, а не файл на диске или из ZIP (Этап 12 явно запрещает то
/// и другое).
///
/// `installManifestJson` — версия, которую получает пользователь при
/// первой установке. `latestManifestJson` — версия, которую каталог
/// "предлагает" в разделе Обновления. У Notes Lite они разные
/// (1.0.0 → 1.1.0) специально, чтобы раздел Обновления было на чём
/// показать; у Calendar Lite и Example Module — совпадают (обновлять
/// нечего).
class ModuleCatalogEntry {
  final String id;
  final String installManifestJson;
  final String latestManifestJson;

  const ModuleCatalogEntry({
    required this.id,
    required this.installManifestJson,
    required this.latestManifestJson,
  });
}

class InMemoryModuleCatalog {
  InMemoryModuleCatalog._();

  static const List<ModuleCatalogEntry> entries = [
    ModuleCatalogEntry(
      id: 'notes-lite',
      installManifestJson: _notesLiteV1,
      latestManifestJson: _notesLiteV1_1,
    ),
    ModuleCatalogEntry(
      id: 'calendar-lite',
      installManifestJson: _calendarLiteV1,
      latestManifestJson: _calendarLiteV1,
    ),
    // Специально включён: id 'example' уже занят настоящим встроенным
    // ExampleModule (зарегистрирован при старте, Этап 10). Попытка
    // установить эту запись из каталога должна быть отклонена —
    // наглядная демонстрация проверки "дублирующийся moduleId"
    // (Этап 11) на реалистичном сценарии, а не только в тестах на
    // синтетических данных.
    ModuleCatalogEntry(
      id: 'example',
      installManifestJson: _exampleCatalogManifest,
      latestManifestJson: _exampleCatalogManifest,
    ),
  ];

  static const _notesLiteV1 = '''
{
  "id": "notes-lite",
  "name": "Notes Lite",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Простые заметки — тестовый пакет каталога.",
  "permissions": [],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';

  static const _notesLiteV1_1 = '''
{
  "id": "notes-lite",
  "name": "Notes Lite",
  "version": "1.1.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Простые заметки — тестовый пакет каталога (обновлённая версия).",
  "permissions": [],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';

  static const _calendarLiteV1 = '''
{
  "id": "calendar-lite",
  "name": "Calendar Lite",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Простой календарь — тестовый пакет каталога.",
  "permissions": [],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';

  static const _exampleCatalogManifest = '''
{
  "id": "example",
  "name": "Example Module",
  "version": "0.1.0",
  "apiVersion": 1,
  "author": "Personal Hub",
  "description": "То же id, что и у встроенного модуля-примера — тестовый пакет для проверки защиты от дублирования id.",
  "permissions": [],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';
}
