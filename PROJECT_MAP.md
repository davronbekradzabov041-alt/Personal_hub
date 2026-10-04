# PROJECT_MAP.md — Personal Hub

Карта проекта по фактическому состоянию рабочего дерева.

Состояние коммитов: HEAD `d453d52` от 2026-09-23. Module Platform,
Import/Export, Backup и HomeSection существуют в рабочем дереве и
**не закоммичены**. Подробная история по этапам — в `README.md`,
краткая — в `CHANGELOG.md`.

## lib/

Весь код приложения.

### lib/main.dart
Точка входа. Порядок инициализации: Isar → регистрация модулей →
настройки → поиск → `ModuleManager` → восстановление состояния из
Isar → автоустановка встроенных модулей при первом запуске. Любая
ошибка на этом этапе до `runApp()` показывается отдельным экраном
(`StartupErrorScreen`) с идентификаторами для воспроизведения.

### lib/app.dart
Корневой виджет `PersonalHubApp` — тема, именованные маршруты,
`AppSettingsScope`/`SearchScope`/`ModuleManagerScope`/
`ModuleStatePersistenceScope`/`BackupServicesScope`.

### lib/core/
Ядро приложения. Не импортирует конкретные функциональные модули
(см. границу composition root ниже).

- **core/database/** — Isar: инициализация (`isar_service.dart`),
  модели ядра (`models/app_settings.dart`, `models/core_test_item.dart`,
  а также общие `ModuleDataRow`, `ModuleStateRecord`), репозитории
  поверх них.
- **core/settings/** — `AppSettingsController` + `Scope`
  (тема, единственная пользовательская настройка сейчас).
- **core/search/** — `GlobalSearchService`, контракт
  `SearchProvider`, `SearchResult`, `SearchScope`.
- **core/navigation/** — `app_routes.dart` (таблица маршрутов:
  `/`, `/settings`, `/search`, `/modules`, экран backup) и
  `app_shell.dart` (`AppShell` — адаптивная навигация, в т.ч.
  `NavigationType.drawer`, `_TopContextBar`, `_FloatingIslandDock`,
  `_RailSecondaryAction`). `AppShell` — источник истины для
  текущей навигации.
- **core/design/** — дизайн-система (Stage 3.6D): полная тема
  (`app_theme.dart` — источник `ThemeData`, цвета, типографика,
  отступы, анимации, breakpoints, компоненты
  `app_components.dart`; наружу отдаётся через `design_system.dart`).
- **core/theme/** — `AppTheme`-фасад, который приложение использует
  для смены темы; сам переадресует в `core/design/app_theme.dart`.
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
    (формат версии, apiVersion, зависимости, циклы) и откатом
    неудачной установки;
  - хранение (`module_storage.dart`,
    `module_storage_isar.dart`) и персистентность состояния
    (`module_state_store.dart`, `module_state_persistence.dart`,
    `module_state_restorer.dart`,
    `module_state_persistence_scope.dart`);
  - автоустановка встроенных модулей
    (`builtin_module_installer.dart`);
  - контракт секции главного экрана (`home_section.dart` —
    `HomeSection`: `moduleId`, `order`, `builder`, `onRefresh`);
  - **core/modules/external/** — формат и приём внешнего модуля:
    парсинг (`manifest_parser.dart`), валидация
    (`manifest_validator.dart`), результат импорта
    (`module_package.dart`, `module_import_result.dart`), мост к
    `Module` без выполнения чужого кода
    (`external_module_adapter.dart`), временный каталог
    «доступных» модулей (`in_memory_module_catalog.dart`).
- **core/modules/platform/** — Module Platform, изолированный слой
  ввода-вывода пакетов `.phm` (барrel `platform.dart`; по
  документации библиотеки не зависит от `ModuleManager`/
  `ModuleRegistry`): package I/O (`package_reader.dart`,
    `package_writer.dart`, `package_content.dart`), security guard
    (`package_security_guard.dart`), песочница модуля
    (`module_sandbox.dart`), сериализация хранилища
    (`module_storage_serializer.dart`), импорт/экспорт
    (`module_importer.dart`, `module_exporter.dart`) и исключения
    (`importer_exceptions.dart`, `package_exceptions.dart`,
    `sandbox_exceptions.dart`, `serializer_exceptions.dart`).
- **core/backup/** — Backup (Stage 6B/6C/6D, barrel `backup.dart`):
  манифест (`backup_manifest.dart`), security guard
    (`backup_security_guard.dart`), запись/чтение архивов
    (`backup_writer.dart`, `backup_reader.dart`), опции
    (`backup_options.dart`), атомарная запись
    (`atomic_file_writer.dart`), глобальный бэкап `.pbk`
    (`global_backup_manager.dart`), бэкап/восстановление модуля
    `.pmb` (`module_backup.dart` и `module_backup_*.dart`),
    исключения (`backup_exceptions.dart`).
  **Глобальный restore `.pbk` не реализован** — есть только создание
  и чтение для предпросмотра; рабочий restore — только для `.pmb`.

### Граница composition root (Core → Modules)
Ядро не импортирует `lib/modules/**`. Единственные разрешённые
исключения, зафиксированные в
`test/ui/home_architecture_boundary_test.dart`:
- `lib/core/modules/module_bootstrap.dart`
- `lib/core/navigation/app_routes.dart`
- `lib/core/navigation/app_shell.dart`

### lib/modules/
Сами модули — каждый в своей подпапке, ядром не импортируются.

- **modules/example/** — демонстрационный модуль (доказывает, что
  механизм регистрации и жизненного цикла работает).
- **modules/schedule/** — Schedule, первый полноценный
  функциональный модуль: события по дням
  (`models/schedule_event.dart`), CRUD-репозиторий поверх
  `ModuleStorage` (`schedule_repository.dart`), поиск
  (`schedule_search_provider.dart`), UI экрана (вкладки
  «Сегодня»/«Календарь», форма создания/редактирования, список)
  и **собственная секция главного экрана**
  (`ui/home/schedule_home_section.dart`, `ui/home/today_hero.dart`,
  `ui/home/timeline_strip.dart`, `ui/home/upcoming_agenda.dart`).
- **modules/README.md** — правило зависимостей и список модулей.

### lib/ui/
Общие экраны и виджеты ядра, не завязанные на конкретный модуль.

- **ui/screens/** — `home_screen.dart` (композиция секций включённых
  модулей), `settings_screen.dart`, `search_screen.dart`,
  `modules_screen.dart` (Module Store), `backup_screen.dart`,
  `startup_error_screen.dart`.
- **ui/backup/** — слой доступа UI к backup, не знающий core:
  контракт операций (`backup_gateway.dart`), адаптер core-менеджеров
  (`core_backup_gateway.dart`), состояние операций
  (`backup_operation_controller.dart`), выбор файла
  (`backup_file_service.dart`), передача сервисов
  (`backup_services_scope.dart`), читаемые сообщения об ошибках
  (`backup_error_presenter.dart`).
- **ui/widgets/** — `EmptyState`; **ui/widgets/home/** —
  `active_modules_canvas.dart` (общий, не принадлежит Schedule);
  **ui/widgets/module_store/** — секции Установленные/Доступные/
  Обновления, карточка модуля, общий обработчик ошибок жизненного
  цикла; **ui/widgets/backup/** — секции глобального бэкапа, бэкапа
  модуля и restore, диалог подтверждения, баннер операции.

Отдельного виджета бокового меню в `ui/widgets/` нет: навигацию
строит `AppShell`.

## test/

Тесты зеркалят структуру `lib/`.

- `test/core/modules/` — `module_state_persistence_test.dart`,
  `security_audit_test.dart`; `test/core/modules/external/` —
  `module_import_test.dart`, `module_store_test.dart`.
- `test/core/modules/platform/` — песочница, security guard,
  сериализация, чтение/запись пакета, импорт/экспорт, регрессии
  дубликатов манифеста и диагностические тесты.
- `test/core/backup/` — манифест, запись, security-регрессии,
  конкурентное и оверрайд-состояние при restore, интеграционный
  тест, диагностика.
- `test/modules/example/`, `test/modules/schedule/` — чек-лист
  «Проверить» на реальных модулях, включая
  `schedule_home_section_test.dart` и
  `event_form_delete_dialog_test.dart`.
- `test/ui/` — контракт и границы Home (`home_section_contract_test.dart`,
  `home_architecture_boundary_test.dart`), навигация
  (`navigation_regression_test.dart`), Module Store
  (`module_store_persistence_test.dart`,
  `module_store_failed_install_test.dart`,
  `module_import_persistence_test.dart`), backup UI
  (`backup_screen_test.dart`, `backup_restore_error_reporting_test.dart`,
  `restore_section_foreign_module_test.dart`,
  `backup_ui_backend_smoke_test.dart`).

## docs/

Документация формата и примеры, не входящие в код приложения.

- `external-module-format.md` — формат `manifest.json` внешнего
  модуля, обязательные поля, что и где проверяется. Синхронизирован
  с `ManifestValidator`/`ModuleManager`.
- `external-module-example/` — пример пакета внешнего модуля
  (manifest.json + assets/ + data/ + README.md), иллюстрирующий
  формат — не устанавливается и не выполняется.

## Корень проекта

- `README.md` — раздел «Актуальное состояние проекта» плюс
  историческая хроника по этапам 1–14.
- `CHANGELOG.md` — краткая история по этапам.
- `PROJECT_MAP.md` — этот документ.
- `pubspec.yaml` — зависимости (Flutter, Isar 3.1.0+1,
  path_provider, google_fonts, path, meta, file_picker, crypto,
  build_runner/isar_generator для кодогенерации).
- `.gitignore`, `.gitattributes` — правила игнорирования и EOL-политика.
