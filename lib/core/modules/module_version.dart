/// Версия модуля: строгий `major.minor.patch` с осмысленным сравнением.
///
/// До этого этапа версия была строкой, а сравнение — проверкой
/// «строка изменилась» (ModuleManager.update). Этого недостаточно для
/// обновления: `'0.9.0'` и `'0.10.0'` — разные версии, но по
/// алфавиту `'0.10.0' < '0.9.0'`, и пользователь, получив такую
/// сборку, увидел бы «обновление на более старую версию».
///
/// Строгий формат — тот же, что проверяли ModuleManager и
/// ManifestValidator: никаких `1.0`, `1.0.0-beta`, `v1.0.0`. Правило
/// одно на всех ([pattern]), чтобы «валидная версия» не зависела от
/// того, кто именно её проверяет.
library module_version;

class ModuleVersion implements Comparable<ModuleVersion> {
  const ModuleVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  /// Строгий формат версии. Используется и ModuleManager, и
  /// ManifestValidator — иначе «валидная версия» означала бы разное в
  /// разных проверках.
  static final RegExp pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  /// Разбирает `X.Y.Z`. null — если строка не разбирается.
  ///
  /// Именно tryParse, а не parse: проверка версии — это про НУЖНО ЛИ
  /// обновление, где «не разобралось» является причиной отказа, а не
  /// исключением, которое должен ловить вызывающий. Версия из
  /// манифеста — это ввод, а не программная ошибка.
  static ModuleVersion? tryParse(String raw) {
    final match = pattern.firstMatch(raw.trim());
    if (match == null) return null;
    return ModuleVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  /// major имеет приоритет над minor, minor — над patch.
  @override
  int compareTo(ModuleVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(ModuleVersion other) => compareTo(other) < 0;

  bool operator <=(ModuleVersion other) => compareTo(other) <= 0;

  bool operator >(ModuleVersion other) => compareTo(other) > 0;

  bool operator >=(ModuleVersion other) => compareTo(other) >= 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is ModuleVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}