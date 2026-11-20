import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/epub_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spectacular.reader_mobile/epub_export');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(paths, null);
  });

  Future<File> source() async {
    final directory = await Directory.systemTemp.createTemp(
      'epub-export-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    return File('${directory.path}/large.epub').writeAsBytes([1, 2, 3]);
  }

  test('缓存父目录被清理后，保存与导出仍可创建互不覆盖的暂存目录', () async {
    final root = await Directory.systemTemp.createTemp('epub-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}/missing/cache');
    messenger.setMockMethodCallHandler(paths, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return cache.path;
    });
    final first = await EpubExport.createTemporaryDirectory();
    final second = await EpubExport.createTemporaryDirectory();
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
    expect(first.parent.path, cache.path);
    expect(first.path, isNot(second.path));
    final file = await File('${first.path}/edited.epub').writeAsBytes([1, 2]);
    expect(await file.readAsBytes(), [1, 2]);
  });

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

  test('下载目录导出只传原文件路径，系统返回 URI 后才报告成功', () async {
    final file = await source();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveToDownloads');
      expect(call.arguments, {
        'sourcePath': file.absolute.path,
        'fileName': '原书.epub',
      });
      return 'content://media/external/downloads/123';
    });
    expect(await EpubExport.saveToDownloads(file, fileName: '原书.epub'), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('下载目录导出报告缺失文件、取消及写入失败，不修改源文件', () async {
    final file = await source();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await EpubExport.saveToDownloads(file, fileName: '取消.epub'),
      isFalse,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'E_EXPORT_WRITE'),
    );
    await expectLater(
      EpubExport.saveToDownloads(file, fileName: '失败.epub'),
      throwsA(isA<PlatformException>()),
    );
    expect(await file.readAsBytes(), [1, 2, 3]);
    await file.delete();
    await expectLater(
      EpubExport.saveToDownloads(file, fileName: '缺失.epub'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
