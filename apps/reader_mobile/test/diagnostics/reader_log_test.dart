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
}
