import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';
import 'package:reader_mobile/reader/reader_offline_tts_worker.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_background.dart';
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

  test('预热与停止重启复用模型工作线程，旧合成丢弃且退出释放', () async {
    final worker = _FakeWorker();
    var opens = 0;
    final synthesizer = SherpaReaderOfflineTtsSynthesizer(
      openWorker: () async {
        opens++;
        return worker;
      },
    );
    final voice = (await _resolveVoice('narrator'))!;
    await synthesizer.prepare(voice);
    expect(worker.prepares, 1);
    final ready = worker.ready = Completer<void>();
    Future<List<ReaderTtsClip>> generate() => synthesizer
        .synthesize(
          segments: ReaderTtsSegmentation.split('复用音色。'),
          narrator: voice,
          dialogue: null,
          settings: _settings,
        )
        .toList();
    final cancelled = generate();
    await _until(() => worker.generations == 1);
    await synthesizer.stop();
    expect(worker.closes, 0);
    ready.complete();
    expect(await cancelled, isEmpty);
    expect(await generate(), hasLength(1));
    expect(opens, 1);
    await synthesizer.dispose();
    expect(worker.closes, 1);
  });

  test('预热只加载已选旁白，不朗读、不启动后台会话或改变状态', () async {
    final background = FakeTtsBackground()..install();
    addTearDown(background.close);
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer();
    final controller = _controller(
      '预热不能朗读这句。',
      synthesizer,
      player,
      backgroundPlayback: ReaderTtsBackgroundPlayback(bookTitle: '预热测试'),
    );
    addTearDown(controller.dispose);
    await controller.prepare(_settings);
    expect(synthesizer.prepared.map((voice) => voice.id), ['narrator']);
    expect(synthesizer.segments, isEmpty);
    expect(player.clips, isEmpty);
    expect(background.methods, isEmpty);
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
  });

  test('长首句先播自然短语，后半句准备不阻塞起播且原文不丢失', () async {
    const lead = '这是准备首先开始朗读的一小段，';
    final text = '$lead${'后续的长句内容' * 12}。末句。';
    final ready = Completer<void>();
    final finished = Completer<void>();
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (text) =>
          text == lead ? Future.value() : ready.future;
    final player = _FakePlayer()
      ..waitForClip = (index) => index == 0 ? finished.future : Future.value();
    final controller = _controller(text, synthesizer, player);
    addTearDown(controller.dispose);
    final running = controller.start(_settings);
    expect(controller.snapshot.phase, ReaderTtsPhase.loading);
    await _until(() => player.clips.isNotEmpty);
    expect(controller.snapshot.text, lead);
    expect(controller.highlight.value!.endCfi, endsWith(':${lead.length})'));
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    ready.complete();
    finished.complete();
    await running;
    expect(synthesizer.segments.map((segment) => segment.text).join(), text);
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
  });

  test('准备中暂停不会提前出声，取消后晚到的合成结果不能播放', () async {
    final ready = Completer<void>();
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (_) => ready.future;
    final player = _FakePlayer();
    final controller = _controller('尚未合成的正文。', synthesizer, player);
    addTearDown(controller.dispose);
    final running = controller.start(_settings);
    await _until(() => synthesizer.segments.isNotEmpty);
    await controller.pause();
    ready.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    expect(player.clips, isEmpty);
    await controller.stop();
    await running;
    expect(player.clips, isEmpty);
    expect(controller.snapshot.phase, ReaderTtsPhase.idle);
  });

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

  test('离线伴听的通知栏暂停继续复用音频，完成后结束后台会话', () async {
    final background = FakeTtsBackground()..install();
    addTearDown(background.close);
    final finished = Completer<void>();
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (_) async => expect(background.active, isTrue);
    final player = _FakePlayer()..waitForClip = (_) => finished.future;
    final controller = _controller(
      '当前句。',
      synthesizer,
      player,
      backgroundPlayback: ReaderTtsBackgroundPlayback(bookTitle: '离线后台听书'),
    );
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(() => player.clips.isNotEmpty);
    await background.emit('pause');
    expect(player.pauses, 1);
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    await background.emit('play');
    expect(player.resumes, 1);
    expect(player.clips, hasLength(1));
    expect(synthesizer.segments, hasLength(1));
    finished.complete();
    await task;
    expect(controller.snapshot.phase, ReaderTtsPhase.completed);
    expect(background.active, isFalse);
  });

  test('改变语速立即重备下一句，当前音频与位置保持不变', () async {
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
    await _until(() => synthesizer.requestSettings.length == 3);
    expect(player.clips, hasLength(1));
    expect(controller.snapshot.text, '当前句。');
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    first.complete();
    await task;
    expect(
      synthesizer.requestSettings.map((settings) => settings.narratorSpeed),
      [1.2, 1.2, 1.8],
    );
    expect(player.volumes, [1, 0.3]);
  });

  test('只改音量不重合成下一句，播放时采用新音量', () async {
    final first = Completer<void>();
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer()
      ..waitForClip = (index) => index == 0 ? first.future : Future.value();
    final controller = _controller('当前句。下一句。', synthesizer, player);
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(() => synthesizer.segments.length == 2);
    controller.updateSettings(_settings.copyWith(volume: 0.3));
    first.complete();
    await task;
    expect(synthesizer.segments.map((segment) => segment.text), [
      '当前句。',
      '下一句。',
    ]);
    expect(player.volumes, [1, 0.3]);
  });

  test('暂停时切换音色立即预备后句，旧结果晚到不会覆盖新音色', () async {
    final first = Completer<void>();
    final stale = Completer<void>();
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (text) =>
          text == '下一句。' ? stale.future : Future.value();
    final player = _FakePlayer()
      ..waitForClip = (index) => index == 0 ? first.future : Future.value();
    final controller = _controller('当前句。下一句。', synthesizer, player);
    addTearDown(controller.dispose);
    final task = controller.start(_settings);
    await _until(() => synthesizer.segments.length == 2);
    await controller.pause();
    synthesizer.beforeSynthesis = (_) => Future.value();
    controller.updateSettings(
      _settings.copyWith(narratorVoiceId: 'dialogue', dialogueVoiceId: ''),
    );
    await _until(() => synthesizer.requestSettings.length == 3);
    expect(controller.paused, isTrue);
    expect(player.clips, hasLength(1));
    stale.complete();
    await controller.resume();
    first.complete();
    await task;
    expect(synthesizer.requestSettings.last.narratorVoiceId, 'dialogue');
    expect(synthesizer.requestSettings, hasLength(3));
    expect(player.clips, hasLength(2));
    expect(String.fromCharCodes(player.clips.last.wav), 'dialogue');
  });

  test('离线合成失败不回退系统语音，保留失败片段状态', () async {
    final system = FakeSystemTts()..install();
    addTearDown(system.close);
    final synthesizer = _FakeSynthesizer()
      ..beforeSynthesis = (text) =>
          text == '第二句。' ? Future.error(StateError('合成失败')) : Future.value();
    final controller = _controller('第一句。第二句。第三句。', synthesizer, _FakePlayer());
    addTearDown(controller.dispose);
    await controller.start(_settings);
    expect(system.spoken, isEmpty);
    expect(controller.snapshot.phase, ReaderTtsPhase.failed);
    expect(controller.snapshot.error, isA<StateError>());
    expect(controller.snapshot.mode, ReaderTtsMode.offline);
    expect(controller.settings.mode, ReaderTtsMode.offline);
  });
}

ReaderTtsController _controller(
  String text,
  _FakeSynthesizer synthesizer,
  _FakePlayer player, {
  ReaderTtsBackgroundPlayback? backgroundPlayback,
}) => ReaderTtsController(
  textSource: MemoryTtsTextSource([text]),
  offlineSynthesizer: synthesizer,
  player: player,
  resolveOfflineVoice: _resolveVoice,
  backgroundPlayback: backgroundPlayback,
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
  final prepared = <ReaderOfflineVoiceInstance>[];
  final segments = <ReaderTtsSegment>[];
  final requestSettings = <ReaderTtsSettings>[];
  ReaderOfflineVoiceInstance? narrator;
  ReaderOfflineVoiceInstance? dialogue;
  ReaderTtsSettings? settings;
  Future<void> Function(String text)? beforeSynthesis;

  @override
  Future<void> prepare(ReaderOfflineVoiceInstance voice) async {
    prepared.add(voice);
  }

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
        wav: Uint8List.fromList(narrator.id.codeUnits),
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

class _FakeWorker extends Fake implements ReaderOfflineTtsWorker {
  int prepares = 0;
  int generations = 0;
  int closes = 0;
  Completer<void>? ready;

  @override
  Future<void> prepare(Map<String, Object?> input) async {
    prepares++;
  }

  @override
  Future<Map<String, Object?>> generate(Map<String, Object?> input) async {
    generations++;
    await ready?.future;
    return {'wav': Uint8List(0), 'sampleRate': 22050, 'sampleCount': 22050};
  }

  @override
  Future<void> close() async {
    closes++;
  }
}
