/// In-memory реализация ModuleStorage для тестов.
library test_storage;

import 'package:personal_hub/core/modules/module_storage.dart';

class InMemoryModuleStorage implements ModuleStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<List<String>> keys() async => _data.keys.toList();

  void clear() => _data.clear();

  Map<String, String> get snapshot => Map.unmodifiable(_data);
}