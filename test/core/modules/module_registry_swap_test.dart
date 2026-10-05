/// Безопасный обмен реализации модуля в реестре (Этап 8.1-А).
///
/// Проверяется не «сработало ли», а ГДЕ именно модуль находится в
/// каждый момент: обмен, который оставляет модуль без кода даже на
/// микросекунду, роняет всё, что читает реестр в этот момент.
library module_registry_swap_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';

class _StubModule extends Module {
  _StubModule(this._manifest);

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {}
}

ModuleManifest _manifest(String id, String version) => ModuleManifest(
      id: id,
      name: 'Модуль $id',
      version: version,
      apiVersion: 1,
      author: 'Test',
    );

void main() {
  setUp(ModuleRegistry.clear);

  group('ModuleRegistry.swap', () {
    test('заменяет модуль и возвращает предыдущий', () {
      final first = _StubModule(_manifest('notes', '1.0.0'));
      final second = _StubModule(_manifest('notes', '1.1.0'));
      ModuleRegistry.register(first);

      final previous = ModuleRegistry.swap(second);

      expect(previous, same(first));
      expect(ModuleRegistry.get('notes'), same(second));
      expect(ModuleRegistry.modules, hasLength(1), reason: 'обмен, а не замена '
          'списка: количество модулей не изменилось');
    });

    test('модуль виден в реестре без единого промежуточного «нет модуля»', () {
      // Unregister+register оставлял модуль отсутствующим между двумя
      // вызовами. Здесь читатель реестра (меню, проверка зависимостей)
      // не может увидеть модуль в промежутке: чтение выполняется
      // до и после обмена, а в обоих состояниях модуль на месте.
      final first = _StubModule(_manifest('notes', '1.0.0'));
      final second = _StubModule(_manifest('notes', '2.0.0'));
      ModuleRegistry.register(first);

      expect(ModuleRegistry.contains('notes'), isTrue);
      ModuleRegistry.swap(second);
      expect(ModuleRegistry.contains('notes'), isTrue);

      expect(ModuleRegistry.get('notes')!.manifest.version, '2.0.0');
    });

    test('откат — это тот же swap предыдущего модуля', () {
      final first = _StubModule(_manifest('notes', '1.0.0'));
      final second = _StubModule(_manifest('notes', '1.1.0'));
      ModuleRegistry.register(first);

      ModuleRegistry.swap(second);
      final rolledBack = ModuleRegistry.swap(first);

      expect(rolledBack, same(second));
      expect(ModuleRegistry.get('notes'), same(first));
      expect(ModuleRegistry.get('notes')!.manifest.version, '1.0.0');
    });

    test('чужая замена не проходит под видом обновления', () {
      ModuleRegistry.register(_StubModule(_manifest('notes', '1.0.0')));

      // register() бросил бы «id занят», но тихо превратил бы
      // обновление в установку нового модуля. Здесь — явная ошибка.
      expect(
        () => ModuleRegistry.swap(_StubModule(_manifest('other', '1.0.0'))),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(ModuleRegistry.modules, hasLength(1));
    });

    test('незарегистрированный модуль менять нечего', () {
      expect(
        () => ModuleRegistry.swap(_StubModule(_manifest('ghost', '1.0.0'))),
        throwsA(isA<ModuleLifecycleError>()),
      );
    });

    test('пустой id отклоняется до мутации', () {
      ModuleRegistry.register(_StubModule(_manifest('notes', '1.0.0')));

      expect(
        () => ModuleRegistry.swap(_StubModule(_manifest('   ', '1.0.0'))),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(ModuleRegistry.contains('notes'), isTrue);
    });

    test('остальные модули не затрагиваются', () {
      final notes = _StubModule(_manifest('notes', '1.0.0'));
      final calendar = _StubModule(_manifest('calendar', '3.2.1'));
      ModuleRegistry.registerAll([notes, calendar]);

      ModuleRegistry.swap(_StubModule(_manifest('notes', '1.1.0')));

      expect(ModuleRegistry.get('calendar'), same(calendar));
      expect(ModuleRegistry.modules, hasLength(2));
    });

    test('существующий API register/unregister не сломан', () {
      final module = _StubModule(_manifest('notes', '1.0.0'));

      ModuleRegistry.register(module);
      ModuleRegistry.register(module); // тот же объект — no-op
      expect(ModuleRegistry.contains('notes'), isTrue);

      expect(ModuleRegistry.unregister('notes'), isTrue);
      expect(ModuleRegistry.unregister('notes'), isFalse);
      expect(ModuleRegistry.contains('notes'), isFalse);
    });

    test('register по-прежнему запрещает чужой объект на занятый id', () {
      ModuleRegistry.register(_StubModule(_manifest('notes', '1.0.0')));

      expect(
        () => ModuleRegistry.register(_StubModule(_manifest('notes', '1.0.1'))),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(ModuleRegistry.get('notes')!.manifest.version, '1.0.0');
    });
  });
}