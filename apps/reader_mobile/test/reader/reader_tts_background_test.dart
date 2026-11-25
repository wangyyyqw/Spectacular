import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_background.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';

import '../support/reader_tts_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSystemTts system;
  late FakeTtsBackground background;
  setUp(() {
    system = FakeSystemTts()..install();
    background = FakeTtsBackground()..install();
  });
  tearDown(() {
    system.close();
    background.close();
  });

  test('服务启动尚未回调时通知栏暂停仍生效，不在就绪后自动出声', () async {
    final ready = Completer<void>();
    background.starting = ready.future;
    system.autoComplete = false;
    final controller = _controller();
    addTearDown(controller.dispose);
    final task = controller.start(ReaderTtsSettings.defaults);
    await _until(
      () => background.methods.any((call) => call.method == 'start'),
    );
    await background.emit('pause');
    expect(controller.paused, isTrue);
    ready.complete();
    await _until(() => background.state?['phase'] == 'paused');
    expect(system.spoken, isEmpty);
    await background.emit('play');
    await _until(() => system.spoken.isNotEmpty);
    await controller.stop();
    await task;
  });

  test('服务启动期间从通知结束听书，就绪后释放服务且不朗读', () async {
    final ready = Completer<void>();
    background.starting = ready.future;
    final controller = _controller();
    addTearDown(controller.dispose);
    final task = controller.start(ReaderTtsSettings.defaults);
    await _until(
      () => background.methods.any((call) => call.method == 'start'),
    );
    final stopped = background.emit('stop');
    await _until(() => controller.snapshot.phase == ReaderTtsPhase.idle);
    ready.complete();
    await Future.wait([stopped, task]);
    expect(background.active, isFalse);
    expect(system.spoken, isEmpty);
    expect(background.methods.last.method, 'stop');
  });

  test('服务就绪后才朗读，媒体命令保留偏移且字词回调不重复刷新通知', () async {
    system.autoComplete = false;
    system.onSpeak = (_) async {
      expect(background.active, isTrue);
      return 1;
    };
    final controller = _controller();
    addTearDown(controller.dispose);
    final task = controller.start(const ReaderTtsSettings(autoTurnPage: false));
    await _until(() => system.spoken.isNotEmpty);
    expect(controller.supportsBackgroundPlayback, isTrue);
    await system.progress(1, 2);
    await Future<void>.delayed(Duration.zero);
    final updates = background.methods
        .where((call) => call.method == 'update')
        .length;
    await system.progress(2, 3);
    await Future<void>.delayed(Duration.zero);
    expect(
      background.methods.where((call) => call.method == 'update'),
      hasLength(updates),
    );
    expect(background.state, {'phase': 'playing', 'chapterTitle': '第 1 章'});
    await background.emit('pause');
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    await background.emit('play');
    await _until(() => system.spoken.length == 2);
    expect(system.spoken.last, '丙丁。');
    await background.emit('stop');
    await task;
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    expect(controller.highlight.value, isNull);
    expect(background.active, isFalse);
  });

  test('前台服务启动失败时不播放、不推进原文，并明确报告失败', () async {
    background.startError = PlatformException(code: 'playback_start_failed');
    final source = MemoryTtsTextSource(['甲乙丙丁。']);
    final controller = _controller(source: source);
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect(controller.snapshot.error, isA<PlatformException>());
    expect(system.spoken, isEmpty);
    expect(source.advances, 0);
    expect(background.active, isFalse);
  });

  test('恢复时被拒绝音频焦点，仍保持暂停且不跳过当前片段', () async {
    system.autoComplete = false;
    final controller = _controller();
    addTearDown(controller.dispose);
    final task = controller.start(ReaderTtsSettings.defaults);
    await _until(() => system.spoken.isNotEmpty);
    await controller.pause();
    final position = controller.position;
    background.activationError = PlatformException(code: 'audio_focus_denied');
    await expectLater(controller.resume(), throwsA(isA<PlatformException>()));
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    expect(controller.position, position);
    expect(system.spoken, hasLength(1));
    await controller.stop();
    await task;
  });

  for (final fails in [false, true]) {
    test(fails ? '朗读失败释放后台会话' : '书末完成释放后台会话', () async {
      if (fails) system.speakResult = 0;
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.start(ReaderTtsSettings.defaults);
      expect(
        controller.snapshot.phase,
        fails ? ReaderTtsPhase.failed : ReaderTtsPhase.completed,
      );
      expect(background.active, isFalse);
      expect(
        background.methods.where((call) => call.method == 'stop'),
        hasLength(1),
      );
    });
  }

  test('启动服务期间结束会话，晚到的启动不会留下后台播放或开始朗读', () async {
    final ready = Completer<void>();
    background.starting = ready.future;
    final controller = _controller();
    addTearDown(controller.dispose);
    final task = controller.start(ReaderTtsSettings.defaults);
    await _until(
      () => background.methods.any((call) => call.method == 'start'),
    );
    final stopped = controller.stop();
    ready.complete();
    await Future.wait([task, stopped]);
    expect(system.spoken, isEmpty);
    expect(background.active, isFalse);
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    expect(background.methods.last.method, 'stop');
  });
}

ReaderTtsController _controller({MemoryTtsTextSource? source}) =>
    ReaderTtsController(
      textSource: source ?? MemoryTtsTextSource(['甲乙丙丁。下一句。']),
      backgroundPlayback: ReaderTtsBackgroundPlayback(bookTitle: '后台听书测试'),
    );

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '预期的后台听书状态没有出现');
}
