import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_playback_sheet.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/reader_tts_fakes.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('听书设置可切换系统 TTS 与离线模型且不再显示语速滑杆', (tester) async {
    final root = Directory.systemTemp.createTempSync('reader-tts-offline-');
    final voices = ReaderTtsVoiceStore(rootDirectory: root);
    final system = FakeSystemTts()..install();
    final background = FakeTtsBackground()..install();
    addTearDown(() {
      system.close();
      background.close();
      voices.close();
      root.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: const ['听书离线模式测试正文。']),
          bookId: 'tts-offline-mode',
          store: MemoryReaderProgressStore(),
          ttsVoiceStore: voices,
          settings: const ReaderSettings(
            tts: ReaderTtsSettings(mode: ReaderTtsMode.offline),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tts')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('tts-apply-settings')),
    );

    expect(find.byType(SegmentedButton<ReaderTtsMode>), findsOneWidget);
    expect(find.text('系统 TTS'), findsOneWidget);
    expect(find.text('离线模型'), findsOneWidget);
    expect(find.text('旁白语速'), findsNothing);
    expect(find.text('对白语速'), findsNothing);
    expect(find.text('尚未下载离线音色。下载后可使用离线模型，模型较大，建议连接 Wi-Fi。'), findsOneWidget);
    expect(
      system.methods.where((call) => call.method == 'getVoices'),
      isNotEmpty,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('系统 TTS'));
    await tester.pumpAndSettle();
    expect(find.text('音色'), findsOneWidget);
    expect(find.text('系统默认音色'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('离线模型'));
    await tester.pumpAndSettle();
    expect(find.text('尚未下载离线音色。下载后可使用离线模型，模型较大，建议连接 Wi-Fi。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬浮听书条显示封面、音色、语速、定时、暂停与取消', (tester) async {
    final player = _FlowPlayer();
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['悬浮控制测试正文。']),
      offlineSynthesizer: _FlowSynthesizer(),
      player: player,
      resolveOfflineVoice: _resolveVoice,
    );
    const settings = ReaderTtsSettings(
      mode: ReaderTtsMode.offline,
      narratorVoiceId: 'offline',
      autoTurnPage: false,
    );
    final running = controller.start(settings);
    await tester.pump();
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);

    var voiceTaps = 0;
    var speedTaps = 0;
    var timerTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReaderTtsPlaybackSheet(
              controller: controller,
              onVoice: () async {
                voiceTaps++;
              },
              onSpeed: () async {
                speedTaps++;
              },
              onTimer: () async {
                timerTaps++;
              },
              onCancel: controller.stop,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tts-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-speed')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-cancel')), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(5));
    expect(find.byKey(const ValueKey('tts-start')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tts-voice')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tts-speed')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tts-timer')));
    await tester.pump();
    expect(voiceTaps, 1);
    expect(speedTaps, 1);
    expect(timerTaps, 1);
    await tester.tap(find.byKey(const ValueKey('tts-pause')));
    await tester.pump();
    expect(controller.paused, isTrue);
    expect(find.byKey(const ValueKey('tts-resume')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tts-resume')));
    await tester.pump();
    expect(controller.paused, isFalse);
    expect(player.resumes, 1);
    await tester.tap(find.byKey(const ValueKey('tts-cancel')));
    await tester.pump();
    await running;
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  testWidgets('定时选项到期后暂停朗读', (tester) async {
    final root = Directory.systemTemp.createTempSync('reader-tts-timer-');
    final voices = ReaderTtsVoiceStore(rootDirectory: root);
    final background = FakeTtsBackground()..install();
    addTearDown(() {
      background.close();
      voices.close();
      root.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: const ['定时暂停测试正文。']),
          bookId: 'tts-timer',
          store: MemoryReaderProgressStore(),
          ttsVoiceStore: voices,
          settings: const ReaderSettings(
            tts: ReaderTtsSettings(mode: ReaderTtsMode.offline),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tts')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('tts-apply-settings')),
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('tts-apply-settings'))),
    ).pop();
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ReaderTtsPlaybackSheet>(find.byType(ReaderTtsPlaybackSheet))
        .controller;
    controller.state.value = const ReaderTtsSnapshot(
      phase: ReaderTtsPhase.playing,
      mode: ReaderTtsMode.offline,
    );
    await tester.pump();
    // 浮条跟随阅读菜单显示，重新展开菜单才能操作。
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tts-timer')));
    await pumpReaderUntil(tester, find.text('15 分钟后暂停'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 分钟后暂停'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('定时 · 15 分钟'), findsOneWidget);

    await tester.pump(const Duration(minutes: 15));
    await tester.pumpAndSettle();
    expect(controller.paused, isTrue);
    expect(find.byKey(const ValueKey('tts-resume')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('准备状态可识别且仍可暂停和取消', (tester) async {
    final ready = Completer<void>();
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['准备状态测试。']),
      offlineSynthesizer: _FlowSynthesizer()..ready = ready.future,
      player: _FlowPlayer(),
      resolveOfflineVoice: _resolveVoice,
    );
    final running = controller.start(
      const ReaderTtsSettings(
        mode: ReaderTtsMode.offline,
        narratorVoiceId: 'offline',
        autoTurnPage: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderTtsPlaybackSheet(
            controller: controller,
            onVoice: () async {},
            onSpeed: () async {},
            onTimer: () async {},
            onCancel: controller.stop,
          ),
        ),
      ),
    );
    expect(find.byTooltip('正在准备语音，可暂停'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tts-pause')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('继续'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tts-cancel')));
    await tester.pump();
    ready.complete();
    await running;
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  testWidgets('失败保留控制条，一键重试当前句且不锁住暂停取消', (tester) async {
    final synthesizer = _FlowSynthesizer()..failText = '第二句。';
    final player = _FlowPlayer();
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['第一句。第二句。']),
      offlineSynthesizer: synthesizer,
      player: player,
      resolveOfflineVoice: _resolveVoice,
    );
    final running = controller.start(
      const ReaderTtsSettings(
        mode: ReaderTtsMode.offline,
        narratorVoiceId: 'offline',
        autoTurnPage: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderTtsPlaybackSheet(
            controller: controller,
            onVoice: () async {},
            onSpeed: () async {},
            onTimer: () async {},
            onCancel: controller.stop,
          ),
        ),
      ),
    );
    player.complete();
    await tester.pump();
    await running;
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect(find.byTooltip('重试当前段'), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-cancel')), findsOneWidget);
    synthesizer.failText = null;
    await tester.tap(find.byKey(const ValueKey('tts-retry')));
    await tester.pump();
    expect(controller.snapshot.text, '第二句。');
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    expect(synthesizer.spoken, ['第一句。', '第二句。']);
    await tester.tap(find.byKey(const ValueKey('tts-pause')));
    await tester.pump();
    expect(controller.paused, isTrue);
    await tester.tap(find.byKey(const ValueKey('tts-cancel')));
    await tester.pump();
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
    expect(find.byKey(const ValueKey('tts-retry')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });
}

Future<ReaderOfflineVoiceInstance?> _resolveVoice(String id) async =>
    id != 'offline'
    ? null
    : ReaderOfflineVoiceInstance(
        id: id,
        rootPath: '/tmp/offline',
        model: const ReaderOfflineVoiceModel(
          kind: ReaderOfflineModelKind.vits,
          model: 'model.onnx',
          tokens: 'tokens.txt',
        ),
      );

class _FlowSynthesizer implements ReaderOfflineTtsSynthesizer {
  Future<void>? ready;
  String? failText;
  final spoken = <String>[];

  @override
  Future<void> prepare(ReaderOfflineVoiceInstance voice) async {}

  @override
  Stream<ReaderTtsClip> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async* {
    await ready;
    for (var index = 0; index < segments.length; index++) {
      if (segments[index].text == failText) throw StateError('合成暂时失败');
      spoken.add(segments[index].text);
      yield ReaderTtsClip(
        wav: Uint8List(0),
        sampleRate: 22050,
        sampleCount: 22050,
        index: index,
      );
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FlowPlayer implements ReaderTtsPlayer {
  Completer<void>? _finished;
  void Function()? _onStarted;
  int resumes = 0;

  void complete() {
    if (_finished?.isCompleted == false) _finished!.complete();
  }

  @override
  Future<void> play(
    ReaderTtsClip clip, {
    double volume = 1,
    void Function()? onStarted,
    void Function(Duration position)? onPosition,
  }) async {
    _onStarted = onStarted;
    onStarted?.call();
    final finished = _finished = Completer<void>();
    await finished.future;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {
    resumes++;
    _onStarted?.call();
  }

  @override
  Future<void> stop() async {
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
    _onStarted = null;
  }

  @override
  Future<void> dispose() => stop();
}
