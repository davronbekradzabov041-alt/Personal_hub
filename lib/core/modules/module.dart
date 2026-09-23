import 'package:flutter/material.dart';
import 'module_api.dart';
import 'module_manifest.dart';

/// Контракт модуля уровня ядра (Module API, Этап 7).
///
/// Описывает встроенные модули — скомпилированные вместе с
/// приложением (ExampleModule, позже Schedule). Внешние модули
/// (Этап 11) не могут содержать собственный Dart-код (аудит
/// Этапа 6 / требование безопасности из Этапа 13 — ядро не
/// выполняет произвольный скачанный код), поэтому для них
/// потребуется отдельное, чисто декларативное представление —
/// это открытый вопрос Этапа 11, а не этого файла.
///
/// `id` и `title` — не отдельные поля, а производные от
/// [manifest], чтобы не было двух источников правды о личности
/// модуля.
abstract class Module {
  /// Манифест — источник правды об id/имени/версии/разрешениях.
  ModuleManifest get manifest;

  /// Иконка в боковом меню. Отдельно от manifest.icon (строка):
  /// строковая иконка манифеста нужна для модулей без Flutter-кода
  /// (Module Store, Этап 12), а у встроенного модуля есть готовый
  /// Flutter-код — он даёт IconData напрямую.
  IconData get icon;

  /// Порядок отображения в меню (меньше — выше).
  int get order => 100;

  String get id => manifest.id;
  String get title => manifest.name;

  /// Строит главную страницу модуля.
  Widget buildPage(BuildContext context);

  // --- Жизненный цикл: installed → enabled → disabled → uninstalled ---
  //
  // Вызывается будущим ModuleManager (Этап 8) на соответствующих
  // переходах состояния. Пустые тела по умолчанию — большинству
  // модулей (как ExampleModule) реагировать не на что.

  /// Модуль только что установлен, ещё не включён.
  Future<void> onInstall(ModuleApi api) async {}

  /// Модуль переходит в activate/enabled — например, стоит
  /// зарегистрировать свои SearchProvider через [ModuleApi].
  Future<void> onEnable(ModuleApi api) async {}

  /// Модуль выключается — стоит отменить регистрацию в поиске
  /// и остановить любую фоновую активность, если она была.
  Future<void> onDisable(ModuleApi api) async {}

  /// Модуль удаляется. После этого хука ModuleManager (Этап 8/9)
  /// очищает хранилище модуля — сам модуль ничего дополнительно
  /// стирать не обязан, если не хранит данные вне ModuleStorage.
  Future<void> onUninstall(ModuleApi api) async {}
}
