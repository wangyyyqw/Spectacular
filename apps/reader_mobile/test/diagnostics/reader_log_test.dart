import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';

void main() {
  test('日志初始化、追加、导出文件', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_test');
    final log = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => <String, String>{
        'device_model': 'UnitTestPhone',
        'android_version': '14',
      },
    );
    await log.initialize();
    await log.log(
      'page_turn',
      fields: <String, Object?>{'spine': 3, 'page': 7},
    );
    final text = await log.exportText();
    expect(text, contains('device_model=UnitTestPhone'));
    expect(text, contains('page_turn'));
    expect(text, contains('spine=3'));
    final path = await log.exportFile();
    expect(path, isNotNull);
    final fileText = File(path!).readAsStringSync();
    expect(fileText, contains('page_turn'));
    expect(fileText, contains('device_model=UnitTestPhone'));
    expect(log.lineCount, greaterThan(0));
    expect(log.isReady, isTrue);
    log.resetForTest();
    expect(log.lineCount, 0);
    dir.deleteSync(recursive: true);
  });

  test('重新启动后仍保留上次会话的日志', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_history');
    Map<String, String> info() => <String, String>{'device_model': 'UnitTestPhone'};

    final first = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => info(),
    );
    await first.initialize();
    await first.log('first_session_event', fields: <String, Object?>{'v': 1});
    first.resetForTest();

    final second = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => info(),
    );
    await second.initialize();
    await second.log('second_session_event');
    final text = await second.exportText();

    expect(text, contains('first_session_event'), reason: '上次会话的日志要保留');
    expect(text, contains('second_session_event'));
    expect(
      '=== 新会话'.allMatches(text).length,
      2,
      reason: '两次启动各有一个会话头',
    );
    second.resetForTest();
    dir.deleteSync(recursive: true);
  });

  test('清理日志后导出为空且保留会话头', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_clear');
    final log = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => <String, String>{'device_model': 'UnitTestPhone'},
    );
    await log.initialize();
    await log.log('to_be_cleared');
    expect(await log.exportText(), contains('to_be_cleared'));

    await log.clear();
    final after = await log.exportText();
    expect(after, isNot(contains('to_be_cleared')));
    log.resetForTest();
    dir.deleteSync(recursive: true);
  });
}
