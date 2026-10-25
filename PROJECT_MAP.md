# PROJECT_MAP.md — Personal Hub

Карта проекта Personal Hub. Описано только то, что подтверждается кодом в рабочем дереве. Ветка: `master`, HEAD `a82e428` (локальный коммит, не отправлен в remote). Рабочее дерево содержит незакоммиченные изменения (см. `git status`).

## lib/

### lib/main.dart
Точка входа приложения. Последовательность инициализации: Isar → репозиторий настроек → `ModuleManager` → восстановление состояния модулей из Isar → `runApp()`. При сбое инициализации до `runApp()` показывается `StartupErrorScreen` с идентификаторами для воспроизведения.

### lib/app.dart
`PersonalHubApp` — корневой виджет приложения. Собирает scope: `AppSettingsScope`, `SearchScope`, `ModuleManagerScope`, `ModuleStatePersistenceScope`, `BackupServicesScope`.

### lib/core/

Ядро приложения. Не импортирует конкретные функциональные модули (`lib/modules/**`) за исключением трёх точек composition root, проверяемых тестом `test/ui/home_architecture_boundary_test.dart`:
- `lib/core/modules/module_bootstrap.dart`
- `lib/core/navigation/app_routes.dart`
- `lib/core/navigation/app_shell.dart`

#### core/database/
Isar: `isar_service.dart`, модели (`models/app_settings.dart`, `models/core_test_item.dart`, `models/module_data_row.dart`, `models/module_state_record.dart` и др.).

#### core/settings/
`AppSettingsController` + Scope — глобальные настройки приложения.

#### core/search/
`GlobalSearchService`, `SearchProvider`, `SearchResult`, `SearchScope`. Модули регистрируют своих провайдеров поиска через `ModuleApi` при `onEnable` и снимают при `onDisable`.

#### core/navigation/
- `app_routes.dart` — таблица маршрутов: `/` (главный экран), `/settings`, `/search`, `/modules` (Module Store), экран backup.
- `app_shell.dart` — `AppShell`: адаптивная навигация (`NavigationType.drawer`, `_TopContextBar`, `_FloatingIslandDock`, `_RailSecondaryAction`).

#### core/design/
Дизайн-система: `app_theme.dart` (`ThemeData`, цветовая схема, типографика), `app_colors.dart`, `app_spacing.dart`, `app_insets.dart`, `app_breakpoints.dart`, `app_components.dart` (карточки, пустые состояния, кнопки, SnackBar, диалоги), `design_system.dart`.

#### core/theme/
`AppTheme` и связанные тематические сущности.

#### core/constants/
UI-константы.

#### core/modules/
Система модулей (composition root, не знает о конкретных функциональных модулях):
- `module.dart` — контракт `Module`: `manifest`, `id`/`title`, `order`, `buildPage()`, хуки `onInstall`/`onEnable`/`onDisable`/`onUninstall`, `homeSections`.
- `module_api.dart` — `ModuleApi`: изолированное хранилище (`ModuleStorage`) и регистрация/снятие `SearchProvider`; реализация `_ModuleApiImpl` внутри `ModuleManager`.
- `module_manifest.dart` — `ModuleManifest` (id, name, version, apiVersion, author, description, schemaVersion, permissions, dependencies, dataMigrations).
- `module_permission.dart` — `ModulePermission` (например, `coreSearch`).
- `module_state.dart` — `ModuleState` (`installed`/`enabled`/`disabled`/`uninstalled`).
- `module_registry.dart` — `ModuleRegistry`: регистрация/замена модулей.
- `module_bootstrap.dart` — начальная загрузка встроенных модулей.
- `module_manager.dart` — `ModuleManager`: `install()`/`tryInstall()` → `ModuleInstallResult`, `enable()`, `disable()`, `uninstall()`, `update()`, `isInstalled()`, `isEnabled()`, `stateOf()`, `apiFor()`, `adoptRestoredState()`. Проверки версии, `apiVersion`, зависимостей и циклов (`_dependencyCycles`), откат при неудачной установке (`_rollbackFailedInstall`).
- `module_manager_scope.dart` — `ModuleManagerScope`: доступ к менеджеру и хранилищу из дерева виджетов.
- `module_install_result.dart`, `module_lifecycle_error.dart` — результаты и ошибки жизненного цикла.
- `module_storage.dart` — контракт `ModuleStorage` (`getString`/`setString`/`remove`/`keys`), изоляция по ключам модуля.
- `module_storage_isar.dart` — Isar-реализация `ModuleStorage` (общая коллекция, изоляция по `moduleId`).
- `module_state_store.dart` — `ModuleStateStore` (`loadAll`/`load`/`save`/`delete` снимков состояния).
- `module_state_persistence.dart` — `ModuleStatePersistence`: синхронизация состояний с Isar (`flush()`, `runAndFlush()`).
- `module_state_restorer.dart` — `ModuleStateRestorer`: восстановление состояний при запуске.
- `module_state_persistence_scope.dart` — доступ к персистентности из дерева виджетов.
- `builtin_module_installer.dart` — `ensureBuiltinModulesInstalled()`: установка/перевключение встроенных модулей. Явно отключённые пользователем модули (`state == disabled`) не активируются повторно.
- `home_section.dart` — `HomeSection` (`moduleId`, `order`, `builder`, `onRefresh?`). Контракт секции главного экрана.

#### core/modules/external/
Формат внешнего модуля `.phm`: `manifest_parser.dart`, `manifest_validator.dart`, `module_package.dart`, `module_import_result.dart`, `external_module_adapter.dart` (манифест → `Module` без выполнения чужого кода), `in_memory_module_catalog.dart`.

#### core/modules/platform/
Module Platform — изолированный слой ввода-вывода для пакетов модулей (не зависит от `ModuleManager`/`ModuleRegistry`): `package_reader.dart`, `package_writer.dart`, `package_content.dart`, `package_security_guard.dart` (`validateArchive()`), `module_sandbox.dart` (`validateModuleId()`), `module_storage_serializer.dart`, `module_importer.dart` (`importFromBytes()`), `module_exporter.dart` (`export()`), исключения (`importer_exceptions.dart`, `package_exceptions.dart`, `sandbox_exceptions.dart`, `serializer_exceptions.dart`).

#### core/backup/
Ядро резервного копирования (барrel `backup.dart`): `backup_manifest.dart`, `backup_exceptions.dart`, `backup_options.dart`, `backup_reader.dart`, `backup_writer.dart`, `atomic_file_writer.dart`, `global_backup_manager.dart` (глобальный архив `.pbk`), `module_backup.dart`, `module_backup_manifest.dart`, `module_backup_options.dart`, `module_backup_reader.dart`, `module_backup_writer.dart`.
**Ограничение:** глобальный архив `.pbk` можно создать и просмотреть, но восстановление глобального бэкапа в состояние приложения **не реализовано** (`GlobalBackupManager` не имеет операций restore). Работает только маршрут `.pmb` (бэкап одного модуля) с отказом при неудаче.

### lib/modules/
Функциональные модули (каждый изолирован: свои репозитории, модели, UI, собственное хранилище через `ModuleStorage` и `ModuleApi`):

#### modules/accounts/
- Модели: `models/account.dart` (`Account`, `AccountType`), `models/category.dart` (`Category`), `models/game_profile.dart` (`GameProfile`).
- Репозитории: `account_repository.dart` (`AccountRepository`, исключение `AccountRepositoryException`), `category_repository.dart`, `game_repository.dart` (`GameRepository`, `deleteByAccount(accountId)`).
- Поиск: `accounts_search_provider.dart` (`AccountsSearchProvider`, регистрируется при `onEnable`, снимается при `onDisable`/`onUninstall`).
- `accounts_module.dart` — `AccountsModule` (id `accounts`, манифест `schemaVersion: 1`, `homeSections`, `buildPage` → `AccountsScreen`).
- UI: `ui/accounts_screen.dart`, `ui/account_list_screen.dart`, `ui/account_form_screen.dart`, `ui/category_list_screen.dart`, `ui/category_form_screen.dart`, `ui/game_list_screen.dart`, `ui/game_form_screen.dart`, `ui/visuals`, `ui/home/accounts_home_section.dart`.

#### modules/schedule/
- Модели: `models/schedule_event.dart`, `models/category.dart`.
- Репозитории и поиск: `schedule_repository.dart`, `schedule_category_repository.dart`, `schedule_search_provider.dart`.
- `schedule_module.dart` — `ScheduleModule` (`homeSections`).
- UI: `ui/home/schedule_home_section.dart`, `ui/home/today_hero.dart`, `ui/home/timeline_strip.dart`, `ui/home/upcoming_agenda.dart`, `ui/today_tab.dart`, `ui/calendar_tab.dart`, экраны категорий и событий, визуализации.

### lib/ui/
Экраны и виджеты приложения:
- `ui/screens/` — `home_screen.dart` (собирает `homeSections` включённых модулей), `modules_screen.dart` (Module Store: «Установленные» / «Доступные» / «Обновления»), `search_screen.dart`, `settings_screen.dart`, `backup_screen.dart`, `startup_error_screen.dart`.
- `ui/backup/` — UI бэкапа без прямой зависимости от core: `backup_gateway.dart`, `core_backup_gateway.dart`, `backup_operation_controller.dart`, `backup_file_service.dart` (`file_picker`), `backup_services_scope.dart`, `backup_error_presenter.dart`.
- `ui/widgets/` — `empty_state.dart`.
- `ui/widgets/home/` — `active_modules_canvas.dart` (не принадлежит Schedule, находится в `ui/`).
- `ui/widgets/module_store/` — секции модульного store, `module_card.dart`, `module_action_runner.dart`, `update_section.dart`.
- `ui/widgets/backup/` — секции глобального бэкапа, бэкапа модуля и restore, диалог подтверждения, баннер операции.

## test/
Тесты, зеркалирующие структуру `lib/`:
- `test/core/modules/` — тесты установщика, миграций, состояния модулей, реестра, жизненного цикла.
- `test/modules/accounts/` — тесты репозитория (CRUD, каскадное удаление, обработка ошибок), жизненного цикла, поиска, UI.
- `test/modules/schedule/` — тесты секции главного экрана, миграций, категорий, событий, форм.
- `test/ui/` — регрессионные тесты макета, навигации, home-секции, модульного store, backup UI.

## docs/
- `docs/external-module-format.md` — формат внешнего модуля `.phm` (`manifest.json` + `assets/` + `data/` + `README.md`).
- `docs/external-module-example/` — пример пакета модуля.

## Документация проекта
- `README.md` — описание проекта, стек, архитектура, инструкции по запуску и сборке, известные ограничения.
- `CHANGELOG.md` — история изменений.
- `pubspec.yaml` — зависимости Flutter/Dart (`isar` 3.1.0+1, `path_provider`, `google_fonts`, `path`, `meta`, `file_picker`, `crypto`, `build_runner`/`isar_generator` в dev).
- `.gitignore`, `.gitattributes` — игнорируемые артефакты сборки (`build/`, `.dart_tool/`, Android-вывод, `.kilo/` и т.д.) и настройки EOL.

## Известные ограничения (код не реализует)
- Восстановление глобального архива `.pbk` отсутствует (только `.pmb`).
- `ModuleStorage` не обеспечивает транзакцию над несколькими ключами: частичный сбой при каскадном удалении возможен (часть игр может быть уже удалена, аккаунт не удаляется).
- Отображение на реальном устройстве не проверялось; проверялись только тесты и статический анализ.
