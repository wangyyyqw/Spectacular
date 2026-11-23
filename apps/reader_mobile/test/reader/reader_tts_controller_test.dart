import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('系统朗读按句完成后自动翻页，读完最后一页停止', () async {
    final spoken = <String>[];
    var page = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
    final controller = ReaderTtsController(
      textProvider: () async => ['第一句。第二句！', '末页。'][page],
      nextPage: () async => page++ == 0,
    );
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(spoken, ['第一句。', '第二句！', '末页。']);
    expect(page, 2);
    expect(controller.speaking, isFalse);
  });

  test('系统拒绝朗读时提示错误且不自动翻页', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'speak' ? 0 : 1,
    );
    var turns = 0;
    Object? error;
    final controller = ReaderTtsController(
      textProvider: () async => '有正文。',
      nextPage: () async {
        turns++;
        return false;
      },
    )..onError = (value) => error = value;
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(error, isA<StateError>());
    expect(turns, 0);
  });

  test('重新开始后旧的朗读完成回调不能触发翻页', () async {
    final oldSpeech = Completer<int>();
    final newSpeech = Completer<int>();
    final oldStarted = Completer<void>();
    final newStarted = Completer<void>();
    var speaks = 0;
    var turns = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'speak') return 1;
      if (speaks++ == 0) {
        oldStarted.complete();
        return oldSpeech.future;
      }
      newStarted.complete();
      return newSpeech.future;
    });
    final controller = ReaderTtsController(
      textProvider: () async => '正文。',
      nextPage: () async {
        turns++;
        return false;
      },
    );
    addTearDown(controller.dispose);
    final oldTask = controller.start(ReaderTtsSettings.defaults);
    await oldStarted.future;
    final newTask = controller.start(
      const ReaderTtsSettings(autoTurnPage: false),
    );
    await newStarted.future;
    oldSpeech.complete(1);
    await oldTask;
    expect(turns, 0);
    expect(controller.speaking, isTrue);
    await controller.stop();
    newSpeech.complete(1);
    await newTask;
    expect(turns, 0);
    expect(controller.speaking, isFalse);
  });

  testWidgets('系统引擎崩溃不回调时退出听书并提示，不自动翻页', (tester) async {
    final pending = Completer<int>();
    var stops = 0;
    var turns = 0;
    Object? error;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') return pending.future;
      if (call.method == 'stop') {
        stops++;
        if (!pending.isCompleted) pending.complete(0);
      }
      return 1;
    });
    final controller = ReaderTtsController(
      textProvider: () async => '引擎无响应。',
      nextPage: () async {
        turns++;
        return false;
      },
    )..onError = (value) => error = value;
    addTearDown(controller.dispose);
    final task = controller.start(ReaderTtsSettings.defaults);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await task;
    expect(error.toString(), contains('系统语音引擎无响应'));
    expect(stops, 1);
    expect(turns, 0);
    expect(controller.speaking, isFalse);
  });
}
