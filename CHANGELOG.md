# CHANGELOG — Personal Hub

Краткая версия истории по этапам. Подробности, ключевые решения и
разобранные компромиссы — в `README.md`.

**Этапы 1–5** (ядро, Isar, базовая система модулей, настройки,
глобальный поиск) — см. `README.md`, разделы «Этап 1»–«Этап 5».

**О нумерации.** Записи ниже до «Final Assembly» используют старую
шкалу «Этап N». Записи, начиная с «Stage 3.6D», используют новую
нумерацию разработки, которая применяется в комментариях кода, в
`pubspec.yaml` и в аудитах. Это две разные шкалы, не одна.

## Этап 6 — Аудит существующего ядра
Ручной аудит `core/`/`modules/` перед расширением системы модулей:
проверка зависимостей (только в одну сторону), выявление, что
`ModuleStorage` должен быть generic key-value (Isar-схемы требуют
кодогенерации, недоступной внешнему модулю).

## Этап 7 — Module API (контракты)
Введены `ModuleManifest`, `ModulePermission`, `ModuleState`,
`ModuleStorage`, `ModuleApi` как чистые контракты, без реализации.
`Module` переведён на lifecycle-хуки (`onInstall`/`onEnable`/
`onDisable`/`onUninstall`), `id`/`title` стали производными от
`manifest`.

## Этап 8 — Module Manager
`ModuleManager` — оркестратор переходов
installed/enabled/disabled/uninstalled поверх `ModuleRegistry`;
`register()` теперь проверяет уникальность id.

## Этап 9 — Module Storage (Isar)
`ModuleStorageIsar` — реализация `ModuleStorage` поверх одной общей
Isar-коллекции (`ModuleDataRow`), изоляция по `moduleId`.
`ModuleStatePersistence`/`ModuleStateRestorer` синхронизируют
состояние `ModuleManager` с Isar в обе стороны.

## Этап 10 — Built-in Modules
Первый настоящий жизненный цикл на `ExampleModule`:
`ModuleManagerScope` в дереве виджетов, автоустановка встроенных
модулей при первом запуске (`builtin_module_installer.dart`).

## Этап 11 — External Module Format
Формат `manifest.json` внешнего модуля (9 обязательных полей),
`ManifestParser`/`ManifestValidator` (пустой id, apiVersion не
число, дубликат id, циклы зависимостей), `ModulePackage` — чистые
данные без кода. Пример пакета в `docs/external-module-example/`.

## Этап 12 — Module Store
UI-экран `/modules`: разделы Установленные/Доступные/Обновления,
`ExternalModuleAdapter` (манифест → `Module` без выполнения кода),
временный `InMemoryModuleCatalog`.

## Этап 13 — Security Audit
`ModuleManager` дополнен проверками при install: формат версии
(`X.Y.Z`), совместимость `apiVersion`, невыполненные зависимости,
циклы; типизированный `ModuleInstallResult`; откат (rollback) при
неудачном install/enable/disable.

## Этап 14 — Schedule Module
Первый полноценный функциональный модуль: события по дням, вкладки
«Сегодня»/«Календарь», создание/редактирование/удаление, поиск
через `GlobalSearchService`. Хранение целиком через уже
существующий `ModuleStorage`, без отдельной Isar-коллекции.

## Final Assembly (Stage 1–7 + Packaging)
Сквозной аудит без новой функциональности: структура и дубли,
архитектурные цепочки, Isar/storage, lifecycle, security, сверка
`docs/external-module-format.md` с реализацией (формат `version`,
таблица проверок), аудит Module Store и Schedule по 10 пунктам
каждый. Найден и устранён критический дефект сборки в `lib/app.dart`
(осиротевший дублирующий блок кода после закрытия класса
`PersonalHubApp`). Документация (`README.md`,
`lib/modules/README.md`) синхронизирована с фактическим составом
модулей. Финальная упаковка: удалены пустые/промежуточные артефакты,
добавлены `PROJECT_MAP.md`, `CHANGELOG.md`,
`FINAL_ASSEMBLY_REPORT.md`.

---

## Stage 3.6D — Design System + Home Screen (2026-09-23, коммит `d453d52`)

Единственный коммит после Final Assembly: полная тема на Material 3
(`lib/core/design/`: цвета, типографика, отступы, анимации,
breakpoints, компоненты) и новый главный экран. Это последнее
состояние, зафиксированное в Git.

Ниже идут работы, которые существуют в рабочем дереве и **не
закоммичены**.

## Module Platform — Stage 1–4 (`.phm`)

Изолированный слой ввода-вывода пакетов модулей
(`lib/core/modules/platform/`), не зависящий от `ModuleManager`/
`ModuleRegistry`: чтение и запись `.phm` (`package_reader.dart`,
`package_writer.dart`, `package_content.dart`), проверка архива
(`package_security_guard.dart`), песочница модуля
(`module_sandbox.dart`, включая `validateModuleId()`), сериализация
хранилища с проверкой версии и `moduleId`
(`module_storage_serializer.dart`), импорт с промежуточной
песочницей и откатом (`module_importer.dart`) и экспорт
(`module_exporter.dart`).

## Stage 5 — Import/Export UI

Формат и приём внешнего модуля доведены до пользователя: экран
`/modules` (`lib/ui/screens/modules_screen.dart`) и секции в
`lib/ui/widgets/module_store/` («Доступные» / «Установленные» /
«Обновления»), карточка модуля, общий обработчик ошибок
жизненного цикла. Экспорт модуля в `.phm` доступен из раздела
«Установленные» с выбором режима `withoutData` / `withData`
(`ModuleExporter.export`).

## Stage 6 — Backup/Restore (6B, 6C, 6D)

Ядро — `lib/core/backup/`: манифест, security guard (проверка
архива, запрет поддиректорий и неразрешённых расширений в
`assets/`), запись/чтение, опции, атомарная запись, глобальный
`.pbk` (`GlobalBackupManager`) и модульный `.pmb` с
восстановлением и откатом (`ModuleBackupManager`).

UI не зависит от core напрямую: операции описаны интерфейсом
`lib/ui/backup/backup_gateway.dart` и реализованы адаптером
`core_backup_gateway.dart`; экран `backup_screen.dart`, состояние
операций, выбор файла через `file_picker`, диалог подтверждения и
баннер операции.

**Ограничение:** глобальный `.pbk` можно создать и просмотреть, но
его восстановление в состояние приложения не реализовано — рабочий
restore есть только для `.pmb` (одного модуля). Пробел зафиксирован
в коде как незакрытая стадия «6E».

## QUAL-03 — HomeSection composition

Главный экран собирается из секций, которые модули отдают сами.
В ядре появился контракт `HomeSection`
(`lib/core/modules/home_section.dart`: `moduleId`, `order`,
`builder`, `onRefresh`) и точка расширения `Module.homeSections`.
`HomeScreen` показывает секции только включённых модулей
(`ModuleManager.isEnabled`) и сортирует по `order`.

Schedule-виджеты главного экрана перенесены в модуль —
`lib/modules/schedule/ui/home/` (`schedule_home_section.dart`,
`today_hero.dart`, `timeline_strip.dart`, `upcoming_agenda.dart`);
общий `lib/ui/widgets/home/active_modules_canvas.dart` остался в
`ui/`. Граница composition root закреплена тестом
`test/ui/home_architecture_boundary_test.dart`: ядро не импортирует
`lib/modules/**`, кроме `module_bootstrap.dart`, `app_routes.dart`
и `app_shell.dart`.

Также в дереве: `AppShell` как адаптивная навигация
(`lib/core/navigation/app_shell.dart`) и `StartupErrorScreen` для
ошибок инициализации до `runApp()`.

## Control Full Audit

Сквозной аудит без новой функциональности. По его итогам
подтверждены архитектурные контракты, чувствительность HomeSection
и отсутствие обратных зависимостей core → модули.

## Project Cleanup (2026-10-02)

Read-only аудит репозитория, затем фактическая чистка: удалены
генерируемые артефакты (`build/`, `.dart_tool/`, `.widget_preview/`,
`.idea/`, audit-логи), пустой каталог `assets/`, локальная копия
`isar.dll` (побайтно совпадала с файлом пакета
`isar_flutter_libs`, в код не импортировалась) и machine-local
`.vscode/settings.json`. В `.gitignore` добавлены `.vscode/`,
`.kilo/worktrees/`, `.kilo/agent-manager.json`, `/isar.dll`; создан
`.gitattributes` с EOL-политикой. Исходный код и тесты не
удалялись, откатов не было, `git add`/`commit`/`push` не
выполнялись.

## Documentation sync (2026-10-02)

`README.md` получил раздел «Актуальное состояние проекта»
(Module Platform, импорт/экспорт, Backup, HomeSection, навигация,
текущий статус и roadmap); исторические разделы по этапам сохранены
и помечены как исторические. `PROJECT_MAP.md` переписан по
фактической структуре. Удалён осиротевший `AppDrawer`
(`lib/ui/widgets/app_drawer.dart`) вместе с упоминаниями в
документации — его роль выполняет `AppShell`.
`FINAL_ASSEMBLY_REPORT.md` удалён как устаревший отчёт о
готовности к моменту Final Assembly.

**Полный QA после Project Cleanup ещё не выполнялся:** ни
`flutter analyze`, ни `flutter test`, ни release-сборка после
чистки не запускались, поэтому записи о «всех пройденных тестах» и
готовности к релизу в changelog не добавляются. Stage 7 (Categories
System) не начиналась.
