import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/epub_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spectacular.reader_mobile/epub_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<File> source() async {
    final directory = await Directory.systemTemp.createTemp(
      'epub-export-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    return File('${directory.path}/large.epub').writeAsBytes([1, 2, 3]);
  }

  test('Android 只发送源文件路径，SAF content URI 表示复制完成', () async {
    final file = await source();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveFile');
      expect(call.arguments, {
        'sourcePath': file.absolute.path,
        'fileName': '编辑后的书.epub',
      });
      return 'content://documents/exported';
    });
    expect(await EpubExport.save(file, fileName: '编辑后的书.epub'), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('取消返回 false，写入失败继续向调用方报告，源文件保留', () async {
    final file = await source();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await EpubExport.save(file, fileName: '取消.epub'), isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'E_EXPORT_WRITE'),
    );
    await expectLater(
      EpubExport.save(file, fileName: '失败.epub'),
      throwsA(isA<PlatformException>()),
    );
    expect(await file.exists(), isTrue);
  });
}
