import 'module_permission.dart';

/// Версия Module API, которую понимает текущее ядро.
///
/// Не путать с ModuleManifest.version (версия самого модуля).
/// Меняется только тогда, когда контракты этого пакета (Module,
/// ModuleApi, ModuleManifest) меняются несовместимо. Сверка
/// manifest.apiVersion с этой константой — задача ModuleManager
/// (Этап 8), не этого файла.
const int kCoreModuleApiVersion = 1;

/// Версия схемы данных, подразумеваемая, пока модуль о ней не
/// говорит (Этап 9.1).
///
/// Модуль, который не объявил `schemaVersion`, ничего о структуре
/// своих данных не менял: все данные, записанные до появления миграций,
/// имеют исходную форму. Обратная договорённость («не объявил — значит
/// новейшая») сделала бы каждый модуль, написанный до Этапа 9.1, требующим
/// миграции, которой нет.
const int kInitialModuleSchemaVersion = 1;

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

  /// Версия структуры пользовательских данных модуля (Этап 9.1).
  ///
  /// Не путать с [version]: та — версия КОДА модуля (строгий
  /// `X.Y.Z`, её сравнивает ModuleVersion), эта — версия ФОРМЫ его
  /// данных в ModuleStorage. Модуль, изменивший структуру своих
  /// данных, повышает счётчик здесь; какая версия фактически лежит
  /// в хранилище — читается из маркера `schema:version`
  /// (ModuleSchemaMarker).
  ///
  /// Целое число, а не строка и не `X.Y.Z`: это счётчик переносов, а
  /// не версия публикации, и сравнивать его вручную пользователю не
  /// нужно. [initialSchemaVersion] означает «данных никогда не
  /// переносили».
  final int schemaVersion;

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
    this.schemaVersion = kInitialModuleSchemaVersion,
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

    // schemaVersion необязателен: его отсутствие в старом манифесте —
    // это исходная форма данных, а не ошибка. Непустое и нецелое
    // значение, наоборот, отвергается: молча превратив "2" в
    // kInitialModuleSchemaVersion, мы бы решили, что перенос не
    // нужен, и оставили бы данные в форме, которой новый код не
    // понимает.
    final schemaVersion = json['schemaVersion'] ?? kInitialModuleSchemaVersion;
    if (schemaVersion is! int) {
      throw const FormatException(
        'ModuleManifest: поле "schemaVersion" должно быть целым числом',
      );
    }
    if (schemaVersion < 1) {
      throw const FormatException(
        'ModuleManifest: поле "schemaVersion" должно быть не меньше 1',
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
      schemaVersion: schemaVersion,
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
        // Только когда отличается от умолчания: иначе каждый нынешний
        // модуль начал бы писать в манифест поле, которого там не было,
        // и байты .phm менялись бы без изменения смысла.
        if (schemaVersion != kInitialModuleSchemaVersion)
          'schemaVersion': schemaVersion,
        if (description.isNotEmpty) 'description': description,
        if (icon.isNotEmpty) 'icon': icon,
        if (permissions.isNotEmpty)
          'permissions': permissions.map((p) => p.id).toList(),
        if (dependencies.isNotEmpty)
          'dependencies': dependencies.map((d) => d.toJson()).toList(),
      };
}
