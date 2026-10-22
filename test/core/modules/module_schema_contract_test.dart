/// Контракт версии схемы данных модуля (Этап 9.1).
///
/// ## Что здесь проверяется
///
/// Этап 9.1 заводит три вещи, на которые дальше опирается: поле
/// `schemaVersion` в манифесте, контракт шага `ModuleDataMigration` и
/// маркер `schema:version` в `ModuleStorage`. Каждая выглядит простой
/// и при этом может тихо сломать чужой код, поэтому проверяется не
/// «поле существует», а поведение, от которого зависят следующие
/// подэтапы:
///
/// 1. старый манифест без поля читается как версия 1 — иначе каждый
///    модуль, написанный до Этапа 9.1, потребовал бы миграции;
/// 2. версия схемы и версия кода не путаются — иначе решение «нужна ли
///    миграция» принималось бы по строке `X.Y.Z`;
/// 3. маркер переживает backup/restore/snapshot вместе с данными, а
///    не живёт отдельной жизнью;
/// 4. чтение маркера не пишет его — иначе no-op перестаёт быть no-op;
/// 5. испорченный маркер — исключение, а не тихая единица.
library module_schema_contract_test;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_schema_marker.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/accounts/accounts_module.dart';
import 'package:personal_hub/modules/schedule/schedule_migrator.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';

/// Хранилище в памяти, считающее ВСЕ записи.
///
/// Счётчики — не удобство, а требование: проверка «чтение маркера
/// ничего не пишет» без них невозможна, потому что отсутствие вызова
/// setString ничего не доказывает — вызова могло не быть просто потому,
/// что никто не смотрел.
class _CountingStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};
  int setCalls = 0;
  int removeCalls = 0;

  void reset() {
    setCalls = 0;
    removeCalls = 0;
  }

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    setCalls++;
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    removeCalls++;
    data.remove(key);
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

ModuleManifest _manifest({
  String id = 'demo',
  String version = '1.0.0',
  int? schemaVersion,
}) {
  return ModuleManifest.fromJson(<String, dynamic>{
    'id': id,
    'name': 'Демо',
    'version': version,
    'apiVersion': 1,
    'author': 'Test',
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
  });
}

void main() {
  group('Манифест: schemaVersion', () {
    test('отсутствующее поле означает исходную версию 1', () {
      expect(_manifest().schemaVersion, 1);
      expect(_manifest().schemaVersion, kInitialModuleSchemaVersion);
    });

    test('явная единица читается как 1', () {
      expect(_manifest(schemaVersion: 1).schemaVersion, 1);
    });

    test('явная двойка читается как 2', () {
      expect(_manifest(schemaVersion: 2).schemaVersion, 2);
    });

    test('большие версии не обрезаются', () {
      expect(_manifest(schemaVersion: 17).schemaVersion, 17);
    });

    test('старый манифест без поля остаётся валидным', () {
      // Ровно тот JSON, какой был в .phm до Этапа 9.1. Ни одного нового
      // поля — разбор обязан пройти, иначе старые пакеты перестали бы
      // открываться вообще.
      final parsed = ModuleManifest.fromJson(jsonDecode('''
        {
          "id": "legacy",
          "name": "Старый",
          "version": "0.9.0",
          "apiVersion": 1,
          "author": "Author",
          "description": "пакет до Этапа 9.1",
          "permissions": ["core:search"],
          "dependencies": [],
          "icon": ""
        }
      ''') as Map<String, dynamic>);

      expect(parsed.id, 'legacy');
      expect(parsed.version, '0.9.0');
      expect(parsed.schemaVersion, 1);
    });

    test('JSON round-trip сохраняет значение', () {
      for (final version in <int>[1, 2, 7, 100]) {
        final restored = ModuleManifest.fromJson(_manifest(schemaVersion: version).toJson());
        expect(restored.schemaVersion, version,
            reason: 'schemaVersion $version потерялся при обходе через JSON');
      }
    });

    test('schemaVersion 1 не пишется в JSON — байты .phm не меняются', () {
      // Обратная совместимость проверяется именно на выводе: модуль с
      // умолчанием должен сериализоваться ровно так же, как до Этапа
      // 9.1, иначе каждый существующий экспорт стал бы другим файлом.
      expect(
        _manifest(schemaVersion: 1).toJson().containsKey('schemaVersion'),
        isFalse,
      );
      expect(_manifest(schemaVersion: 2).toJson()['schemaVersion'], 2);
    });

    test('schemaVersion не путается с version кода', () {
      final manifest = _manifest(version: '3.7.1', schemaVersion: 5);
      expect(manifest.version, '3.7.1');
      expect(manifest.schemaVersion, 5);
      expect(manifest.version, isNot(manifest.schemaVersion.toString()),
          reason: 'версия кода — строка X.Y.Z, версия схемы — целое');
    });

    test('нецелое значение отвергается, а не становится единицей', () {
      // Молчаливое превращение "2" в 1 означало бы: перенос не
      // запустится, данные останутся в старой форме, а новый код будет
      // читать их как новые.
      expect(
        () => ModuleManifest.fromJson(<String, dynamic>{
          'id': 'demo',
          'name': 'Демо',
          'version': '1.0.0',
          'apiVersion': 1,
          'author': 'Test',
          'schemaVersion': '2',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('нулевая и отрицательная версия отвергаются', () {
      for (final bad in <int>[0, -1]) {
        expect(
          () => ModuleManifest.fromJson(<String, dynamic>{
            'id': 'demo',
            'name': 'Демо',
            'version': '1.0.0',
            'apiVersion': 1,
            'author': 'Test',
            'schemaVersion': bad,
          }),
          throwsA(isA<FormatException>()),
          reason: 'schemaVersion $bad не имеет смысла',
        );
      }
    });
  });

  group('Контракт шага миграции', () {
    test('модуль по умолчанию не обязан объявлять миграции', () {
      // Проверяется на настоящем модуле, а не на синтетике: если бы
      // геттер требовал переопределения, об этом узнал бы только
      // анализ всего проекта, и новый модуль сначала не собрался бы.
      expect(AccountsModule().dataMigrations, isEmpty);
    });

    test('Schedule объявляет свой шаг, а список не пуст', () {
      // Schedule — единственный модуль, чьи данные уже переносились
      // (Этап 7.2). Молчащий список означал бы, что его перенос никто
      // не видит.
      expect(ScheduleModule().dataMigrations, isNotEmpty);
    });

    test('внешний модуль не объявляет миграций', () {
      // У внешнего пакета нет Dart-кода, а шаг миграции — это код.
      // Пустой список здесь не умолчание, а следствие архитектуры.
      expect(ExternalModuleAdapter(_manifest()).dataMigrations, isEmpty);
    });

    test('объявленный шаг непрерывен: toVersion больше fromVersion', () {
      for (final migration in ScheduleModule().dataMigrations) {
        expect(migration.toVersion, greaterThan(migration.fromVersion),
            reason: 'шаг, не повышающий версию, — это откат, а не миграция');
      }
    });

    test('версия шага совпадает с заявленной в манифесте модуля', () {
      // Два независимых числа — «куда переносим» в шаге и «какой формы
      // ждём данные» в манифесте. Расхождение означало бы, что данные
      // навсегда остались бы в промежуточной форме: платформа ждёт
      // одну версию, модуль переносит в другую.
      final module = ScheduleModule();
      expect(
        module.manifest.schemaVersion,
        module.dataMigrations.last.toVersion,
      );
    });

    test('ключ маркера у модуля не свой, а платформенный', () {
      // Владелец маркера должен быть один. Собственный литерал в
      // модуле означал бы второй источник правды, который разошёлся
      // бы с платформенным при первом же нестандартном значении.
      expect(ScheduleMigrator.schemaVersionKey, ModuleSchemaMarker.key);
    });
  });

  group('Маркер schema:version', () {
    test('ключ маркера принадлежит платформе', () {
      expect(ModuleSchemaMarker.key, 'schema:version');
    });

    test('отсутствие маркера означает версию 1', () async {
      expect(await ModuleSchemaMarker.read(_CountingStorage()), 1);
    });

    test('отсутствие маркера НЕ создаёт запись', () async {
      // Ключевое свойство чтения: иначе «узнать текущую версию,
      // ничего не меняя» оставляло бы в хранилище запись, и сравнение
      // «менялись ли данные» перестало бы работать.
      final storage = _CountingStorage();
      await ModuleSchemaMarker.read(storage);
      expect(storage.setCalls, 0);
      expect(storage.data, isEmpty);
    });

    test('"1" читается как 1', () async {
      final storage = _CountingStorage();
      await storage.setString(ModuleSchemaMarker.key, '1');
      expect(await ModuleSchemaMarker.read(storage), 1);
    });

    test('"2" читается как 2', () async {
      final storage = _CountingStorage();
      await storage.setString(ModuleSchemaMarker.key, '2');
      expect(await ModuleSchemaMarker.read(storage), 2);
    });

    test('write пишет строку, а не число', () async {
      // ModuleStorage хранит строки, и разбор не должен зависеть от
      // того, как именно записано число.
      final storage = _CountingStorage();
      await ModuleSchemaMarker.write(storage, 3);
      expect(storage.data[ModuleSchemaMarker.key], '3');
      expect(await ModuleSchemaMarker.read(storage), 3);
    });

    test('пробелы вокруг числа не мешают', () async {
      final storage = _CountingStorage();
      await storage.setString(ModuleSchemaMarker.key, ' 4 ');
      expect(await ModuleSchemaMarker.read(storage), 4);
    });

    test('испорченный маркер — исключение, а не тихая единица', () async {
      for (final bad in <String>['abc', '', '  ', '1.5', '2.0', 'null']) {
        final storage = _CountingStorage();
        await storage.setString(ModuleSchemaMarker.key, bad);

        await expectLater(
          ModuleSchemaMarker.read(storage),
          throwsA(isA<ModuleSchemaMarkerException>()),
          reason: 'значение "$bad" не должно молча превращаться в 1: '
              'тогда перенос не запустится, а новый код будет читать '
              'старые данные как новые',
        );
      }
    });

    test('нулевой и отрицательный маркер отвергаются', () async {
      for (final bad in <String>['0', '-3']) {
        final storage = _CountingStorage();
        await storage.setString(ModuleSchemaMarker.key, bad);
        await expectLater(
          ModuleSchemaMarker.read(storage),
          throwsA(isA<ModuleSchemaMarkerException>()),
        );
      }
    });

    test('write отказывается записывать неположительную версию', () async {
      // Иначе миграция, решившая записать 0, создала бы маркер,
      // который следующий же read() отвергнет, то есть заведомо
      // испорченное состояние.
      final storage = _CountingStorage();
      await expectLater(
        ModuleSchemaMarker.write(storage, 0),
        throwsA(isA<ModuleSchemaMarkerException>()),
      );
      expect(storage.setCalls, 0, reason: 'отказ должен произойти до записи');
    });

    test('маркер лежит в ModuleStorage, а не в отдельном хранилище', () async {
      // Единственное место, где маркер существует: обычный ключ
      // хранилища модуля. Отдельная коллекция или поле в
      // ModuleStateRecord дали бы источник правды, который не едет
      // вместе с данными при backup, restore и rollback.
      final storage = _CountingStorage();
      await ModuleSchemaMarker.write(storage, 2);
      expect(await storage.keys(), <String>[ModuleSchemaMarker.key]);
    });
  });

  group('No-op: совпадающие версии не пишут в хранилище', () {
    test('чтение при совпадении версий не пишет ничего', () async {
      // Сценарий, ради которого существует весь Stage 9.1: модуль,
      // чья форма данных уже совпадает с заявленной, не должен
      // оставлять следов. Любая запись здесь означала бы, что
      // приложение меняет данные модуля без причины.
      final storage = _CountingStorage();
      await ModuleSchemaMarker.write(storage, 2);
      storage.reset();

      final manifest = _manifest(schemaVersion: 2);
      final current = await ModuleSchemaMarker.read(storage);

      expect(current, manifest.schemaVersion,
          reason: 'форма данных уже совпадает с заявленной');
      expect(storage.setCalls, 0);
      expect(storage.removeCalls, 0);
    });

    test('модуль без миграций и со схемой 1 не трогает хранилище', () async {
      final storage = _CountingStorage();
      await storage.setString('event:1', '{"id":"1"}');
      storage.reset();

      final module = AccountsModule();
      final current = await ModuleSchemaMarker.read(storage);

      expect(module.dataMigrations, isEmpty);
      expect(module.manifest.schemaVersion, current,
          reason: 'AccountsModule ничего не переносил и не объявляет иного');
      expect(storage.setCalls, 0);
      expect(storage.removeCalls, 0);
    });
  });

  group('Схема и версия кода — разные вещи', () {
    test('две версии кода с одной схемой не считаются конфликтом схем', () {
      // Именно это различие обязана уметь делать проверка обновления,
      // когда появится (Этапы 9.3–9.4): «сменился код» и «сменилась
      // форма данных» — разные вещи.
      final first = _manifest(version: '1.0.0', schemaVersion: 2);
      final second = _manifest(version: '1.1.0', schemaVersion: 2);

      expect(second.version, isNot(first.version));
      expect(second.schemaVersion, first.schemaVersion);
    });

    test('одна версия кода с разной схемой — обратный случай', () {
      final first = _manifest(version: '1.0.0', schemaVersion: 1);
      final second = _manifest(version: '1.0.0', schemaVersion: 2);

      expect(second.version, first.version);
      expect(second.schemaVersion, isNot(first.schemaVersion));
    });

    test('версия кода модуля не попадает в маркер схемы', () async {
      // Граница, о которой легко забыть: installedVersion и
      // manifest.version описывают КОД, а форма данных — нет. Маркер
      // хранит только целое число переносов.
      final storage = _CountingStorage();
      await ModuleSchemaMarker.write(storage, 1);

      final raw = storage.data[ModuleSchemaMarker.key]!;
      expect(raw, '1');
      expect(raw, isNot(contains('.')),
          reason: 'маркер не должен содержать версию кода вида X.Y.Z');
    });
  });
}
