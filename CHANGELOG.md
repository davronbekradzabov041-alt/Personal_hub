# CHANGELOG — Personal Hub

Краткая версия истории по этапам. Подробности, ключевые решения и
разобранные компромиссы — в `README.md`.

**Этапы 1–5** (ядро, Isar, базовая система модулей, настройки,
глобальный поиск) — см. `README.md`, разделы «Этап 1»–«Этап 5».

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
