# PROJECT_MAP.md — Personal Hub

Карта проекта на момент передачи в Kilo Code. Подробная история
принятых решений по каждому этапу — в `README.md` (changelog по
этапам 1–14) и `CHANGELOG.md` (краткая версия).

## lib/

Весь код приложения.

### lib/main.dart
Точка входа. Порядок инициализации: Isar → регистрация модулей →
настройки → поиск → `ModuleManager` → восстановление состояния из
Isar → автоустановка встроенных модулей при первом запуске.

### lib/app.dart
Корневой виджет `PersonalHubApp` — тема, именованные маршруты,
`AppSettingsScope`/`SearchScope`/`ModuleManagerScope`.

### lib/core/
Ядро приложения — не знает о конкретных модулях.

- **core/database/** — Isar: инициализация (`isar_service.dart`),
  модели ядра (`AppSettings`, `CoreTestItem`), общая модель для
  модулей (`ModuleDataRow`, `ModuleStateRecord`) и репозитории
  поверх них.
- **core/settings/** — `AppSettingsController` + `Scope`
  (тема, единственная пользовательская настройка сейчас).
- **core/search/** — `GlobalSearchService`, контракт
  `SearchProvider`, `SearchResult`, `SearchScope`.
- **core/navigation/** — таблица маршрутов (`/`, `/settings`,
  `/search`, `/modules`).
- **core/theme/** — Material 3, светлая/тёмная тема.
- **core/constants/** — строковые константы UI.
- **core/modules/** — вся система модулей:
  - контракт (`module.dart`, `module_api.dart`,
    `module_manifest.dart`, `module_permission.dart`,
    `module_state.dart`);
  - реестр (`module_registry.dart`) и точка подключения модулей
    (`module_bootstrap.dart`);
  - оркестратор жизненного цикла (`module_manager.dart`,
    `module_manager_scope.dart`, `module_install_result.dart`,
    `module_lifecycle_error.dart`) с проверками безопасности
    (формат версии, apiVersion, зависимости, циклы);
  - хранение (`module_storage.dart`,
    `module_storage_isar.dart`) и персистентность состояния
    (`module_state_store.dart`, `module_state_persistence.dart`,
    `module_state_restorer.dart`);
  - автоустановка встроенных модулей
    (`builtin_module_installer.dart`);
  - **core/modules/external/** — формат и приём внешнего модуля:
    парсинг (`manifest_parser.dart`), валидация
    (`manifest_validator.dart`), результат импорта
    (`module_package.dart`, `module_import_result.dart`), мост к
    `Module` без выполнения чужого кода
    (`external_module_adapter.dart`), временный каталог
    «доступных» модулей (`in_memory_module_catalog.dart`).

### lib/modules/
Сами модули — каждый в своей подпапке, не импортируется ядром.

- **modules/example/** — демонстрационный модуль (доказывает, что
  механизм регистрации и жизненного цикла работает).
- **modules/schedule/** — Schedule, первый полноценный
  функциональный модуль: события по дням
  (`models/schedule_event.dart`), CRUD-репозиторий поверх
  `ModuleStorage` (`schedule_repository.dart`), поиск
  (`schedule_search_provider.dart`), UI (вкладки «Сегодня»/
  «Календарь», форма создания/редактирования, список).
- **modules/README.md** — правило зависимостей и актуальный
  список модулей.

### lib/ui/
Общие экраны и виджеты ядра, не завязанные на конкретный модуль.

- **ui/screens/** — home, settings, search, modules
  (`ModulesScreen` — точка входа Module Store).
- **ui/widgets/** — `AppDrawer` (боковое меню), `EmptyState`,
  **ui/widgets/module_store/** — секции Установленные/Доступные/
  Обновления, карточка модуля, общий обработчик ошибок жизненного
  цикла.

## test/

Тесты зеркалят структуру `lib/`:
- `test/modules/example/`, `test/modules/schedule/` — чек-лист
  «Проверить» соответствующего этапа на реальных модулях.
- `test/core/modules/` — `module_state_persistence_test.dart`,
  `security_audit_test.dart`; `test/core/modules/external/` —
  `module_import_test.dart`, `module_store_test.dart`.

## docs/

Документация формата и примеры, не входящие в код приложения.

- `external-module-format.md` — формат `manifest.json` внешнего
  модуля, обязательные поля, что и где проверяется. Синхронизирован
  с `ManifestValidator`/`ModuleManager`.
- `external-module-example/` — пример пакета внешнего модуля
  (manifest.json + assets/ + data/ + README.md), иллюстрирующий
  формат — не устанавливается и не выполняется.

## Корень проекта

- `README.md` — полная история проекта, по одному разделу на
  каждый этап 1–14 (что добавлено, ключевые решения, что сознательно
  отложено).
- `CHANGELOG.md` — краткая версия того же, по 1–3 строки на этап.
- `PROJECT_MAP.md` — этот документ.
- `FINAL_ASSEMBLY_REPORT.md` — итоговый отчёт о готовности проекта
  к передаче.
- `pubspec.yaml` — зависимости (Flutter, Isar 3.1.0+1,
  path_provider, build_runner/isar_generator для кодогенерации).
