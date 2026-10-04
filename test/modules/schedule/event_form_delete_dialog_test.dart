import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/schedule/models/schedule_event.dart';
import 'package:personal_hub/modules/schedule/schedule_repository.dart';
import 'package:personal_hub/modules/schedule/ui/event_form_screen.dart';

/// UI-01: кнопки диалога подтверждения удаления должны закрывать
/// сам dialog, а не маршрут под ним.
///
/// Раньше `actions` получали `context` вызывающего `EventFormScreen`,
/// поэтому `Navigator.of(context).pop(...)` закрывал сам экран формы.
/// Для «Отмены» это означало исчезновение формы без удаления, а для
/// «Удалить» — потерю результата подтверждения: `await` возвращал не
/// `true`, а результат закрытия формы, из-за чего событие удалялось
/// раньше, чем пользователь на это согласился.
void main() {
  late _InMemoryStorage storage;
  late ScheduleRepository repository;

  ScheduleEvent existingEvent() => ScheduleEvent(
        id: 'evt-1',
        title: 'Планёрка',
        category: 'Работа',
        priority: EventPriority.medium,
        date: DateTime(2026, 3, 10),
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        status: EventStatus.planned,
        note: 'подготовить слайды',
      );

  setUp(() async {
    storage = _InMemoryStorage();
    repository = ScheduleRepository(storage);
    await repository.add(existingEvent());
  });

  /// Экран формы внутри ВЛОЖЕННОГО Navigator — как в приложении.
  ///
  /// Это существенно для воспроизведения дефекта. `showDialog` по
  /// умолчанию открывает диалог на корневом Navigator
  /// (`useRootNavigator: true`), а форма живёт во вложенном
  /// Navigator оболочки AppShell. Поэтому `Navigator.of(context)` с
  /// context'а формы указывает на вложенный Navigator и закрывает
  /// маршрут формы, а не dialog. Если положить форму на корневой
  /// Navigator, дефект не воспроизводится вовсе — оба Navigator'а
  /// совпадают и pop() случайно попадает в dialog.
  Widget app() {
    return MaterialApp(
      home: Scaffold(
        key: const ValueKey('root-host'),
        body: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (formContext) => ElevatedButton(
                    onPressed: () => Navigator.of(formContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EventFormScreen(
                          repository: repository,
                          existing: existingEvent(),
                        ),
                      ),
                    ),
                    child: const Text('Открыть форму'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('UI-01: «Отмена» закрывает только диалог, форма остаётся',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Открыть форму'));
    await tester.pumpAndSettle();

    expect(find.byType(EventFormScreen), findsOneWidget);

    // Форма живёт во вложенном Navigator, диалог — на корневом.
    // Это расхождение и есть причина дефекта, поэтому фиксируем его
    // явно: иначе тест проходит в любом случае.
    final formContext = tester.element(find.byType(EventFormScreen));
    final rootNavigator =
        Navigator.of(tester.element(find.byKey(const ValueKey('root-host'))));
    expect(Navigator.of(formContext), isNot(same(rootNavigator)),
        reason: 'тест бессмыслен, если форма и корневой Navigator совпадают');

    // Открываем диалог подтверждения.
    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить событие?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    // Диалог закрыт, форма на месте.
    expect(find.text('Удалить событие?'), findsNothing);
    expect(find.byType(EventFormScreen), findsOneWidget,
        reason: '«Отмена» не должна закрывать экран формы');
    expect(find.text('Редактировать событие'), findsOneWidget);

    // Событие не удалено — отказ не должен иметь побочных эффектов.
    final stored = await repository.getAll();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'evt-1');
  });

  testWidgets('UI-01: после «Отмены» диалог открывается снова и удаление работает',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Открыть форму'));
    await tester.pumpAndSettle();

    // Первый диалог — отмена.
    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(EventFormScreen), findsOneWidget);

    // Второй диалог — подтверждение. Форма обязана дожить до него.
    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить событие?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    // Подтверждение дошло до _delete(): событие удалено из хранилища.
    expect(await repository.getAll(), isEmpty,
        reason: 'подтверждённое удаление обязано удалить событие');

    // Экран формы закрылся только после успешного удаления.
    expect(find.byType(EventFormScreen), findsNothing);
  });

  testWidgets('UI-01: отмена не закрывает форму даже при повторном открытии',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Открыть форму'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить событие?'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(find.byType(EventFormScreen), findsOneWidget,
          reason: 'форма обязана пережить любое число отмен');
    }

    expect(await repository.getAll(), hasLength(1));
  });
}

class _InMemoryStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}