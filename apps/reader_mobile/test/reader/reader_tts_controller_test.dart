import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';

import '../support/reader_tts_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSystemTts system;
  setUp(() {
    system = FakeSystemTts()..install();
  });
  tearDown(() => system.close());

  test('系统朗读按原文顺序续读，书末完成并清除高亮', () async {
    final source = MemoryTtsTextSource(['第一句。第二句！', '末页。']);
    final controller = ReaderTtsController(textSource: source);
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(system.spoken, ['第一句。', '第二句！', '末页。']);
    expect(source.advances, 2);
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    expect(controller.highlight.value, isNull);
  });

  test('系统拒绝朗读时提示错误且不推进原文', () async {
    system.speakResult = 0;
    final source = MemoryTtsTextSource(['有正文。', '不应朗读。']);
    final controller = ReaderTtsController(textSource: source);
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(controller.snapshot.error, isA<StateError>());
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect(source.advances, 0);
  });

  testWidgets('系统接受朗读但未开始时明确失败，重试仍从当前片段开始', (tester) async {
    system
      ..autoStart = false
      ..autoComplete = false;
    final source = MemoryTtsTextSource(['当前片段。下一片段。']);
    final controller = ReaderTtsController(textSource: source);
    try {
      const settings = ReaderTtsSettings(autoTurnPage: false);
      final task = controller.start(settings);
      await tester.pump();
      expect(system.spoken, ['当前片段。']);
      await tester.pump(const Duration(seconds: 15));
      expect(controller.snapshot.phase, ReaderTtsPhase.failed);
      expect('${controller.snapshot.error}', contains('未响应'));
      expect(source.advances, 0);
      expect(system.spoken, ['当前片段。']);
      await task;
      system
        ..autoStart = true
        ..autoComplete = true;
      await controller.retry(settings);
      expect(system.spoken, ['当前片段。', '当前片段。', '下一片段。']);
      expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    } finally {
      await controller.dispose();
    }
  });

  testWidgets('启动等待在暂停时取消，继续后已开始的长句不被启动超时中断', (tester) async {
    system
      ..autoStart = false
      ..autoComplete = false;
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['需要继续的正文。']),
    );
    try {
      final task = controller.start(
        const ReaderTtsSettings(autoTurnPage: false),
      );
      await tester.pump();
      expect(system.spoken, hasLength(1));
      await controller.pause();
      await tester.pump(const Duration(minutes: 1));
      expect(controller.snapshot.phase, ReaderTtsPhase.paused);
      system.autoStart = true;
      await controller.resume();
      await tester.pump();
      expect(system.spoken, hasLength(2));
      await tester.pump(const Duration(minutes: 1));
      expect(controller.snapshot.phase, ReaderTtsPhase.playing);
      await system.complete();
      await task;
      expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    } finally {
      await controller.dispose();
    }
  });

  testWidgets('系统只返回实际字词进度时也确认已开始，不错误中断朗读', (tester) async {
    system
      ..autoStart = false
      ..autoComplete = false;
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['实际正在朗读的正文。']),
    );
    try {
      final task = controller.start(
        const ReaderTtsSettings(autoTurnPage: false),
      );
      await tester.pump();
      await system.progress(1, 3);
      await tester.pump(const Duration(seconds: 15));
      expect(controller.snapshot.phase, ReaderTtsPhase.playing);
      expect(controller.highlight.value!.wordStartCfi, endsWith(':1)'));
      await system.complete();
      await task;
      expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    } finally {
      await controller.dispose();
    }
  });

  test('重新开始后旧的异步结果不能推进或清除新会话高亮', () async {
    system.autoComplete = false;
    final oldSpeech = Completer<int>();
    system.onSpeak = (_) =>
        system.spoken.length == 1 ? oldSpeech.future : Future.value(1);
    final source = MemoryTtsTextSource(['正文。']);
    final controller = ReaderTtsController(textSource: source);
    addTearDown(controller.dispose);
    final oldTask = controller.start(ReaderTtsSettings.defaults);
    await _until(() => system.spoken.length == 1);
    final newTask = controller.start(
      const ReaderTtsSettings(autoTurnPage: false),
    );
    await _until(() => system.spoken.length == 2);
    final newHighlight = controller.highlight.value;
    oldSpeech.complete(-1);
    await oldTask;
    expect(source.advances, 0);
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    expect(controller.highlight.value, newHighlight);
    await system.complete();
    await newTask;
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
  });

  test('多次暂停累计偏移并按实际字词更新高亮，不从页首重读', () async {
    system.autoComplete = false;
    final source = MemoryTtsTextSource(['甲乙丙丁。下一句。']);
    final controller = ReaderTtsController(textSource: source);
    addTearDown(controller.dispose);
    final task = controller.start(const ReaderTtsSettings(autoTurnPage: false));
    await _until(() => system.spoken.length == 1);
    await system.progress(1, 2);
    final before = controller.highlight.value;
    expect(before!.wordStartCfi, endsWith(':1)'));
    await controller.pause();
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    expect(controller.highlight.value, before);
    await controller.resume();
    await _until(() => system.spoken.length == 2);
    expect(system.spoken.last, '乙丙丁。');
    await system.progress(1, 2);
    expect(controller.highlight.value!.wordStartCfi, endsWith(':2)'));
    await controller.pause();
    await controller.resume();
    await _until(() => system.spoken.length == 3);
    expect(system.spoken.last, '丙丁。');
    await system.progress(0, 1);
    expect(controller.highlight.value!.wordStartCfi, endsWith(':2)'));
    await system.complete();
    await _until(() => system.spoken.length == 4);
    expect(system.spoken.last, '下一句。');
    await system.complete();
    await task;
    expect(source.advances, 0);
    expect(controller.highlight.value, isNull);
  });

  test('播放中查询音色不覆盖进度回调，停止后旧进度不能恢复高亮', () async {
    system.autoComplete = false;
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['重复重复。']),
    );
    addTearDown(controller.dispose);
    final task = controller.start(const ReaderTtsSettings(autoTurnPage: false));
    await _until(() => system.spoken.isNotEmpty);
    expect(await controller.loadVoices(), hasLength(1));
    await system.progress(2, 3);
    expect(controller.highlight.value!.wordStartCfi, endsWith(':2)'));
    await controller.stop();
    await system.progress(3, 4);
    await task;
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    expect(controller.highlight.value, isNull);
  });

  test('缺少中文语音时不提交朗读或错误推进位置', () async {
    system.languageAvailable = false;
    final source = MemoryTtsTextSource(['有正文。']);
    final controller = ReaderTtsController(textSource: source);
    addTearDown(controller.dispose);
    await controller.start(ReaderTtsSettings.defaults);
    expect(system.spoken, isEmpty);
    expect(source.advances, 0);
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect('${controller.snapshot.error}', contains('语音包'));
  });

  test('失败后重试保留失败片段，不重读已经完成的正文', () async {
    system.onSpeak = (text) async {
      if (text == '失败片段。') return 0;
      scheduleMicrotask(system.complete);
      return 1;
    };
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['已经读完。失败片段。后续正文。']),
    );
    addTearDown(controller.dispose);
    const settings = ReaderTtsSettings(autoTurnPage: false);
    await controller.start(settings);
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect(system.spoken, ['已经读完。', '失败片段。']);
    system.onSpeak = null;
    await controller.retry(settings);
    expect(system.spoken, ['已经读完。', '失败片段。', '失败片段。', '后续正文。']);
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
  });

  test('相邻重复句子各自从句首朗读，不沿用上一句的字词偏移', () async {
    system.autoComplete = false;
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['重复。重复。']),
    );
    addTearDown(controller.dispose);
    final task = controller.start(const ReaderTtsSettings(autoTurnPage: false));
    await _until(() => system.spoken.length == 1);
    await system.progress(2, 3);
    await system.complete();
    await _until(() => system.spoken.length == 2);
    expect(system.spoken, ['重复。', '重复。']);
    await system.complete();
    await task;
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '预期的朗读状态没有出现');
}
