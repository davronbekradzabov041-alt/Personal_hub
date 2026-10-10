import 'dart:math';

/// Простая генерация UUID v4 без внешних зависимостей.
///
/// Использует `Random.secure()` с системным источником энтропии.
/// Формат: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (RFC 4122 v4).
String generateUuidV4() {
  final random = Random.secure();
  final bytes = <int>[];
  for (var i = 0; i < 16; i++) {
    bytes.add(random.nextInt(256));
  }

  // version (4) в битах 4-7 байта 6
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // variant (10) в битах 6-7 байта 8
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}