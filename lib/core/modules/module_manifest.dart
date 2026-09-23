import 'module_permission.dart';

/// Версия Module API, которую понимает текущее ядро.
///
/// Не путать с ModuleManifest.version (версия самого модуля).
/// Меняется только тогда, когда контракты этого пакета (Module,
/// ModuleApi, ModuleManifest) меняются несовместимо. Сверка
/// manifest.apiVersion с этой константой — задача ModuleManager
/// (Этап 8), не этого файла.
const int kCoreModuleApiVersion = 1;

/// Зависимость модуля от другого модуля.
///
/// Только структура данных — само сравнение версий и разрешение
/// графа зависимостей (что ставить первым, что блокировать при
/// отсутствии зависимости) реализует ModuleManager на Этапе 8.
class ModuleDependency {
  final String moduleId;
  final String? minVersion;

  const ModuleDependency({required this.moduleId, this.minVersion});

  factory ModuleDependency.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('ModuleDependency: отсутствует поле "id"');
    }
    return ModuleDependency(
      moduleId: id,
      minVersion: json['minVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': moduleId,
        if (minVersion != null) 'minVersion': minVersion,
      };
}

/// Манифест модуля.
///
/// Декларативное описание модуля, не зависящее от того, есть ли
/// у модуля собственный скомпилированный Dart-код. Для встроенных
/// модулей (ExampleModule и т.п.) манифест — часть класса Module.
/// Для внешних модулей (Этап 11) это единственное, что у модуля
/// вообще есть — свой код им иметь нельзя (см. аудит Этапа 6:
/// ядро не выполняет произвольный скачанный код).
class ModuleManifest {
  final String id;
  final String name;
  final String version;
  final int apiVersion;
  final String author;
  final String description;

  /// Идентификатор/имя иконки строкой, а не Flutter IconData —
  /// манифест должен разбираться из чужого JSON без зависимости
  /// от Flutter. Как строка превращается в отображаемую иконку —
  /// вопрос Module Store (Этап 12).
  final String icon;

  final List<ModulePermission> permissions;
  final List<ModuleDependency> dependencies;

  const ModuleManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.author,
    this.description = '',
    this.icon = '',
    this.permissions = const [],
    this.dependencies = const [],
  });

  /// Разбирает manifest.json в модель.
  ///
  /// Проверяет только структуру: обязательные поля присутствуют
  /// и имеют правильный тип. НЕ проверяет совместимость apiVersion
  /// с ядром, разрешённость permissions или разрешимость
  /// dependencies — это задача установки внешнего модуля (Этап 11)
  /// и ModuleManager (Этап 8), которые могут дать пользователю
  /// осмысленную ошибку, в отличие от голого парсера.
  factory ModuleManifest.fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException(
          'ModuleManifest: отсутствует или пустое обязательное поле "$key"',
        );
      }
      return value;
    }

    final apiVersion = json['apiVersion'];
    if (apiVersion is! int) {
      throw const FormatException(
        'ModuleManifest: поле "apiVersion" должно быть целым числом',
      );
    }

    final permissionsJson = json['permissions'] as List<dynamic>? ?? const [];
    final dependenciesJson =
        json['dependencies'] as List<dynamic>? ?? const [];

    return ModuleManifest(
      id: requireString('id'),
      name: requireString('name'),
      version: requireString('version'),
      apiVersion: apiVersion,
      author: requireString('author'),
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      permissions:
          permissionsJson.map((p) => ModulePermission(p as String)).toList(),
      dependencies: dependenciesJson
          .map((d) => ModuleDependency.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'apiVersion': apiVersion,
        'author': author,
        if (description.isNotEmpty) 'description': description,
        if (icon.isNotEmpty) 'icon': icon,
        if (permissions.isNotEmpty)
          'permissions': permissions.map((p) => p.id).toList(),
        if (dependencies.isNotEmpty)
          'dependencies': dependencies.map((d) => d.toJson()).toList(),
      };
}
