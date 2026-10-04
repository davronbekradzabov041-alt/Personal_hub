# modules/

Здесь живут независимые модули приложения, каждый в своей
подпапке. Каждый модуль реализует интерфейс `Module`
(`core/modules/module.dart`) и регистрируется одной строкой
в `core/modules/module_bootstrap.dart`.

Актуальные модули:
- `modules/example/` — демонстрационный модуль, доказывающий,
  что механизм регистрации и навигации работает.
- `modules/schedule/` — Schedule, первый полноценный
  функциональный модуль (Этап 14): события по дням, вкладки
  «Сегодня»/«Календарь», поиск через `GlobalSearchService`,
  своя секция главного экрана в `ui/home/` (QUAL-03).

Финансы, Аккаунты, Файлы, AI по-прежнему запрещены до отдельной
команды. Backup реализован не как модуль, а в ядре
(`core/backup/`, Stage 6).

Правило: ядро (`core/`, `ui/`) никогда не импортирует код
из `modules/`. Зависимость — только в одну сторону: модуль
может использовать ядро (например, `BaseRepository`,
`EmptyState`), но не наоборот. Разрешённые исключения —
composition root: `core/modules/module_bootstrap.dart`,
`core/navigation/app_routes.dart`, `core/navigation/app_shell.dart`
(см. `test/ui/home_architecture_boundary_test.dart`).
