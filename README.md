# Personal Hub

Локальное офлайн-приложение для Android на Flutter (Material 3) с модульной архитектурой: личные записи, игры, категории, расписание, глобальный поиск, встроенные модули с жизненным циклом, раздел модулей (Module Store) и резервное копирование/восстановление.

## Стек технологий

- **Flutter / Dart**, SDK `>=3.3.0 <4.0.0` (`pubspec.yaml`).
- **Материал-дизайн 3** (`uses-material-design: true`).
- Зависимости: `isar`, `isar_flutter_libs` (хранение состояния и данных модулей), `path_provider`, `google_fonts`, `cupertino_icons`, `path`, `meta`, `file_picker` (выбор файлов бэкапа), `crypto` (контрольные суммы архивов).
- dev-зависимости: `flutter_test`, `flutter_lints`, `isar_generator`, `build_runner`.

## Реальные модули и возможности (на момент проверки)

Встроенные модули регистрируются в `ModuleRegistry` и активируются через `ModuleManager` (`install` → `enable` → `disable` → `uninstall`, с откатом при ошибке установки):

- **Schedule** — события, категории, домашняя секция главного экрана (сегодняшняя статистика, временная лента, ближайшие события), поиск через `SearchProvider`.
- **Accounts** — аккаунты, игры, категории, поиск, домашняя секция, UI-экраны списков и форм. При удалении аккаунта сначала удаляются все связанные с ним игры (через `GameRepository.deleteByAccount`), затем сам аккаунт; категории не удаляются и не затрагиваются игры других аккаунтов.

Главный экран (`HomeScreen`) собирает домашние секции (`Module.homeSections`) только из модулей в состоянии `enabled`, сортируя по `order`.

## Архитектура проекта

Подтверждённые детали из кода:

- **Ядро (`lib/core/`)**:
  - `modules/` — контракт модуля (`Module`), `ModuleManifest`, `ModuleApi`, жизненный цикл `ModuleManager`, реестр `ModuleRegistry`, загрузчик встроенных модулей `builtin_module_installer`, контракт секции `HomeSection`.
  - `backup/` — ядро резервного копирования: архивы `.pbk` (глобальный) и `.pmb` (один модуль), манифесты, security guard, атомарная запись, чтение архивов.
  - `design/` — дизайн-система (`AppTheme`, `AppColors`, `AppSpacing`, `AppInsets`, `AppComponents`).
  - `navigation/` — `app_routes.dart` (маршруты `/`, `/settings`, `/search`, `/modules`, backup) и `app_shell.dart` (`AppShell`: адаптивная навигация).
  - `search/` — `GlobalSearchService`, `SearchProvider`, `SearchResult`, `SearchScope`.
  - `database/` — Isar: сервис, модели (`AppSettings`, `ModuleDataRow`, `ModuleStateRecord` и др.).
  - `settings/` — `AppSettingsController` + Scope.
  - `storage/` — контракт `ModuleStorage` и его Isar-реализация (`ModuleStorageIsar`), изоляция по `moduleId`.
  - Состояние модулей: `module_state_store.dart`, `module_state_persistence.dart` (синхронизация с Isar, `flush()` / `runAndFlush()`), `module_state_restorer.dart`, `module_state_persistence_scope.dart`.
- **Модули (`lib/modules/`)**: `schedule`, `accounts`. Каждый módul изолирован: свои репозитории, модели, UI, собственное хранилище через `ModuleStorage` и `ModuleApi`.
- **UI (`lib/ui/`)**: экраны (`home_screen`, `modules_screen`, `search_screen`, `settings_screen`, `backup_screen`, `startup_error_screen`), виджеты модульного store, виджеты backup, дизайн-компоненты.

## Структура каталогов

```
lib/             — исходный код (core, modules, ui)
test/            — тесты (core, modules, ui, support)
android/         — наборка Android-приложения
docs/            — документация (в т.ч. формат внешнего модуля .phm)
build/           — артефакты сборки, в т.ч. build/personal_hub.apk
```

## Требования к окружению и инструкции

Получение зависимостей:
```
flutter pub get
```

Запуск приложения (требуется подключённый Android-устройство/эмулятор):
```
flutter run
```

Запуск всех тестов:
```
flutter test
```

Тесты отдельного модуля (пример Accounts):
```
flutter test test/modules/accounts
```

Статический анализ:
```
flutter analyze
```

Сборка release APK:
```
flutter build apk --release
```
Итоговый файл: `build/personal_hub.apk` (примерно 57,9 МБ на момент последней сборки).

## Известные ограничения и незавершённые функции

- Восстановление глобального архива `.pbk` не реализовано — можно создать и просмотреть, но не развернуть в состояние приложения. Работает только `.pmb` (бэкап одного модуля) с откатом при неудаче.
- `ModuleStorage` не предоставляет транзакцию над несколькими ключами: при каскадном удалении аккаунта и его игр, при частичном сбое часть игр может быть уже удалена, аккаунт при этом не удаляется. Атомарность не заявляется.
- Отображение на реальном устройстве не проверялось; проверялись только тесты и статический анализ.
- Файлы `PROJECT_MAP.md` и `CHANGELOG.md` относятся к более раннему состоянию репозитория (HEAD `d453d52`) и могут не совпадать с текущим кодом; в случае расхождения верьте коду в рабочем дереве.

## Проверка качества (последний запуск)

- `flutter test`: 1153 теста пройдено.
- `flutter analyze`: 287 замечаний (базовый уровень проекта, новых после последних изменений не добавлено).
- Сборка APK: успешна, файл `build/personal_hub.apk`.
