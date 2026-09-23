import '../module_manifest.dart';
import 'manifest_parser.dart';
import 'manifest_validator.dart';
import 'module_package.dart';

/// Итог попытки импортировать внешний модуль: либо готовый
/// ModulePackage, либо список причин отказа.
///
/// Не бросает исключений наружу — ошибки формата и валидации для
/// внешнего, недоверенного пакета это ОЖИДАЕМЫЙ, а не аварийный
/// исход, поэтому результат — обычное значение, которое вызывающий
/// код (будущий Module Store UI, Этап 12) разбирает через isSuccess.
class ModuleImportResult {
  final bool isSuccess;
  final ModulePackage? package;
  final List<String> errors;

  const ModuleImportResult._({
    required this.isSuccess,
    this.package,
    this.errors = const [],
  });

  const ModuleImportResult.success(ModulePackage package)
      : this._(isSuccess: true, package: package);

  const ModuleImportResult.failure(List<String> errors)
      : this._(isSuccess: false, errors: errors);

  /// Собирает пакет из сырых входных данных: строка manifest.json +
  /// списки путей assets/data + опциональный README.
  ///
  /// Единственная точка, которая связывает ManifestParser,
  /// ManifestValidator и ModulePackage вместе — статический фабричный
  /// метод здесь, а не отдельный класс-оркестратор: у него нет
  /// собственного состояния и поведения сверх последовательного
  /// вызова уже существующих классов, так что отдельный файл добавил
  /// бы абстракцию ради количества файлов, а не ради архитектуры.
  ///
  /// Циклы зависимостей (ManifestValidator.findDependencyCycles)
  /// сюда намеренно НЕ включены: для них нужен граф МНОЖЕСТВА
  /// модулей, а здесь импортируется всегда один пакет за раз. Код,
  /// который будет ставить несколько внешних модулей разом (не на
  /// Этапе 11), сам построит граф и отдельно вызовет
  /// findDependencyCycles над результатами нескольких import().
  factory ModuleImportResult.from({
    required String manifestJson,
    List<String> assetPaths = const [],
    List<String> dataPaths = const [],
    String? readme,
    required Set<String> existingModuleIds,
    ManifestParser? parser,
    ManifestValidator? validator,
  }) {
    final effectiveParser = parser ?? ManifestParser();
    final effectiveValidator = validator ?? ManifestValidator();

    final ModuleManifest manifest;
    try {
      manifest = effectiveParser.parse(manifestJson);
    } on ManifestParseException catch (e) {
      return ModuleImportResult.failure([e.message]);
    }

    final errors = effectiveValidator.validate(
      manifest,
      existingModuleIds: existingModuleIds,
    );
    if (errors.isNotEmpty) {
      return ModuleImportResult.failure(errors);
    }

    return ModuleImportResult.success(ModulePackage(
      manifest: manifest,
      assetPaths: assetPaths,
      dataPaths: dataPaths,
      readme: readme,
    ));
  }
}
