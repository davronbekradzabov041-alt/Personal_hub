/// Версия модуля: разбор и сравнение (Этап 8.1-А).
///
/// Сравнение версий — то, на чём держится решение «обновлять ли», и
/// ошибка в нём выглядит как «приложение предлагает откатить модуль на
/// старую версию». Поэтому проверяются не только очевидные случаи
/// (0.9.0 < 0.10.0), но и то, что порядок полей именно такой.
library module_version_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_version.dart';

void main() {
  group('ModuleVersion: разбор', () {
    test('разбирает major.minor.patch', () {
      final version = ModuleVersion.tryParse('2.10.3');

      expect(version, isNotNull);
      expect(version!.major, 2);
      expect(version.minor, 10);
      expect(version.patch, 3);
      expect(version.toString(), '2.10.3');
    });

    test('отклоняет то, что не X.Y.Z', () {
      // Список не из прихоти: каждый пункт — реальный способ сломать
      // сравнение версий (или, наоборот, молча разрешить пакет,
      // которому нельзя доверять).
      final rejected = <String>[
        '',// пусто
        '1', // нет minor/patch
        '1.0', // нет patch
        '1.0.0.0', // лишний сегмент
        'v1.0.0', // префикс
        '1.0.0-beta', // суффикс
        '1.0.x', // не цифра
        '1..0', // пустой сегмент
        '.1.0', // пустой сегмент
        '1.0.', // пустой сегмент
        'latest', // не версия вовсе
        '-1.0.0', // отрицательное
        ' 1.0.0-beta', // пробелы не спасают суффикс
      ];

      for (final raw in rejected) {
        expect(
          ModuleVersion.tryParse(raw),
          isNull,
          reason: '«$raw» не должен разбираться как версия',
        );
      }
    });

    test('пробелы вокруг версии допускаются', () {
      // Манифест может прийти с пробелами из редактора пакета; это не
      // повод отказывать в обновлении.
      expect(ModuleVersion.tryParse('  1.4.2  '), const ModuleVersion(major: 1, minor: 4, patch: 2));
    });

    test('одни и те же поля дают равные версии', () {
      expect(
        ModuleVersion.tryParse('1.2.3'),
        ModuleVersion.tryParse('01.002.0003'),
      );
    });
  });

  group('ModuleVersion: сравнение', () {
    test('major важнее minor и patch', () {
      expect(_v('2.0.0') > _v('1.9.9'), isTrue);
      expect(_v('1.9.9') < _v('2.0.0'), isTrue);
    });

    test('minor важнее patch', () {
      expect(_v('1.10.0') > _v('1.9.9'), isTrue);
      expect(_v('1.9.9') < _v('1.10.0'), isTrue);
    });

    test('10.0 больше 9.0 — лексикографическое сравнение строк тут ошибается', () {
      // Именно этот случай ломал сравнение строк: '0.9.0' > '0.10.0'
      // по алфавиту.
      expect('0.10.0'.compareTo('0.9.0') < 0, isTrue,
          reason: 'строки сравниваются неверно');
      expect(_v('0.10.0') > _v('0.9.0'), isTrue,
          reason: 'числовое сравнение обязано давать обратный результат');
    });

    test('равные версии равны во всех отношениях', () {
      final a = _v('3.4.5');
      final b = _v('3.4.5');

      expect(a.compareTo(b), 0);
      expect(a == b, isTrue);
      expect(a >= b, isTrue);
      expect(a <= b, isTrue);
      expect(a < b, isFalse);
      expect(a > b, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('сортировка по возрастанию', () {
      final versions = ['1.10.0', '1.2.0', '0.9.9', '2.0.0', '1.2.1', '10.0.0']
          .map((raw) => _v(raw))
          .toList()
        ..sort();

      expect(
        versions.map((v) => v.toString()),
        ['0.9.9', '1.2.0', '1.2.1', '1.10.0', '2.0.0', '10.0.0'],
      );
    });
  });

  group('ModuleVersion: правило формата одно на всех', () {
    test('pattern совпадает с тем, что принимает парсер', () {
      // ManifestValidator и ModuleManager проверяют формат версии
      // своим регулярным выражением. Если бы ModuleVersion разбирал
      // другие строки, «валидная версия» означала бы разное в разных
      // местах — и обновление могло бы отклонить пакет, который
      // установка приняла бы (или наоборот).
      for (final raw in ['1.0.0', '10.20.30', '0.0.0']) {
        expect(ModuleVersion.pattern.hasMatch(raw), isTrue, reason: raw);
        expect(ModuleVersion.tryParse(raw), isNotNull, reason: raw);
      }
      for (final raw in ['1.0', '1.0.0-rc1', 'v2.0.0', '1.0.0.0']) {
        expect(ModuleVersion.pattern.hasMatch(raw), isFalse, reason: raw);
        expect(ModuleVersion.tryParse(raw), isNull, reason: raw);
      }
    });
  });
}

ModuleVersion _v(String raw) => ModuleVersion.tryParse(raw)!;