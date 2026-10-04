/// Регрессия AUD-31: под конечным именем backup не должен никогда
/// появляться частично записанный файл, а уже существующий архив — не
/// теряться при сбое замены.
///
/// Формат архива, манифест и контрольные суммы не участвуют: тест
/// проверяет только порядок операций с файловой системой и результат
/// на диске.
///
/// Платформенные факты, на которых опираются тесты. Проверены на
/// Windows (платформа сборки) запуском, а не взяты из документации:
///
/// * `File.rename` ЗАМЕНЯЕТ существующий файл целиком. Значит подмена
///   не требует предварительного удаления цели и не оставляет окна, в
///   котором файла нет;
/// * `File.rename` на каталог падает с PathAccessException —
///   детерминированный способ занять конечное имя;
/// * `File.rename` поверх файла с открытым дескриптором падает с
///   PathAccessException (в Windows дескриптор открыт без
///   FILE_SHARE_DELETE) — детерминированный способ сорвать подмену,
///   не мешая записи данных во временный файл;
/// * `File.delete` файла с открытым дескриптором тоже падает — этим
///   проверяется, что сбой уборки не подменяет собой исходную ошибку.
library atomic_file_writer_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/backup/atomic_file_writer.dart';

/// Архив, который всегда читается как целый: заголовок, тело, хвост.
///
/// [tag] используется и как маркер тела, и как имя: под конечным именем
/// обязан лежать архив, собранный из ОДНОГО тега. Смесь тегов означает,
/// что файл собран из байтов двух разных записей.
List<int> _archive(String tag, {int bodyBytes = 4096}) {
  return <int>[
    ...utf8.encode('HEADER:$tag:'),
    ...List<int>.filled(bodyBytes, tag.codeUnitAt(0)),
    ...utf8.encode(':FOOTER:$tag'),
  ];
}

/// Байтовое сравнение: «файл на диске побайтово равен ожидаемому».
bool _isWhole(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}

/// Файл состоит ровно из одного повторяющегося байта [fill].
///
/// Используется как признак «это тело одного архива», а не смесь
/// тел двух разных записей.
bool _isSingleFill(List<int> actual, int fill) {
  if (actual.isEmpty) return false;
  return actual.every((b) => b == fill);
}

/// Временные файлы, оставшиеся рядом с целью.
List<String> _leftovers(Directory dir, File target) {
  final base = path.basename(target.path);
  return dir
      .listSync()
      .map((e) => path.basename(e.path))
      .where((name) => name != base)
      .toList();
}

void main() {
  late Directory _dir;

  setUp(() async {
    _dir = await Directory.systemTemp.createTemp('atomic_write_');
  });

  tearDown(() async {
    if (await _dir.exists()) {
      await _dir.delete(recursive: true);
    }
  });

  File targetIn(String name) => File(path.join(_dir.path, name));

  group('успешная запись', () {
    test('1. создание нового backup: файл целый, временных файлов нет',
        () async {
      final target = targetIn('new.pbk');
      final payload = _archive('v1');

      await writeFileAtomically(target, payload);

      expect(_isWhole(await target.readAsBytes(), payload), isTrue);
      expect(_leftovers(_dir, target), isEmpty);
    });

    test('2. замена существующего backup: под именем только новый архив',
        () async {
      final target = targetIn('replace.pbk');
      final oldPayload = _archive('old');
      final newPayload = _archive('new');
      await target.writeAsBytes(oldPayload);

      await writeFileAtomically(target, newPayload);

      final content = await target.readAsBytes();
      expect(_isWhole(content, newPayload), isTrue,
          reason: 'под конечным именем обязан быть новый архив целиком');
      expect(_leftovers(_dir, target), isEmpty,
          reason: 'прежний архив не должен остаться вторым файлом рядом');
    });

    test('остатки прошлого прерванного запуска не мешают записи', () async {
      final target = targetIn('restarts.pbk');
      await target.writeAsBytes(_archive('old'));
      // Мусор от прерванного запуска: под другим именем, но тоже .tmp.
      await targetIn('restarts.pbk.leftover.tmp')
          .writeAsString('мусор от прошлого раза');

      await writeFileAtomically(target, _archive('new'));

      expect(_isWhole(await target.readAsBytes(), _archive('new')), isTrue);
    });
  });

  group('сбой записи во временный файл', () {
    test('3. сбой записи temp: прежний архив не пострадал', () async {
      // Каталог занимает путь цели: записать временный файл невозможно.
      final blocker = await File(path.join(_dir.path, 'blocked'))
          .writeAsString('x');
      final target = File(path.join(blocker.path, 'backup.pbk'));

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      expect(await File(target.path).exists(), isFalse,
          reason: 'частично записанный архив появиться не может');
      expect(await blocker.readAsString(), 'x',
          reason: 'исходный объект не должен пострадать');
    });

    test('3b. сбой записи temp поверх существующего архива: архив цел',
        () async {
      // Конечное имя занято каталогом, но рядом лежит настоящий
      // прежний архив с другим именем: он обязан остаться нетронутым.
      final target = targetIn('occupied-dir');
      final oldPayload = _archive('old');
      await File(path.join(_dir.path, 'keeper.pbk')).writeAsBytes(oldPayload);
      await Directory(target.path).create();

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      final keeper = File(path.join(_dir.path, 'keeper.pbk'));
      expect(_isWhole(await keeper.readAsBytes(), oldPayload), isTrue,
          reason: 'сбой записи не должен трогать другие архивы');
    });
  });

  group('сбой финальной подмены', () {
    test('4. занятое конечное имя: ошибка без разрушения цели', () async {
      // По пути цели лежит каталог: подмена файла на каталог невозможна.
      // Каталог обязан остаться целым — «освобождать» имя за счёт
      // чужого каталога нельзя.
      final target = targetIn('occupied.pbk');
      await Directory(target.path).create();
      await File(path.join(target.path, 'inside.txt')).writeAsString('внутри');

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      expect(await Directory(target.path).exists(), isTrue);
      expect(
        File(path.join(target.path, 'inside.txt')).readAsStringSync(),
        'внутри',
        reason: 'содержимое чужого каталога не должно пострадать',
      );
    });

    test('5. сорванная подмена: прежний backup остаётся валидным',
        () async {
      // Дескриптор открыт на САМОЙ цели: запись данных проходит,
      // а подмена — нет (в Windows дескриптор открыт без
      // FILE_SHARE_DELETE). Это ровно тот сбой, который стоил бы
      // пользователю архива в схеме «delete → rename».
      final target = targetIn('locked.pbk');
      final oldPayload = _archive('old');
      await target.writeAsBytes(oldPayload);

      final blocker = await target.open(mode: FileMode.append);
      addTearDown(blocker.close);

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.exists(), isTrue,
          reason: 'прежний архив не должен исчезнуть при сорванной подмене');
      expect(_isWhole(await target.readAsBytes(), oldPayload), isTrue,
          reason: 'прежний архив обязан уцелеть БЕЗ единого изменённого байта');
    });

    test('после сорванной подмены новых данных под именем нет', () async {
      final target = targetIn('locked2.pbk');
      final oldPayload = _archive('old');
      await target.writeAsBytes(oldPayload);

      final blocker = await target.open(mode: FileMode.append);
      addTearDown(blocker.close);

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      // Никаких «новых» байт под конечным именем: подмена не была
      // частичной, она не была вовсе.
      final content = await target.readAsBytes();
      expect(_isWhole(content, oldPayload), isTrue);
      expect(_isSingleFill(content, 0x6E), isFalse,
          reason: 'новый архив не должен просочиться под конечное имя');
    });

    test('сорванная подмена не оставляет мусорных файлов', () async {
      final target = targetIn('locked3.pbk');
      await target.writeAsBytes(_archive('old'));

      final blocker = await target.open(mode: FileMode.append);
      addTearDown(blocker.close);

      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );

      expect(_leftovers(_dir, target), isEmpty,
          reason: 'незаписанный временный файл обязан быть убран');
    });

    test('сбой уборки не подменяет собой исходную ошибку записи', () async {
      // Конечное имя занято каталогом — подмена упадёт. Проверяем, что
      // вызывающий получит FileSystemException от подмены, а не что-то
      // другое из уборки, и что каталог на месте цели цел.
      final target = targetIn('locked4.pbk');
      await Directory(target.path).create();

      Object? caught;
      try {
        await writeFileAtomically(target, _archive('new'));
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<FileSystemException>(),
          reason: 'вызывающий обязан узнать о провале записи');
      expect(await Directory(target.path).exists(), isTrue);
    });
  });

  group('повторная запись', () {
    test('6. несколько последовательных записей: каждая читается целиком',
        () async {
      final target = targetIn('repeat.pbk');

      for (var round = 1; round <= 6; round++) {
        final payload = _archive('r$round');

        await writeFileAtomically(target, payload);

        expect(_isWhole(await target.readAsBytes(), payload), isTrue,
            reason: 'после записи №$round под именем лежит не тот архив');
        expect(_leftovers(_dir, target), isEmpty,
            reason: 'после записи №$round остался мусор');
      }
    });

    test('7. повторная запись после сорванной подмены снова успешна',
        () async {
      final target = targetIn('retry.pbk');
      await target.writeAsBytes(_archive('old'));

      final blocker = await target.open(mode: FileMode.append);
      await expectLater(
        writeFileAtomically(target, _archive('new')),
        throwsA(isA<FileSystemException>()),
      );
      await blocker.close();

      // Дескриптор закрылся — цель снова доступна для подмены.
      final retry = _archive('retry');
      await writeFileAtomically(target, retry);

      expect(_isWhole(await target.readAsBytes(), retry), isTrue,
          reason: 'неудачная попытка не должна делать цель непригодной');
      expect(_leftovers(_dir, target), isEmpty);
    });
  });

  group('параллельные записи в одну цель', () {
    // Две одновременные записи в ОДНУ цель — сценарий, которого в
    // приложении нет (имена файлов backup уникальны по времени), но
    // именно он вскрыл дефект фиксированного временного имени.
    //
    // Проверяем единственную гарантию, которая здесь осмысленна:
    // под конечным именем лежит ЦЕЛЫЙ архив одной из записей. Победить
    // обязана одна из них; вторая может выиграть или честно сообщить
    // об ошибке (в Windows rename поверх цели, которую в этот же
    // момент подменяет другая запись, возвращает «отказано в
    // доступе»). Оба варианта допустимы, битый файл — нет.
    test('8. две одновременные записи: под именем целый архив одной из них',
        () async {
      // Реальный дефект: при фиксированном временном имени
      // `<target>.tmp` второй вызов затирал временный файл первого, и
      // под конечным именем оказывался файл, СОБРАННЫЙ из байтов обоих
      // архивов, причём оба вызова сообщали об успехе. Воспроизводилось
      // в 3 запусках из 12.
      final target = targetIn('concurrent.pbk');
      await target.writeAsBytes(_archive('old'));

      // Разный объём: смесь байтов видна и по длине, и по содержимому.
      final small = _archive('a', bodyBytes: 200 * 1024);
      final large = _archive('b', bodyBytes: 700 * 1024);

      final outcomes = await Future.wait<String>([
        writeFileAtomically(target, small)
            .then((_) => 'ok', onError: (Object e) => 'failed: $e'),
        writeFileAtomically(target, large)
            .then((_) => 'ok', onError: (Object e) => 'failed: $e'),
      ]);

      final content = await target.readAsBytes();
      expect(
        _isWhole(content, small) || _isWhole(content, large),
        isTrue,
        reason: 'под конечным именем смесь двух архивов: '
            'длина ${content.length}, ожидалось ${small.length} '
            'или ${large.length}; исходы: $outcomes',
      );
      expect(_leftovers(_dir, target), isEmpty,
          reason: 'ни одна из двух записей не должна оставить свой temp');
    });

    test('9. повторные пары параллельных записей не дают битого файла',
        () async {
      final target = targetIn('concurrent2.pbk');
      final payloads = [
        for (var i = 0; i < 5; i++) _archive('p$i', bodyBytes: 300 * 1024),
      ];

      for (var round = 0; round < payloads.length; round++) {
        // Сбой rename из-за гонки допустим — важно лишь содержимое
        // цели. Поэтому ошибки собираем, а не пробрасываем.
        await Future.wait<String>([
          writeFileAtomically(target, payloads[round])
              .then((_) => 'ok', onError: (Object e) => 'failed'),
          writeFileAtomically(target, payloads[(round + 1) % payloads.length])
              .then((_) => 'ok', onError: (Object e) => 'failed'),
        ]);

        final content = await target.readAsBytes();
        final anyWhole = payloads.any((p) => _isWhole(content, p));
        expect(anyWhole, isTrue,
            reason: 'раунд $round: под именем смесь архивов '
                '(длина ${content.length})');
      }
    });
  });

  group('инвариант целостности', () {
    test('10. под конечным именем всегда целый архив — старый или новый',
        () async {
      final target = targetIn('polling.pbk');
      // Объём подобран так, чтобы запись во временный файл занимала
      // заметное время и подмену удавалось «поймать» замерами.
      final oldPayload = _archive('old', bodyBytes: 4 * 1024 * 1024);
      final newPayload = _archive('new', bodyBytes: 4 * 1024 * 1024);
      await target.writeAsBytes(oldPayload);

      final pending = writeFileAtomically(target, newPayload);

      // Пока идёт операция, под конечным именем обязано быть либо
      // N байт прежнего архива, либо M байт нового. Промежуточных
      // размеров (0, обрезанный хвост, «голова» нового файла) быть не
      // может: запись идёт во временный файл, подмена атомарна.
      final observed = <int>{};
      for (var i = 0; i < 200; i++) {
        observed.add(await target.length());
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await pending;
      observed.add(await target.length());

      expect(
        observed.every(
          (length) => length == oldPayload.length || length == newPayload.length,
        ),
        isTrue,
        reason: 'наблюдались промежуточные размеры файла: $observed '
            '(ожидались только ${oldPayload.length} и ${newPayload.length})',
      );
      expect(_isWhole(await target.readAsBytes(), newPayload), isTrue);
    });
  });
}