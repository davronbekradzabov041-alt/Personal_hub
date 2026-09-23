# Personal Hub — Этап 1: Ядро

Flutter + Material 3. Локальное офлайн-приложение,
модульная архитектура.

## Структура проекта

```
lib/
├── main.dart                          # Точка входа. Только запускает PersonalHubApp.
├── app.dart                           # Корневой MaterialApp: тема + маршруты.
│
├── core/                              # Ядро — не знает о модулях
│   ├── theme/
│   │   └── app_theme.dart             # Material 3 темы: light/dark
│   ├── navigation/
│   │   └── app_routes.dart            # Таблица именованных маршрутов
│   └── constants/
│       └── app_strings.dart           # Текстовые константы (заготовка под i18n)
│
├── ui/                                # Общие переиспользуемые экраны/виджеты ядра
│   ├── screens/
│   │   ├── home_screen.dart           # Главный экран (пока пустой список модулей)
│   │   └── settings_placeholder_screen.dart
│   └── widgets/
│       └── empty_state.dart           # Переиспользуемая "заглушка" для пустых разделов
│
└── modules/                           # Пусто. Система модулей — Этап 3.
    └── README.md
```

### core/database/ (добавлено на Этапе 2)

```
core/database/
├── isar_service.dart                  # Открывает и хранит единственный экземпляр Isar
├── models/
│   └── core_test_item.dart            # Тестовая коллекция ядра (не модуль)
└── repositories/
    ├── base_repository.dart           # Общий CRUD-контракт для всех репозиториев
    └── core_test_item_repository.dart # Реализация контракта поверх Isar
```

**Важно про CoreTestItem**: это не модуль и не относится к
Расписанию/Финансам/и т.д. Это временная коллекция для
проверки CRUD и данных для глобального поиска (Этап 5). Её
можно будет удалить, когда появятся настоящие модули.

**Нужно сделать локально перед первым запуском:**
```
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```
Это сгенерирует `core_test_item.g.dart` и `app_settings.g.dart`
(схемы Isar). Без этого шага проект не скомпилируется —
кодогенерацию нельзя выполнить в этой среде без Flutter/Dart
SDK и доступа к pub.dev.

### core/modules/ и modules/ (добавлено на Этапе 3)

```
core/modules/
├── module.dart              # Интерфейс Module — контракт для любого модуля
├── module_registry.dart     # Реестр: register()/registerAll()/modules
└── module_bootstrap.dart    # Единственное место, где модули подключаются

modules/
└── example/
    └── example_module.dart  # Демо-модуль — доказывает, что механизм работает

ui/widgets/
└── app_drawer.dart          # Боковое меню: Главная, Настройки + список модулей
```

**Как это работает**: `main.dart` вызывает `registerCoreModules()`
до `runApp()`. `AppDrawer` читает `ModuleRegistry.modules` и
строит пункты меню динамически — ни ядро, ни меню не содержат
названий конкретных модулей. Чтобы подключить/отключить модуль,
достаточно добавить/убрать одну строку в `module_bootstrap.dart`.

`ExampleModule` — не настоящий модуль, а доказательство того,
что систему можно расширять независимо от ядра. Его можно
удалить в любой момент без последствий для `core/`.

### core/settings/ (добавлено на Этапе 4)

```
core/settings/
├── app_settings_controller.dart  # ChangeNotifier: themeMode + language, load()/set*()
└── app_settings_scope.dart       # InheritedNotifier — доступ к контроллеру без прокидывания

core/database/models/app_settings.dart        # Isar-коллекция, одна запись (id фиксирован)
core/database/repositories/app_settings_repository.dart  # load()/save() этой записи

ui/screens/settings_screen.dart   # Заменил settings_placeholder_screen.dart — теперь реальный экран
```

**Как это работает**: `main.dart` создаёт `AppSettingsController`,
вызывает `load()` (читает сохранённую тему/язык из Isar) —
всё ещё до `runApp()`, чтобы не мигать темой по умолчанию.
`PersonalHubApp` оборачивает дерево в `AppSettingsScope` и
слушает контроллер через `ListenableBuilder`, поэтому смена
темы на экране настроек применяется сразу, без перезапуска.
Каждый `set...()` в контроллере сам сохраняет изменение в Isar.

Язык пока только сохраняется как предпочтение — переключение
самих текстов интерфейса не входило в Этап 4 (потребует
отдельной системы локализации строк).

**Изменение архитектуры**: `settings_placeholder_screen.dart`
удалён и заменён на `settings_screen.dart` — это ожидаемая
замена заглушки на реальный экран, а не отход от структуры
Этапа 1 (маршрут `AppRoutes.settings` и место в `AppDrawer`
не изменились).

### core/search/ (добавлено на Этапе 5)

```
core/search/
├── search_result.dart                       # Общая модель результата поиска
├── search_provider.dart                      # Контракт источника данных для поиска
├── global_search_service.dart                # Опрашивает все зарегистрированные провайдеры
├── search_scope.dart                         # Доступ к сервису поиска через context
└── providers/
    └── core_test_item_search_provider.dart    # Адаптер CoreTestItem → SearchResult

ui/screens/search_screen.dart   # Поле ввода + список результатов
```

**Как это работает**: `main.dart` создаёт `GlobalSearchService`
и регистрирует в нём один источник —
`CoreTestItemSearchProvider`, который использует уже готовый
`searchByTitle()` из Этапа 2. При первом запуске, если
тестовая коллекция пуста, добавляются 3 демонстрационные
записи (`_seedDemoDataIfEmpty` в `main.dart`), чтобы было что
искать. Иконка поиска в AppBar главного экрана ведёт на
`SearchScreen`.

Архитектура специально не завязана на `CoreTestItem`:
`SearchProvider` — общий контракт, поэтому когда появятся
настоящие модули, каждый добавит свой провайдер одной строкой
в `main.dart`, и `search_screen.dart` не изменится.

## Почему так (состояние на Этап 1 — исторический раздел, см. "Статус" ниже для актуального списка модулей)

- **core/** не импортирует ничего из `modules/` — зависимость
  всегда в одну сторону, чтобы модули можно было подключать
  и отключать независимо.
- **ui/** содержит только общие, не завязанные на конкретный
  модуль экраны и виджеты.
- Isar (база данных) сознательно ещё не подключена в
  `pubspec.yaml` — это Этап 2.
- На Этапе 1 модули (Расписание, Финансы, Аккаунты, Файлы, AI,
  Бэкапы) ещё не создавались — только заготовка
  `modules/README.md`, объясняющая правило зависимостей на
  будущее.

## Статус

✅ Этап 1: структура, тема, навигация, главный экран — готово
✅ Этап 2: Isar (модели, инициализация, Repository) — готово
✅ Этап 3: система модулей + боковое меню — готово
✅ Этап 4: настройки приложения — готово
✅ Этап 5: глобальный поиск — готово

### Расширенная система модулей (Этапы 6–14)

✅ Этап 6: аудит существующего ядра
✅ Этап 7: Module API — контракты
✅ Этап 8: Module Manager
✅ Этап 9: хранение модулей (ModuleStorage поверх Isar)
✅ Этап 10: встроенные модули (реальный жизненный цикл у ExampleModule)
✅ Этап 11: формат и установка внешнего модуля
✅ Этап 12: Module Store (UI)
✅ Этап 13: аудит безопасности
✅ Этап 14: Schedule — первый полноценный функциональный модуль

### Этап 7 — Module API (только контракты)

```
core/modules/
├── module.dart              # ИЗМЕНЁН: manifest, lifecycle-хуки, id/title из manifest
├── module_registry.dart     # ИЗМЕНЁН: + get()/contains()/unregister()
├── module_manifest.dart     # НОВЫЙ: ModuleManifest, ModuleDependency, kCoreModuleApiVersion
├── module_permission.dart   # НОВЫЙ: ModulePermission (value-тип, не enum)
├── module_state.dart        # НОВЫЙ: ModuleState (installed/enabled/disabled/uninstalled)
├── module_storage.dart      # НОВЫЙ: ModuleStorage — контракт, без реализации
└── module_api.dart          # НОВЫЙ: ModuleApi — точка входа модуля в ядро
```

**Ключевые решения:**
- `id`/`title` в `Module` теперь производные от `manifest` (не дублируются) — один источник правды.
- `ExampleModule` переведён с `implements Module` на `extends Module`, иначе пришлось бы вручную реализовывать все lifecycle-хуки вместо использования пустых тел по умолчанию.
- `ModulePermission` — не enum, а value-объект над строкой: внешний модуль (Этап 11) может запросить разрешение, которого ядро ещё не знает; enum потребовал бы пересборки ядра под каждое новое разрешение.
- `ModuleState` — отдельный тип, не поле в `Module`: состояние отслеживает будущий `ModuleManager`, а не сам модуль (иначе — два источника правды).
- `ModuleStorage` — только строковый key-value, без типизированных моделей: Isar регистрирует схемы на этапе компиляции, а у внешнего модуля своего Dart-кода не будет вовсе (см. аудит Этапа 6).
- `GlobalSearchService` дополнен `unregisterProvider()` — нужен `ModuleApi.unregisterSearchProvider`, чтобы отключённый/удалённый модуль не оставался в результатах поиска.
- `buildPage(BuildContext)` не тронут — сигнатура не получила `ModuleApi`, чтобы не тянуть за собой реализацию `ModuleManager` раньше времени.

**Сознательно не реализовано:** `ModuleManager` (Этап 8), Isar-реализация `ModuleStorage` (Этап 9), установка/удаление внешних модулей (Этап 11), UI Module Store (Этап 12), проверки apiVersion/dependencies/permissions в рантайме (контракты определяют форму, не логику).

**Открытый вопрос для Этапа 11:** `Module` описывает только встроенные (скомпилированные) модули — `buildPage`/lifecycle-хуки это Dart-код. Внешний модуль без своего кода не сможет реализовать `Module` напрямую; ему понадобится отдельное декларативное представление поверх того же `ModuleManifest`. Решение сознательно отложено.

**Проверки:** Flutter/Dart SDK в этой среде отсутствует — `dart analyze` и `flutter test` не запускались (не имитировались). Локальный аудит зависимостей между новыми файлами сделан вручную (граф импортов ниже) — циклов нет, `core/search` → `core/modules` зависимости не появилось (зависимость только в одну сторону: `core/modules` → `core/search`).

```
module.dart          → module_api.dart, module_manifest.dart
module_api.dart       → core/search/search_provider.dart, module_storage.dart
module_manifest.dart  → module_permission.dart
module_permission.dart → (нет)
module_storage.dart    → (нет)
module_state.dart      → (нет; пока не используется — тип для Этапа 8)
module_registry.dart   → module.dart
```

Команды для локального запуска:
```
dart analyze
flutter test
```

### Этап 8 — Module Manager

```
core/modules/
├── module_manager.dart        # НОВЫЙ: оркестратор жизненного цикла
└── module_lifecycle_error.dart # НОВЫЙ: единая ошибка недопустимых действий

core/modules/module_registry.dart  # ИЗМЕНЁН: register() теперь реально проверяет уникальность id
```

**Что умеет `ModuleManager`:** `install(id)`, `enable(id)`, `disable(id)`,
`uninstall(id)`, `update(Module newVersion)` — минимальная версия
(подмена реализации в реестре той же версии-строки, без semver,
без миграции данных, без `onUpdate`-хука — их пока нет в контрактах
Этапа 7). Состояние (`ModuleState`) хранится в самом `ModuleManager`
(`Map<String, ModuleState>`), не в `Module`.

**Разрешённые переходы:**
```
(нет)      → installed   [install]
installed  → enabled      [enable]
disabled   → enabled      [enable]
enabled    → disabled     [disable]
installed  → uninstalled  [uninstall]
disabled   → uninstalled  [uninstall]
uninstalled → installed   [install]  (переустановка)
```
`enabled → uninstalled` напрямую запрещён — сначала `disable()`,
чтобы модуль гарантированно отписался от поиска и т.п.

**Проверки, подготовленные на этом этапе** (по списку из задачи):
- уникальность `moduleId` — в `ModuleRegistry.register()`: молча
  игнорирует повторную регистрацию ТОГО ЖЕ объекта, но бросает
  `ModuleLifecycleError`, если id уже занят ДРУГИМ объектом;
- невозможность enable неустановленного модуля — `enable()` требует
  `installed`/`disabled`;
- невозможность повторной установки — `install()` требует отсутствия
  состояния или `uninstalled`;
- корректная последовательность lifecycle — таблица переходов выше,
  каждый метод проверяет свой набор допустимых исходных состояний.

**Архитектурное решение по ходу работы:** первая версия проверки
уникальности id была ошибочной — я сравнивал объект, полученный из
`ModuleRegistry.get(id)`, сам с собой (тавтология, `identical()`
всегда true). Перенёс проверку туда, где она имеет смысл: в
`ModuleRegistry.register()`, единственное место, где могут
одновременно существовать два РАЗНЫХ объекта с одинаковым id.

**ModuleApi для хуков:** `ModuleManager` передаёт в `onInstall`/
`onEnable`/`onDisable`/`onUninstall` реализацию `ModuleApi`
(`_ModuleApiImpl`, приватный класс) с временным **in-memory**
хранилищем (`_InMemoryModuleStorage`) — не Isar (это Этап 9, явно
запрещённый сейчас). Данные не переживают перезапуск приложения;
переиспользуются между вызовами хуков одного модуля, пока его не
удалят. `registerSearchProvider()` проверяет наличие разрешения
`ModulePermission.coreSearch` в манифесте модуля и бросает
`ModuleLifecycleError`, если его нет — разрешения из Этапа 7
здесь наконец на что-то влияют.

**Сознательно НЕ реализовано:** внешний формат модулей, скачивание/
импорт файлов, Module Store UI, реальные функциональные модули,
Isar-бэкенд `ModuleStorage`, проверка `apiVersion`/зависимостей при
install (контракты для этого есть — `kCoreModuleApiVersion`,
`ModuleDependency` — но сама проверка не входила в список Этапа 8
и добавится, когда появится первый модуль, которому это реально
нужно).

**Интеграция:** `ModuleManager` НЕ подключён в `main.dart`/`app.dart`.
Состояние живёт только в памяти — подключить его сейчас означало бы,
что после каждого перезапуска все модули (включая `ExampleModule`)
считались бы неустановленными, а поведение приложения не изменилось
бы, потому что `AppDrawer` по-прежнему читает `ModuleRegistry.modules`
напрямую, без учёта состояния. Осмысленная интеграция — после Этапа 9
(персистентность состояния) и, вероятно, правки `AppDrawer`
(Этап 10/12), а не раньше.

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались и не имитировались. Граф импортов новых файлов
проверен вручную — циклов нет; `ModuleRegistry` по-прежнему не знает
о `ModuleManager` (зависимость только в одну сторону).

Команды для локального запуска:
```
dart analyze
flutter test
```

### Этап 9 — Module Storage (Isar)

```
core/database/models/
├── module_state_record.dart   # НОВЫЙ: Isar-модель — состояние ОДНОГО модуля
└── module_data_row.dart        # НОВЫЙ: Isar-модель — generic key-value, общая на все модули

core/database/repositories/
└── module_state_repository.dart # НОВЫЙ: Isar-репозиторий, implements ModuleStateStore

core/modules/
├── module_state_store.dart     # НОВЫЙ: контракт ModuleStateStore + ModuleStateSnapshot (без Isar-типов)
├── module_storage_isar.dart    # НОВЫЙ: ModuleStorageIsar — Isar-реализация контракта ModuleStorage (Этап 7)
├── module_state_persistence.dart # НОВЫЙ: слушает ModuleManager, сохраняет/удаляет состояние
└── module_state_restorer.dart  # НОВЫЙ: восстанавливает состояние при старте через публичный API ModuleManager

test/core/modules/
└── module_state_persistence_test.dart # НОВЫЙ: install/enable/disable/uninstall/restart — на фейковом хранилище
```

**Изменены:** `core/database/isar_service.dart` (две новые схемы),
`lib/main.dart` (создание ModuleManager + репозитория + подписка +
восстановление до `runApp()`), `lib/app.dart` (добавлено поле
`moduleManager` — чтобы объект не собрал GC сразу после `runApp()`;
UI его пока не использует). **`core/modules/module_manager.dart` НЕ
менялся** — ни строки, как и было явно запрещено.

**Новые Isar-схемы:**
- `ModuleStateRecordSchema` — одна строка на `moduleId`: `state`,
  `installedVersion`, `enabled`, `installedAt`, `updatedAt`. Апсерт
  сделан вручную (найти по `moduleId` → переиспользовать id → `put()`),
  а не через `@Index(..., replace: true)` — этот синтаксис Isar не
  проверен компилятором в этой среде, ручной апсерт использует только
  уже опробованные в проекте базовые операции.
- `ModuleDataRowSchema` — общая generic key-value коллекция
  (`moduleId`, `key`, `jsonValue`) на данные ВСЕХ модулей. Отдельных
  типизированных коллекций на модуль нет и не будет — прямое следствие
  аудита Этапа 6.

**Как ModuleManager взаимодействует с ModuleStorage — важная оговорка.**
`ModuleManager` не менялся, поэтому его приватный `_apiFor()` (Этап 8)
по-прежнему создаёт `ModuleApi` с временным **in-memory**
`_InMemoryModuleStorage` — тем же самым, что и на Этапе 8. Реальный
`ModuleStorageIsar`, построенный на этом этапе, **пока не является**
тем хранилищем, которое модуль получает внутри `onInstall`/`onEnable`/
и т.д. Он используется в другом месте — `ModuleStatePersistence`
вызывает его (через `storageFactory`) только чтобы **стереть** данные
модуля при `uninstall` (`keys()` + `remove()` по контракту `ModuleStorage`
из Этапа 7). Подключить `ModuleStorageIsar` как основное хранилище
хуков модуля можно только отредактировав `_apiFor()` в
`module_manager.dart` — а это прямо запрещено условиями этого этапа.
Это осознанный, явный компромисс, а не недосмотр: следующий шаг —
либо явно разрешить точечную правку `_apiFor()`, либо иначе передавать
фабрику хранилища в `ModuleManager` (например, через конструктор,
что тоже потребует правки файла).

**Персистентность (пункты 3–5 задания):**
- **Сохранение после install/enable/disable/uninstall/update** —
  `ModuleStatePersistence` подписывается на `ModuleManager` через уже
  существующий `notifyListeners()` (Этап 8), файл `module_manager.dart`
  не тронут ни строкой. При `uninstall` строка `ModuleStateRecord`
  удаляется целиком (не помечается uninstalled) и данные модуля
  стираются — ровно как требовало задание.
- **Загрузка при запуске / восстановление после перезапуска** —
  `ModuleStateRestorer` читает сохранённые снимки и проводит
  `ModuleManager` через его же публичный API (`install`/`enable`/
  `disable`), а не выставляет состояние напрямую — такого метода у
  `ModuleManager` нет и не должно быть, иначе на холодном старте не
  вызвались бы lifecycle-хуки, которые заново регистрируют модуль в
  `GlobalSearchService` (он тоже создаётся заново при каждом запуске).
  Плата за это: восстановление `disabled` проходит `install → enable →
  disable`, то есть `onEnable` вызывается и тут же гасится `onDisable`
  — по результату корректно, но лишний проход хуков не бесплатен.
  Убрать это можно только правкой `ModuleManager`, что запрещено здесь.

**Тесты (`test/core/modules/module_state_persistence_test.dart`):**
покрывают буквально каждый пункт из «Проверить»: install → сохраняется,
enable → сохраняется, disable → сохраняется, uninstall → запись и
данные удаляются, restart → состояние (включая `disabled`)
восстанавливается. Тесты используют фейковые `ModuleStateStore` и
`ModuleStorage` (in-memory), а не настоящий Isar — в этой среде нет
возможности прогнать `build_runner`, чтобы получить `*.g.dart` для
`ModuleStateRecord`/`ModuleDataRow`, без которых Isar-путь вообще не
скомпилируется. Сама Isar-реализация (`ModuleStateRepository`,
`ModuleStorageIsar`) собрана по тому же образцу, что уже принятый и
рабочий код Этапа 2 (`CoreTestItemRepository`), но не прогнана.

**Результат `dart analyze`:** не запускался — Flutter/Dart SDK в этой
среде отсутствует (проверено: `flutter`/`dart` не найдены). Не имитирую.

**Результат `flutter test`:** не запускался по той же причине. Тесты
написаны и должны пройти при локальном запуске — команды ниже.

Команды для локального запуска:
```
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
dart analyze
flutter test
```

### Этап 10 — Built-in Modules

```
core/modules/
├── module_manager_scope.dart       # НОВЫЙ: InheritedNotifier — доступ к ModuleManager из UI
└── builtin_module_installer.dart   # НОВЫЙ: авто-install+enable модуля при первом запуске

lib/modules/example/example_module.dart # ПЕРЕПИСАН: настоящая реализация (было — пустая заглушка)

test/modules/example/example_module_test.dart # НОВЫЙ: весь чек-лист «Проверить» на реальном ExampleModule
```

**Изменены:**
- `core/modules/module_manager.dart` — `_apiFor()` теперь отдаёт
  настоящий `ModuleStorageIsar` вместо временного in-memory (Этап 8
  просил не трогать этот файл — тот запрет был только на Этапе 8–9,
  здесь снят явно); добавлен публичный `apiFor(moduleId)`.
- `lib/app.dart` — добавлен `ModuleManagerScope` в дерево виджетов
  (поле `moduleManager` наконец используется, не только «для GC»).
- `lib/main.dart` — после восстановления состояния (Этап 9) вызывается
  `ensureBuiltinModulesInstalled`.
- `core/search/global_search_service.dart` — добавлен `providerCount`
  (только для тестов/отладки — проверить, что регистрация и отписка
  реально меняют число источников).

**Схема регистрации модулей:**
```
module_bootstrap.dart (main.dart, при старте)
        │  ModuleRegistry.registerAll([ExampleModule()])
        ▼
ModuleRegistry                      ← «чей код известен приложению»
        │  ModuleRegistry.modules (все зарегистрированные)
        ▼
ensureBuiltinModulesInstalled(manager, store)
        │  для каждого модуля: store.load(id) == null?
        │    да  → install(id) + enable(id)  [первый запуск]
        │    нет → пропустить                [уже видели раньше]
        ▼
ModuleStateRestorer.restore()       ← на КАЖДЫЙ запуск, ДО автоустановки
        │  для каждой сохранённой записи: install/enable/disable
        │  через публичный API — восстанавливает то, что уже было
        ▼
ModuleManager (состояние) ⇄ ModuleStatePersistence ⇄ Isar (Этап 9)
```
Порядок в `main.dart`: restore() сначала (восстановить то, что уже
было), `ensureBuiltinModulesInstalled` — потом (установить то, чего
ещё не было). Для уже знакомого модуля второй шаг — no-op.

**Жизненный цикл Example Module:**
1. Регистрация в `ModuleRegistry` — при каждом старте, через
   `module_bootstrap.dart` (не изменился).
2. Первый запуск: `ensureBuiltinModulesInstalled` не находит записи в
   хранилище → `install('example')` → `enable('example')` →
   `onEnable` регистрирует `_ExampleSearchProvider` в
   `GlobalSearchService` (требует `ModulePermission.coreSearch` в
   манифесте — иначе `ModuleApi.registerSearchProvider` бросил бы
   `ModuleLifecycleError`).
3. Пользователь открывает страницу модуля (через `AppDrawer`, не
   менялся) — страница сама показывает текущее состояние
   (`ModuleManagerScope.of(context).stateOf('example')`) и кнопки
   Установить/Включить/Выключить/Удалить, актуальные для этого
   состояния. Собственные настройки (заметка) читаются/пишутся через
   `ModuleApi.storage` (Isar, Этап 9).
4. `disable('example')` → `onDisable` отписывает провайдер от поиска.
   `uninstall('example')` (только из installed/disabled) → защитный
   дубль отписки в `onUninstall` → `ModuleStatePersistence` удаляет
   Isar-запись и данные модуля.
5. Повторный `install('example')` после uninstall работает — «удаление»
   было про состояние и данные, не про код (он всё ещё скомпилирован
   в приложение).
6. Перезапуск приложения (в тестах — новый `ModuleManager` поверх
   того же хранилища): `ModuleStateRestorer` проводит модуль через
   `install`/`enable`/`disable` заново, чтобы `onEnable` повторно
   зарегистрировал `SearchProvider` в свежем `GlobalSearchService`.

**Переиспользовано из Этапов 7–9, без изменений:** `Module`,
`ModuleManifest`, `ModulePermission`, `ModuleApi`, `ModuleRegistry`
(кроме уже принятого на Этапе 8 расширения), `ModuleLifecycleError`,
весь механизм `install/enable/disable/uninstall` из `ModuleManager`
(поведение и проверки переходов — те же, менялась только реализация
хранилища внутри), `ModuleStatePersistence`, `ModuleStateRestorer`,
`ModuleStateStore`, `ModuleStorageIsar`, `AppDrawer` (совсем не тронут
— по-прежнему просто перечисляет `ModuleRegistry.modules`).

**Сознательно оставлено на Этап 11 (и далее):**
- Формат внешнего модуля (`manifest.json`, `assets/`, `data/`) —
  не создавался, как и запрещено.
- Различение «встроенный / внешний» модуль в
  `ensureBuiltinModulesInstalled` — сейчас там ВСЁ, что есть в
  `ModuleRegistry`, потому что других источников регистрации ещё нет;
  когда появится импорт внешних модулей, эту функцию (или её вызов)
  нужно будет сузить явно.
- Module Store UI (список «Установленные / Доступные / Обновления») —
  вместо него `AppDrawer` + собственная страница модуля, как и
  требовало условие «Запрещено» этого этапа.
- `AppDrawer` по-прежнему не фильтрует список по состоянию (показывает
  модуль, даже если он `disabled`/`uninstalled`) — сознательно не
  трогался; сама страница модуля корректно отражает состояние и
  предлагает нужные действия, так что видимого разрыва в поведении
  нет, но полноценная фильтрация списка — тоже, вероятно, задача
  Module Store UI (Этап 12).

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались. Тесты (`example_module_test.dart`) покрывают
все 6 пунктов «Проверить» на реальном классе `ExampleModule` с
фейковыми `ModuleStateStore`/`ModuleStorage` — реальный Isar-путь
(`ModuleStorageIsar`, `ModuleStateRepository`) по-прежнему не
скомпилирован и не прогнан локально.

Команды для локального запуска:
```
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
dart analyze
flutter test
```

### Этап 11 — External Module Format

```
docs/external-module-format.md              # НОВЫЙ: спецификация формата
docs/external-module-example/                # НОВЫЙ: иллюстративный пример пакета
├── manifest.json
├── README.md
├── assets/README.md
└── data/README.md

lib/core/modules/external/
├── manifest_parser.dart      # НОВЫЙ: ManifestParser + ManifestParseException
├── manifest_validator.dart   # НОВЫЙ: ManifestValidator (+ findDependencyCycles)
├── module_package.dart       # НОВЫЙ: ModulePackage
└── module_import_result.dart # НОВЫЙ: ModuleImportResult

test/core/modules/external/module_import_test.dart # НОВЫЙ: все правила валидации
```

**Изменённых файлов на этом этапе нет** — весь код нового формата
живёт в отдельном `core/modules/external/`, ничего из Этапов 1–10 не
трогалось. `ModuleManifest`/`kCoreModuleApiVersion` (Этап 7)
переиспользованы как есть, не продублированы.

**Структура формата** — `module/manifest.json` (обязателен) +
`assets/` + `data/` (могут быть пустыми) + `README.md`
(необязателен). Подробности и таблица обязательных полей —
`docs/external-module-format.md`.

**Пример manifest.json:**
```json
{
  "id": "notes-lite",
  "name": "Notes Lite",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Иллюстративный пример внешнего модуля (заметки).",
  "permissions": ["core.search"],
  "dependencies": [],
  "icon": "assets/icon.png"
}
```
(Полный файл — `docs/external-module-example/manifest.json`. Пример
намеренно нейтральный — гипотетические "заметки", не Schedule/
Финансы/Аккаунты.)

**Все правила валидации и где они реализованы:**
| Правило | Класс |
|---|---|
| Повреждённый JSON | `ManifestParser` |
| Не JSON-объект верхнего уровня | `ManifestParser` |
| Отсутствующие поля (любое из 9 обязательных) | `ManifestParser` |
| Пустой `id` | `ManifestParser` (через `ModuleManifest.fromJson`) + повторно `ManifestValidator` (defense-in-depth на границе класса) |
| `apiVersion` не целое число | `ManifestParser` (через `ModuleManifest.fromJson`) |
| Неподдерживаемая версия Module API (число вне `1..kCoreModuleApiVersion`) | `ManifestValidator` |
| Дублирующийся `moduleId` | `ManifestValidator` (сверяет с переданным `existingModuleIds`) |
| Циклические зависимости | `ManifestValidator.findDependencyCycles` — DFS со стеком рекурсии по графу `Map<moduleId, List<зависимостей>>` |

**Какие ошибки возвращает система:**
- `ManifestParser.parse()` бросает `ManifestParseException` (одна
  причина за раз — если JSON сломан или неполон, дальше разбирать
  нечего).
- `ManifestValidator.validate()` возвращает `List<String>` — ВСЕ
  найденные нарушения сразу, не только первое (полезнее для
  недоверенного внешнего пакета — видно все проблемы за одну попытку).
- `ModuleImportResult.from()` объединяет оба источника в одно
  значение (`isSuccess`/`package`/`errors`), ничего не бросает наружу
  — для внешнего пакета отказ валидации ожидаемый исход, а не авария.

**Почему именно 4 запрошенных класса, без пятого оркестратора:**
связка parser→validator→package понадобилась, но она не имеет
собственного состояния сверх последовательного вызова — реализована
статическим фабричным методом `ModuleImportResult.from(...)`, а не
отдельным классом, чтобы не плодить абстракции ради количества файлов.

**Циклические зависимости — "подготовить архитектуру" буквально:**
`findDependencyCycles` работает на синтетических графах (протестировано:
простой цикл, самоссылка, граф без циклов, пустой граф) и не привязана
к `ModuleManifest`. Реального применения в приложении пока нет — граф
неоткуда взять: единственный установленный модуль (`ExampleModule`) не
зависит ни от кого, а импорт нескольких внешних модулей разом не входит
в этот этап.

**Что остаётся на Этап 12 (и далее):** реальное чтение `manifest.json`
с диска/из ZIP, выбор файла пользователем, установка `ModulePackage` в
`ModuleRegistry`/`ModuleManager` (сведение внешнего пакета к чему-то,
что можно `install()` — открытый вопрос ещё с Этапа 7: `Module`
описывает только модули со своим Dart-кодом, а у внешнего пакета кода
нет), сопоставление `ModulePackage.assetPaths`/`dataPaths` с реальными
файлами, Module Store UI (списки «Установленные/Доступные/Обновления»,
карточки, кнопки), подключение `findDependencyCycles` к реальному графу
нескольких модулей.

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались. Весь код Этапа 11 работает только со строками и
`dart:convert` (`jsonDecode`) — ни `dart:io`, ни Isar, ни Flutter-виджеты
не задействованы, так что теоретически это самый "лёгкий" для проверки
код в проекте, но формально он всё ещё не прогнан локально.

Команды для локального запуска:
```
dart analyze
flutter test
```

### Этап 12 — Module Store

```
lib/core/modules/external/
├── external_module_adapter.dart   # НОВЫЙ: мост ModulePackage → Module (общая info-страница)
└── in_memory_module_catalog.dart  # НОВЫЙ: ModuleCatalogEntry + InMemoryModuleCatalog

lib/ui/widgets/module_store/
├── module_card.dart          # НОВЫЙ: переиспользуемая карточка модуля
├── module_action_runner.dart # НОВЫЙ: общий обработчик ModuleLifecycleError → SnackBar
├── installed_section.dart    # НОВЫЙ: раздел «Установленные»
├── available_section.dart    # НОВЫЙ: раздел «Доступные»
└── update_section.dart       # НОВЫЙ: раздел «Обновления»

lib/ui/screens/modules_screen.dart # НОВЫЙ: ModulesScreen — собирает три секции

test/core/modules/external/module_store_test.dart # НОВЫЙ: весь чек-лист «Проверить»
```

**Изменены:** `lib/core/navigation/app_routes.dart` (маршрут `/modules`),
`lib/ui/widgets/app_drawer.dart` (пункт меню «Модули» — первое
изменение этого файла с Этапа 3, ранее сознательно откладывалось
именно до Module Store UI).

**Структура Module Store:**
```
ModulesScreen
 ├── InstalledSection   → ModuleRegistry.modules, отфильтрованные
 │                         по manager.isInstalled(id); Открыть/
 │                         Включить-Выключить/Удалить
 ├── AvailableSection    → InMemoryModuleCatalog.entries, у которых
 │                         !ModuleRegistry.contains(id); Установить
 └── UpdateSection       → записи каталога, которые isInstalled(id)
                           И latestManifestJson.version отличается
                           от версии в ModuleRegistry; Обновить
```
Все три читают состояние через один и тот же `ModuleManagerScope`
(Этап 10) и оборачиваются в `ListenableBuilder`, поэтому UI
реагирует на install/enable/disable/uninstall/update сразу, без
ручного `setState`.

**Как ModulePackage связывается с ModuleManager** — по цепочке,
без единого исключения из уже существующих классов:
```
ModuleCatalogEntry.installManifestJson  (строка JSON, как настоящий внешний пакет)
        │  ManifestParser.parse() + ManifestValidator.validate()   (Этап 11)
        ▼
ModuleImportResult  →  success: ModulePackage { manifest, ... }
        │
        ▼
ExternalModuleAdapter(package.manifest)   implements Module   (Этап 12, новый мост)
        │  ModuleRegistry.register(adapter)                   (Этап 7/8 — уникальность id)
        ▼
ModuleManager.install(adapter.id)                              (Этап 8, без изменений)
        │
        ▼
ModuleStatePersistence сохраняет в Isar                         (Этап 9, без изменений)
```
`ModulePackage` сам по себе не становится `Module` — он остаётся
чистыми данными (Этап 11 не менялся). `ExternalModuleAdapter` —
единственное новое звено, и оно НЕ выполняет никакого кода пакета:
просто показывает его манифест. Обновление идёт по короткому пути —
`ExternalModuleAdapter(latestManifest)` сразу в `manager.update(...)`
(Этап 8), без повторной валидации через `ModuleImportResult` — версия
для обновления берётся из доверенного каталога, а не из внешнего
источника, так что здесь это осознанно, не недосмотр.

**Какие данные временно эмулируются:**
- Все три записи каталога (Notes Lite, Calendar Lite, Example
  Module) — константные строки JSON в коде, не файлы и не сеть.
- У Notes Lite `installManifestJson` (1.0.0) и `latestManifestJson`
  (1.1.0) специально различаются — только ради демонстрации раздела
  Обновления; у Calendar Lite они совпадают (обновлять нечего).
- Запись «Example Module» в каталоге специально конфликтует по id со
  встроенным `ExampleModule` — демонстрирует защиту от дублирования
  id (Этап 11/8) на реалистичном, а не только синтетическом сценарии;
  поэтому в разделе Доступные она физически никогда не появится (id
  уже занят с самого старта приложения), но тест
  (`module_store_test.dart`) явно проверяет, что попытка ей
  воспользоваться отклоняется.

**Известное ограничение:** `InstalledSection` показывает только
модули в состоянии `installed`/`enabled`/`disabled` — полностью
удалённый (`uninstalled`) встроенный модуль (например, `example`
после uninstall) не появляется ни в Установленных (уже не
installed), ни в Доступных (id всё ещё занят в `ModuleRegistry`,
раз код встроен и никуда не делся). Переустановить его через
Module Store в этом состоянии сейчас нельзя — но сама возможность
переустановки уже проверена в Этапе 10 через собственную страницу
`ExampleModule` (она остаётся доступной через `AppDrawer` независимо
от состояния). Не стал добавлять для этого частного случая
отдельную ветку в UI, чтобы не плодить логику ради одного сценария,
но фиксирую как открытый вопрос.

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались. `module_store_test.dart` покрывает все 6
пунктов «Проверить», используя тот же код (`ManifestParser` →
`ModuleImportResult` → `ExternalModuleAdapter` → `ModuleRegistry` →
`ModuleManager`), что вызывает `AvailableSection`/`UpdateSection` —
не дублирует его отдельной тестовой реализацией.

**Что остаётся на Этап 13:** аудит безопасности (недоверенные
модули, повреждённые manifest в реальных условиях — не только в
тестах, несовместимые версии, попытки получить запрещённые данные,
откат после неудачной установки), реальное чтение
`manifest.json`/ассетов с диска или из ZIP (по-прежнему не
реализовано нигде), устранение известного ограничения выше
(переустановка полностью удалённого встроенного модуля через
Module Store), возможная общая фильтрация `AppDrawer` по состоянию
модуля (сейчас список в Drawer и `InstalledSection` фильтруются
независимо и слегка по-разному).

Команды для локального запуска:
```
dart analyze
flutter test
```

### Этап 13 — Security Audit

```
lib/core/modules/module_install_result.dart # НОВЫЙ: типизированный результат установки

test/core/modules/security_audit_test.dart  # НОВЫЙ: весь чек-лист «Проверить» (25+ тестов)
```

**Изменены:**
- `lib/core/modules/module_manager.dart` — добавлены `tryInstall()`
  (типизированный результат), проверки apiVersion/формата версии/
  зависимостей/циклов внутри `install`, rollback при неудачном
  `install`/`update`, перестановка порядка («хук до мутации
  состояния») в `enable`/`disable`, опциональный `storageFactory` в
  конструкторе (для тестируемости rollback без реального Isar).
  `install()`/`enable()`/`disable()`/`uninstall()`/`update()` — те же
  сигнатуры, тот же выбрасываемый тип исключения для существующих
  вызывающих. Ни один вызывающий код (Этапы 8/10/12) не менялся.
- `lib/core/modules/external/manifest_validator.dart` — добавлена
  проверка формата версии (тот же паттерн `major.minor.patch`, что и
  в `ModuleManager` — defense-in-depth на двух границах: валидация
  внешнего пакета и сама установка).

**Найденные уязвимости/пробелы (аудит):**
1. **`apiVersion` не проверялся в `ModuleManager.install()`** — только
   в `ManifestValidator`, который вызывает UI-слой Module Store
   (Этап 12). Прямой вызов `ModuleRegistry.register()` +
   `manager.install()` (как делает `ensureBuiltinModulesInstalled` и
   `ModuleStateRestorer`) полностью обходил эту проверку. **Исправлено**
   — проверка теперь и внутри `ModuleManager` самого.
2. **Формат версии не проверялся нигде** — ни `ManifestParser`, ни
   `ManifestValidator` не смотрели на СОДЕРЖИМОЕ строки версии, только
   на то, что это непустая строка. **Исправлено** — добавлена
   проверка `^\d+\.\d+\.\d+$` в обоих слоях.
3. **Зависимости (`manifest.dependencies`) никогда не проверялись** —
   модуль, объявивший зависимость от несуществующего/невключённого
   модуля, спокойно устанавливался. **Исправлено** в `tryInstall()`.
4. **`findDependencyCycles` (Этап 11) была построена, но нигде не
   вызывалась** — архитектура была готова, но "выключена". **Исправлено**
   — `tryInstall()` строит граф из `ModuleRegistry.modules` и вызывает её.
5. **Гонка состояния при отказе install/enable/disable** — во всех
   трёх методах состояние (`_states[moduleId] = ...`) мутировалось
   **до** вызова lifecycle-хука. Если хук бросал исключение, модуль
   оставался помеченным как `installed`/`enabled` НЕСМОТРЯ на отказ —
   классический баг "частичного применения" без отката. Конкретно
   воспроизводится: модуль без разрешения `core.search`, чей `onEnable`
   вызывает `registerSearchProvider()` — тот бросает `ModuleLifecycleError`
   из `_checkPermission`, а `enable()` до этого уже успел выставить
   `ModuleState.enabled`. **Исправлено** для `install`/`enable`/`disable`
   — хук теперь вызывается ДО мутации состояния; `install` дополнительно
   получил настоящий rollback (см. ниже), потому что для install
   "прежнее состояние" может быть `uninstalled`, а не просто "ничего".
6. **`update()` мог оставить модуль без кода в реестре** — если
   `ModuleRegistry.register(newVersion)` после `unregister(moduleId)`
   почему-либо отказывал, старая версия уже была удалена, а новая не
   встала на её место — модуль исчезал из реестра целиком.
   **Исправлено** — при отказе старая версия регистрируется обратно.
7. **Ошибки install сообщались только исключением** — для системы,
   которая явно хочет "success/failure/причина/список нарушений" (а не
   одну строку в `Exception.toString()`), это было недостаточно
   структурировано. **Исправлено** — `ModuleInstallResult`.

**Что сознательно оставлено:**
- Rollback для `update()` в ветке «`register(newVersion)` отказал» не
  покрыт тестом — в однопоточном коде этот путь недостижим естественным
  образом сразу после успешного `unregister()` той же id (никто другой
  не может синхронно занять освободившийся id между двумя строками).
  Защита в коде есть (см. выше), тест — нет; это осознанно, не
  недосмотр: писать искусственный тест только ради покрытия строки
  посчитал менее ценным, чем честно об этом написать.
- `tryEnable`/`tryDisable`/`tryUninstall`/`tryUpdate` (типизированные
  версии остальных операций, по аналогии с `tryInstall`) не созданы —
  задание Этапа 13 явно просило «единый результат УСТАНОВКИ», не всех
  пяти операций. `enable`/`disable`/`uninstall`/`update` получили
  исправление порядка/отката, но остались exception-based.
- Проверка permissions при install (например, "не устанавливать
  модуль, запрашивающий неизвестное ядру разрешение") не добавлена —
  `ModulePermission` уже поддерживает неизвестные строки как штатный
  случай (Этап 7, ради совместимости с будущими внешними модулями);
  отклонять install из-за незнакомого разрешения означало бы, что
  ядро не может устанавливать модули с разрешениями из будущих версий
  API — противоречит собственной архитектуре. Проверка разрешения
  происходит там, где оно реально ИСПОЛЬЗУЕТСЯ (`registerSearchProvider`
  в `_ModuleApiImpl`), не заранее при install.
- Полноценный аудит внешнего формата (реальные повреждённые ZIP,
  файлы с диска) — по-прежнему нет чтения файлов нигде в проекте
  (Этап 11/12 ограничение сохраняется), поэтому "повреждённый manifest
  в реальных условиях" проверен только на уровне строк JSON, не файлов.

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались. `security_audit_test.dart` покрывает все 7
пунктов «Проверить»: битый manifest (несовместимый apiVersion/неверный
формат версии), дубликат moduleId, циклические зависимости, rollback
после ошибки (включая стирание частично записанных данных и повторную
успешную установку после отката), полное удаление данных, сохранность
остальных модулей (дважды — на уровне `ModuleManager` с раздельными
fake-хранилищами и сквозно через `ModuleStatePersistence`).

Команды для локального запуска:
```
dart analyze
flutter test
```

### Этап 14 — Schedule Module

```
lib/modules/schedule/
├── schedule_module.dart          # НОВЫЙ: ScheduleModule (manifest + lifecycle)
├── schedule_repository.dart      # НОВЫЙ: CRUD поверх ModuleStorage + ScheduleDaySummary
├── schedule_search_provider.dart # НОВЫЙ: SearchProvider по названию/категории/заметке
├── models/
│   └── schedule_event.dart       # НОВЫЙ: ScheduleEvent, EventPriority, EventStatus + JSON
└── ui/
    ├── schedule_screen.dart      # НОВЫЙ: корневой экран (вкладки + FAB)
    ├── today_tab.dart            # НОВЫЙ: «Сегодня» — список/занято/свободно
    ├── calendar_tab.dart         # НОВЫЙ: «Календарь» — выбор даты + события дня
    ├── event_form_screen.dart    # НОВЫЙ: создание/редактирование/удаление события
    └── event_tile.dart           # НОВЫЙ: переиспользуемая строка события

test/modules/schedule/schedule_module_test.dart # НОВЫЙ: весь чек-лист «Проверить»
```

**Изменён один файл:** `lib/core/modules/module_bootstrap.dart` —
добавлена одна строка `ScheduleModule()` рядом с `ExampleModule()`,
ровно как обещал комментарий в этом файле с самого Этапа 3.

**Структура Schedule:**
```
ScheduleModule (Module)
 ├── manifest: id='schedule', permissions=[core.search]
 ├── onEnable/onDisable: регистрирует/снимает ScheduleSearchProvider
 └── buildPage → ScheduleScreen
                   ├── TabBar: Сегодня | Календарь
                   │     ├── TodayTab    → ScheduleRepository.getForDate(сегодня) + ScheduleDaySummary
                   │     └── CalendarTab → CalendarDatePicker + ScheduleRepository.getForDate(выбранная дата)
                   └── FAB → EventFormScreen (create)
                              EventTile.onTap → EventFormScreen (edit/delete)

ScheduleRepository — единственная точка доступа к данным:
  add/update → storage.setString('event:<id>', jsonEncode(...))
  delete     → storage.remove('event:<id>')
  getAll     → storage.keys().where(startsWith('event:')) → parse каждый
```
Никакой отдельной Isar-коллекции под Schedule нет — `ScheduleRepository`
работает целиком через уже существующий `ModuleStorage` (Этап 9),
тот же контракт, что и у заметки `ExampleModule`. Список событий не
хранится отдельным индексом — просто фильтруются все ключи модуля по
префиксу `event:` (`ModuleStorage.keys()` и так возвращает только
ключи ЭТОГО модуля, изоляция уже гарантирована слоем ниже).

**Жизненный цикл модуля** — ничем не отличается от `ExampleModule`
(Этап 10), `ModuleManager` не менялся ни строкой:
```
регистрация (module_bootstrap.dart)
        → install (ensureBuiltinModulesInstalled при первом запуске)
        → enable → onEnable регистрирует ScheduleSearchProvider
        → [использование: создание/редактирование/удаление событий]
        → disable → onDisable снимает ScheduleSearchProvider
        → uninstall → ModuleStatePersistence стирает состояние И
                       все ключи `event:*` этого модуля (Этап 9,
                       без изменений — Schedule просто ещё один
                       потребитель уже готового механизма)
```

**Найденные и исправленные по ходу работы баги (компиляционные, не
логические — но реальные, стоит перечислить честно):**
- `late final _repository`, присваиваемое внутри `build()` —
  `LateInitializationError` при второй сборке виджета. Исправлено:
  инициализация перенесена в `didChangeDependencies()` (тот же приём,
  что и в `ExampleModule`), поле сделано nullable.
- Неверная глубина относительного импорта в `schedule_screen.dart`
  (файл в `ui/`, на уровень глубже остальных файлов модуля) —
  `../../core/...` указывал бы на несуществующий `lib/modules/core/`.
  Исправлено на `../../../core/...`.
- Обновление данных после добавления события через FAB: простой
  `setState()` родителя не заставил бы `TodayTab`/`CalendarTab`
  перечитать данные (Flutter сохраняет их `State` при том же ключе/
  типе виджета — `initState()` с загрузкой не вызвался бы заново).
  Исправлено через смену `ValueKey` (счётчик `_refreshTick`) —
  плата: у «Календаря» при этом сбрасывается выбранная дата на
  сегодня; сознательное упрощение для базовой версии, не влияет на
  сохранность данных.

**Что сознательно упрощено (сама задача явно просит "базовую
версию"):** свободное время считается от условных суток (1440 мин)
без учёта пересечения событий друг с другом (не «сшивает» интервалы);
поиск — простой `contains()` по подстроке, не полнотекстовый;
календарь — стандартный `CalendarDatePicker`, без индикаторов «есть
события в этот день» на самих числах месяца.

**Проверки:** Flutter/Dart SDK недоступен — `dart analyze`/`flutter
test` не запускались, честно не имитирую. `schedule_module_test.dart`
покрывает все 6 пунктов «Проверить»: создание, редактирование,
удаление, поиск (по названию/категории/заметке отдельно), сохранение
после «перезапуска» (новый репозиторий поверх того же хранилища) и
включение/отключение без потери данных (через настоящие `ScheduleModule`
+ `ModuleManager` с fake `ModuleStorage`).

Команды для локального запуска:
```
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
dart analyze
flutter test
```
