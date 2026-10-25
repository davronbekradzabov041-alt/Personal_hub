# CHANGELOG — Personal Hub

История изменений проекта. Разделы ниже описывают историю проекта до коммита `a82e428` (HEAD, последняя закоммиченная версия). Последние изменения в рабочем дереве (не закоммичены) вынесены в первый раздел.

## Незакоммиченные изменения (рабочее дерево)

Каскадное удаление аккаунта и связанных игр (модуль `accounts`):

- `AccountRepository.delete(String id, {GameRepository? gameRepository})` сначала удаляет все игры аккаунта через `GameRepository.deleteByAccount(id)`, а затем удаляет сам аккаунт. При ошибке удаления игр исключение пробрасывается вызывающему коду в виде `AccountRepositoryException`, аккаунт не удаляется.
- Ограничение: `ModuleStorage` не обеспечивает транзакцию над несколькими ключами, поэтому при частичном сбое часть игр может быть уже удалена; атомарность не заявляется.
- `AccountListScreen._confirmDelete`: удаление обёрнуто в `try/catch` на `AccountRepositoryException`; при ошибке показывается `SnackBar` с текстом ошибки, `_reload()` вызывается только при успешном удалении, ложный успех не отображается.
- Тесты: `test/modules/accounts/account_repository_test.dart` (каскадное удаление всех игр аккаунта; сохранение игр других аккаунтов и категорий; сохранение аккаунта при ошибке удаления игр) и `test/modules/accounts/accounts_ui_test.dart` (UI показывает сообщение об ошибке и не объявляет успех).
- `builtin_module_installer.dart`: при восстановлении/установке встроенных модулей явно отключённые пользователем модули (`state == disabled`) не активируются повторно.
- `accounts_module.dart`: имя манифеста модуля исправлено на «Аккаунты».
- Документация: обновлены `README.md`, `PROJECT_MAP.md`, `CHANGELOG.md` (раздел актуального состояния, структура каталогов, архитектура, навигация, хранение, известные ограничения).

## История проекта (до коммита `a82e428`)

### Этапы 1–5
Ядро с Isar, модульная архитектура с полным жизненным циклом модулей, глобальный поиск, настройки, система модулей. Подробности — в разделе «Ручное описание этапов 1–5» более ранних версий документа; синхронизировано с `pubspec.yaml` и кодом `lib/core/modules/`.

### Этап 6 — Ядро резервного копирования (`.pbk` / `.pmb`)
`lib/core/backup/`: манифест бэкапа, security guard, запись/чтение архивов, опции, атомарная запись, глобальный архив `.pbk` (`GlobalBackupManager`) и архив одного модуля `.pmb` (`ModuleBackupManager`).
**Ограничение:** восстановление глобального `.pbk` не реализовано; работает только `.pmb`.

### Этап 7 — Module API
`ModuleManifest`, `ModulePermission`, `ModuleState`, `ModuleStorage`, `ModuleApi`; lifecycle-хуки модуля (`onInstall`/`onEnable`/`onDisable`/`onUninstall`), `id`/`title` из манифеста.

### Этап 8 — Module Manager
`ModuleManager`: состояния `installed`/`enabled`/`disabled`/`uninstalled`, `ModuleRegistry`, регистрация модулей.

### Этап 9 — Module Storage (Isar)
`ModuleStorageIsar`: изоляция по `moduleId`; `ModuleStatePersistence`/`ModuleStateRestorer` — синхронизация состояний с Isar.

### Этап 10 — Встроенные модули
`builtin_module_installer.dart`: установка и включение встроенных модулей при запуске/применении состояния.

### Этап 11 — Внешний формат модуля (`.phm`)
`manifest.json` + `assets/` + `data/` (+ `README.md`); `ManifestParser`/`ManifestValidator`; `ModulePackage`; мост `external_module_adapter.dart` (манифест → `Module` без выполнения чужого кода); пример в `docs/external-module-example/`.

### Этап 12 — Module Store
Экран `/modules` (`lib/ui/screens/modules_screen.dart`): секции «Установленные» / «Доступные» / «Обновления»; `ExternalModuleAdapter`; каталог `InMemoryModuleCatalog`.

### Этап 13 — Безопасность
Валидация при установке: формат версии, совместимость `apiVersion`, зависимости, циклы (`_dependencyCycles`), `ModuleInstallResult`, откат при неудаче (`_rollbackFailedInstall`).

### Этап 14 — Schedule Module
Модуль `schedule`: события, категории, поиск, домашняя секция главного экрана.

### Final Assembly (этапы 1–7 + упаковка)
Сборка приложения: навигация, поиск, Isar/storage, lifecycle, безопасность, формат `.phm`, Module Store и Schedule. Документация (`README.md`, `lib/modules/README.md`).

### Stage 3.6D (2026-09-23, коммит `d453d52`)
Дизайн-система (Material 3: `lib/core/design/`: цветовая схема, типографика, отступы, breakpoints, компоненты) и главный экран с секциями модулей.

### Module Platform — этапы 1–4 (`.phm`)
`lib/core/modules/platform/`: чтение/запись `.phm`, security guard, песочница модуля, сериализация хранилища, импорт/экспорт. Не зависит от `ModuleManager`/`ModuleRegistry`.

### Этап 5 — Import/Export UI
Экран `/modules` и виджеты `lib/ui/widgets/module_store/`; импорт/экспорт `.phm` через UI.

### Этап 6 — Backup/Restore (6B, 6C, 6D)
Ядро `lib/core/backup/`; UI через `lib/ui/backup/backup_gateway.dart` и адаптер `core_backup_gateway.dart`; экран `backup_screen.dart`; выбор файла через `file_picker`. Восстановление глобального `.pbk` не реализовано.

### QUAL-03 — HomeSection composition
Контракт `HomeSection` (`lib/core/modules/home_section.dart`: `moduleId`, `order`, `builder`, `onRefresh`) и `Module.homeSections`. `HomeScreen` показывает секции только включённых модулей (`ModuleManager.isEnabled`), сортировка по `order`. Граница composition root проверяется тестом `test/ui/home_architecture_boundary_test.dart` (`module_bootstrap.dart`, `app_routes.dart`, `app_shell.dart` разрешены импортировать модули; остальное ядро не знает о `lib/modules/**`).

### Control Full Audit
Полная проверка связи ядра с модулями, навигации, хранения и HomeSection.

### Project Cleanup (2026-10-02)
Удалены артефакты сборки (`build/`, `.dart_tool/`, Android-вывод), локальные настройки IDE (`.vscode/`, `.kilo/`), неиспользуемые ассеты; `.gitignore`/`.gitattributes` обновлены (EOL, игнорирование артефактов).

### Documentation sync (2026-10-02)
`README.md`, `PROJECT_MAP.md`, `CHANGELOG.md` приведены к тогдашнему состоянию кода.
