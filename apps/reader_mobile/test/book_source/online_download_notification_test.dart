import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/online_download_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.spectacular.reader_mobile/online_download',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('准备、章节、保存和结束通知按顺序发送，完成状态不会被旧进度覆盖', () async {
    final first = Completer<void>();
    final started = Completer<void>();
    final calls = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments as Map);
      if (calls.length == 1) {
        started.complete();
        await first.future;
      }
      return null;
    });
    final notification = OnlineDownloadNotification('测试书');
    addTearDown(notification.dispose);
    final preparing = notification.update(0, 0, '准备');
    await started.future;
    final chapters = notification.update(1, 2, '下载章节');
    final saving = notification.update(0, 0, '保存书架');
    final done = notification.update(0, 0, '已保存到书架', done: true);
    first.complete();
    await Future.wait([preparing, chapters, saving, done]);
    expect(calls.map((call) => call['message']), [
      '准备',
      '下载章节',
      '保存书架',
      '已保存到书架',
    ]);
    expect(calls.last['done'], isTrue);
    expect(calls.map((call) => call['id']).toSet(), {notification.id});
  });

  test('通知取消只作用于对应任务，结束后忽略旧取消事件', () async {
    final first = OnlineDownloadNotification('第一本');
    final second = OnlineDownloadNotification('第二本');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Future<void> cancel(int id) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('cancel', id)),
        (_) {},
      );
    }

    await cancel(first.id);
    expect(first.cancelled, isTrue);
    expect(second.cancelled, isFalse);
    second.dispose();
    await cancel(second.id);
    expect(second.cancelled, isFalse);
  });
}
