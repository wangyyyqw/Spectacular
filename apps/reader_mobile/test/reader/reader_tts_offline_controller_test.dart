import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';

import '../support/reader_tts_fakes.dart';

const _settings = ReaderTtsSettings(
  mode: ReaderTtsMode.offline,
  narratorVoiceId: 'narrator',
  dialogueVoiceId: 'dialogue',
  autoTurnPage: false,
  narratorSpeed: 1.2,
  dialogueSpeed: 0.9,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('离线听书保留旁白与对白配置并按原文顺序播放', () async {
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer();
    final controller = _controller('“你好。”他说。', synthesizer, player);
    addTearDown(controller.dispose);
    await controller.start(_settings);
    expect(synthesizer.segments.map((segment) => segment.text), ['你好。', '他说。']);
    expect(synthesizer.narrator?.id, 'narrator');
    expect(synthesizer.dialogue?.id, 'dialogue');
    expect(synthesizer.settings?.dialogueSpeed, 0.9);
    expect(player.clips, hasLength(2));
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
  });

  test('对白跟随旁白时只解析一个模型', () async {
    var resolves = 0;
    final synthesizer = _FakeSynthesizer();
    final controller = ReaderTtsController(
      textSource: MemoryTtsTextSource(['旁白。“对白。”']),
      offlineSynthesizer: synthesizer,
      player: _FakePlayer(),
      resolveOfflineVoice: (id) {
        resolves++;
        return _resolveVoice(id);
      },
    );
    addTearDown(controller.dispose);
    await controller.start(_settings.copyWith(dialogueVoiceId: ''));
    expect(synthesizer.dialogue, isNull);
    expect(resolves, 1);
  });

  test('首段不等待后段合成，播放时最多提前准备一段', () async {
    final secondReady = Completer<void>();
    final firstPlayed = Completer<void>();
    final secondPlayed = Completer<void>();
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (text) =>
          text == '第二句。' ? secondReady.future : Future.value();
    final player = _FakePlayer()
      ..waitForClip = (index) => switch (index) {
        0 => firstPlayed.future,
        1 => secondPlayed.future,
        _ => Future.value(),
      };
    final controller = _controller('第一句。第二句。第三句。', synthesizer, player);
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(
      () => player.clips.length == 1 && synthesizer.segments.length == 2,
    );
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    expect(synthesizer.segments.map((segment) => segment.text), [
      '第一句。',
      '第二句。',
    ]);
    expect(controller.highlight.value, isNotNull);
    firstPlayed.complete();
    await _until(() => controller.snapshot.phase == ReaderTtsPhase.loading);
    expect(player.clips, hasLength(1));
    secondReady.complete();
    await _until(() => player.clips.length == 2);
    secondPlayed.complete();
    await task;
    expect(player.clips, hasLength(3));
  });

  test('暂停保留当前句音频，继续调用播放器恢复而非重播', () async {
    final finished = Completer<void>();
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer()..waitForClip = (_) => finished.future;
    final controller = _controller('当前句。', synthesizer, player);
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(() => player.clips.isNotEmpty);
    final range = controller.highlight.value;
    await controller.pause();
    expect(player.pauses, 1);
    expect(controller.highlight.value, range);
    await controller.resume();
    expect(player.resumes, 1);
    expect(player.clips, hasLength(1));
    expect(synthesizer.segments, hasLength(1));
    finished.complete();
    await task;
  });

  test('改变语速在下一句生效，并丢弃旧参数预合成片段', () async {
    final first = Completer<void>();
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer()
      ..waitForClip = (index) => index == 0 ? first.future : Future.value();
    final controller = _controller('当前句。下一句。', synthesizer, player);
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(
      () => player.clips.length == 1 && synthesizer.segments.length == 2,
    );
    controller.updateSettings(
      _settings.copyWith(narratorSpeed: 1.8, volume: 0.3),
    );
    first.complete();
    await task;
    expect(
      synthesizer.requestSettings.map((settings) => settings.narratorSpeed),
      [1.2, 1.2, 1.8],
    );
    expect(player.volumes, [1, 0.3]);
  });

  test('离线后段失败只从失败片段回退系统，不重读已播放正文', () async {
    final system = FakeSystemTts()..install();
    addTearDown(system.close);
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (text) =>
          text == '第二句。' ? Future.error(StateError('合成失败')) : Future.value();
    final controller = _controller('第一句。第二句。第三句。', synthesizer, _FakePlayer());
    addTearDown(controller.dispose);
    await controller.start(_settings);
    expect(system.spoken, ['第二句。', '第三句。']);
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    expect(controller.snapshot.mode, ReaderTtsMode.system);
    expect(controller.settings.mode, ReaderTtsMode.offline);
  });
}

ReaderTtsController _controller(
  String text,
  _FakeSynthesizer synthesizer,
  _FakePlayer player,
) => ReaderTtsController(
  textSource: MemoryTtsTextSource([text]),
  offlineSynthesizer: synthesizer,
  player: player,
  resolveOfflineVoice: _resolveVoice,
);

Future<ReaderOfflineVoiceInstance?> _resolveVoice(String id) async =>
    id != 'narrator' && id != 'dialogue'
    ? null
    : ReaderOfflineVoiceInstance(
        id: id,
        rootPath: '/tmp/$id',
        model: const ReaderOfflineVoiceModel(
          kind: ReaderOfflineModelKind.vits,
          model: 'model.onnx',
          tokens: 'tokens.txt',
        ),
      );

class _FakeSynthesizer implements ReaderOfflineTtsSynthesizer {
  final segments = <ReaderTtsSegment>[];
  final requestSettings = <ReaderTtsSettings>[];
  ReaderOfflineVoiceInstance? narrator;
  ReaderOfflineVoiceInstance? dialogue;
  ReaderTtsSettings? settings;
  Future<void> Function(String text)? beforeSynthesis;

  @override
  Stream<ReaderTtsClip> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async* {
    this.segments.addAll(segments);
    requestSettings.add(settings);
    this.narrator = narrator;
    this.dialogue = dialogue;
    this.settings = settings;
    for (var i = 0; i < segments.length; i++) {
      await beforeSynthesis?.call(segments[i].text);
      yield ReaderTtsClip(
        wav: Uint8List.fromList([0]),
        sampleRate: 22050,
        sampleCount: 22050,
        index: i,
      );
    }
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _FakePlayer implements ReaderTtsPlayer {
  final clips = <ReaderTtsClip>[];
  final volumes = <double>[];
  Future<void> Function(int index)? waitForClip;
  Completer<void>? _stop;
  void Function()? _onStarted;
  int pauses = 0;
  int resumes = 0;

  @override
  Future<void> play(
    ReaderTtsClip clip, {
    double volume = 1,
    void Function()? onStarted,
    void Function(Duration position)? onPosition,
  }) async {
    final index = clips.length;
    clips.add(clip);
    volumes.add(volume);
    _onStarted = onStarted;
    onStarted?.call();
    final stop = _stop = Completer<void>();
    await Future.any([
      waitForClip?.call(index) ?? Future<void>.value(),
      stop.future,
    ]);
    if (identical(_stop, stop)) _stop = null;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> resume() async {
    resumes++;
    _onStarted?.call();
  }

  @override
  Future<void> stop() async {
    if (_stop?.isCompleted == false) _stop!.complete();
    _onStarted = null;
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '预期的播放状态没有出现');
}
