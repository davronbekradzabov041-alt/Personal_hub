import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/core_test_item.dart';
import 'models/app_settings.dart';
import 'models/module_state_record.dart';
import 'models/module_data_row.dart';

/// Сервис базы данных Isar.
///
/// Один экземпляр Isar на всё приложение. Инициализируется
/// один раз в main.dart до runApp(), чтобы база была готова
/// к моменту первой отрисовки UI.
///
/// Модули НЕ открывают свою базу и (начиная с аудита Этапа 6) не
/// заводят собственные типизированные Isar-схемы — Isar регистрирует
/// схемы на этапе компиляции, а внешний модуль (Этап 11) может не
/// иметь своего Dart-кода вовсе. Данные модулей будут жить в общей
/// generic-коллекции через ModuleStorage (контракт — Этап 7,
/// реализация — Этап 9), используя тот же экземпляр Isar.
class IsarService {
  IsarService._();

  static Isar? _isar;

  /// Готовый экземпляр базы. Бросает ошибку, если init() ещё
  /// не был вызван — это осознанно: инициализация должна
  /// произойти один раз, явно, в main.dart.
  static Isar get instance {
    final isar = _isar;
    if (isar == null) {
      throw StateError(
        'IsarService.init() ещё не был вызван. '
        'Добавьте "await IsarService.init();" в main() до runApp().',
      );
    }
    return isar;
  }

  /// Открывает базу данных. Безопасен для повторного вызова —
  /// если база уже открыта, просто возвращает существующий экземпляр.
  static Future<Isar> init() async {
    if (_isar != null) return _isar!;

    final dir = await getApplicationDocumentsDirectory();

    _isar = await Isar.open(
      // Список схем ядра и (в будущем) модулей.
      // CoreTestItemSchema — временная тестовая коллекция ядра,
      // используется для проверки CRUD и глобального поиска (Этап 5).
      // AppSettingsSchema — единственная запись общих настроек (Этап 4).
      // ModuleStateRecordSchema — постоянное состояние модулей (Этап 9).
      // ModuleDataRowSchema — общее generic key-value хранилище данных
      // модулей (Этап 9) — одна коллекция на все модули, без отдельных
      // типизированных схем на каждый.
      [
        CoreTestItemSchema,
        AppSettingsSchema,
        ModuleStateRecordSchema,
        ModuleDataRowSchema,
      ],
      directory: dir.path,
      name: 'personal_hub_db',
    );

    return _isar!;
  }

  /// Закрывает базу. На практике почти не нужен (Isar живёт
  /// весь жизненный цикл приложения), но полезен для тестов.
  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
