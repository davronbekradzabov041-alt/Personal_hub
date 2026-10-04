import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manager_scope.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_persistence_scope.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/widgets/module_store/available_section.dart';
import 'package:personal_hub/ui/widgets/module_store/module_card.dart';

/// R-02: неудачная установка из Module Store не должна оставлять модуль
/// зарегистрированным.
///
/// Порядок «зарегистрировать → установить» вынужден: ModuleManager
/// устанавливает уже зарегистрированный модуль. Но если установка падает,
/// регистрация оставалась, и модуль навсегда исчезал из «Доступных»
/// (раздел фильтрует по `ModuleRegistry.contains`), не появляясь в
/// «Установленных»: повторная установка в этой сессии становилась
/// невозможной без перезапуска приложения.
void main() {
  late ModuleManager manager;
  late ModuleStatePersistence persistence;
  late _MemoryStateStore store;

  setUp(() {
    ModuleRegistry.clear();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _MemoryModuleStorage(),
    );
    store = _MemoryStateStore();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: (_) => _MemoryModuleStorage(),
    );
  });

  tearDown(() {
    persistence.dispose();
    ModuleRegistry.clear();
  });

  Widget app() {
    return ModuleStatePersistenceScope(
      persistence: persistence,
      child: ModuleManagerScope(
        manager: manager,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AvailableSection())),
        ),
      ),
    );
  }

  /// Кнопка «Установить» именно у нужной карточки: в каталоге три
  /// записи с одинаковой подписью, поэтому искать надо внутри
  /// ModuleCard, а не по всему экрану.
  Finder installButtonFor(String moduleName) {
    final card = find.ancestor(
      of: find.text(moduleName),
      matching: find.byType(ModuleCard),
    );
    return find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, 'Установить'),
    );
  }

  testWidgets('R-02: после неудачной установки модуль снова доступен',
      (tester) async {
    // Делаем установку заведомо неуспешной, не подменяя production-код:
    // состояние 'installed' выставляется напрямую, тогда как в
    // ModuleRegistry модуля нет. Доступен он поэтому по-прежнему, и
    // ModuleManager.tryInstall отклоняет его с «уже установлен».
    //
    // Важно, что модуль НЕ зарегистрирован: иначе раздел «Доступные»
    // отфильтровал бы его и кнопки установки не существовало бы.
    manager.setStateForTesting('notes-lite', ModuleState.installed);
    expect(ModuleRegistry.contains('notes-lite'), isFalse);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Notes Lite'), findsOneWidget,
        reason: 'модуль обязан быть виден в разделе «Доступные»');

    final before = ModuleRegistry.modules.length;

    await tester.tap(installButtonFor('Notes Lite'));
    await tester.pumpAndSettle();

    // 1. Установка завершилась ошибкой — пользователь её видит.
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'пользователь обязан получить сообщение об отказе');
    expect(find.textContaining('уже установлен'), findsOneWidget);

    // 2. Регистрация снята.
    expect(ModuleRegistry.contains('notes-lite'), isFalse,
        reason: 'неудачная установка не должна оставлять модуль в реестре');
    expect(ModuleRegistry.modules.length, before,
        reason: 'реестр обязан вернуться к исходному составу');

    // 3. Модуль снова доступен для установки.
    expect(find.text('Notes Lite'), findsOneWidget,
        reason: 'модуль обязан вернуться в «Доступные»');

    // И кнопка установки снова доступна для повторной попытки.
    final button = tester.widget<FilledButton>(installButtonFor('Notes Lite'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('R-02: успешная установка по-прежнему оставляет модуль в реестре',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(ModuleRegistry.contains('calendar-lite'), isFalse);
    expect(find.text('Calendar Lite'), findsOneWidget);

    await tester.tap(installButtonFor('Calendar Lite'));
    await tester.pumpAndSettle();

    // Успешный путь не должен пострадать от отката регистрации.
    expect(ModuleRegistry.contains('calendar-lite'), isTrue,
        reason: 'успешная установка обязана оставить модуль в реестре');
    expect(manager.stateOf('calendar-lite'), ModuleState.installed);

    // Модуль ушёл из «Доступных» — он теперь установлен.
    await tester.pumpAndSettle();
    expect(find.text('Calendar Lite'), findsNothing);
  });
}

class _MemoryModuleStorage implements ModuleStorage {
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

class _MemoryStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async => _data.remove(moduleId);
}