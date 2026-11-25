import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';

import '../support/reader_tts_fakes.dart';

void main() {
  test('后台不提供界面帧时仍按真实播放位置更新，暂停和停止不再轮询', () async {
    final native = _AudioPlayer();
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    final received = <Duration>[];
    final playing = player.play(_clip(), onPosition: received.add);
    try {
      await _until(() => native.resumes == 1);
      native.currentPosition = const Duration(milliseconds: 18);
      // 仅推进真实时间，不请求 Flutter 帧；复现熄屏后的播放环境。
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(received, contains(const Duration(milliseconds: 18)));
      await player.pause();
      final reads = native.positionReads;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(native.positionReads, reads);
      await player.resume();
      native.currentPosition = const Duration(milliseconds: 25);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(received.last, const Duration(milliseconds: 25));
      await player.stop();
      await playing;
      final stoppedReads = native.positionReads;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(native.positionReads, stoppedReads);
    } finally {
      await player.dispose();
    }
  });

  test('音源尚未就绪时暂停再继续，只在就绪后真正起播一次', () async {
    final ready = Completer<void>();
    final native = _AudioPlayer()..sourceReady = ready.future;
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    var starts = 0;
    final playing = player.play(_clip(), onStarted: () => starts++);
    await _until(() => native.sources.isNotEmpty);
    await player.pause();
    await player.resume();
    expect(native.resumes, 0);
    expect(starts, 0);
    ready.complete();
    await _until(() => starts == 1);
    expect(native.resumes, 1);
    native.complete.add(null);
    await playing;
    await player.dispose();
  });

  test('取消准备后立即重新播放，旧音源完成不能覆盖新音源或出声', () async {
    final ready = Completer<void>();
    final native = _AudioPlayer()..sourceReady = ready.future;
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    var oldStarts = 0;
    var newStarts = 0;
    final old = player.play(_clip(), onStarted: () => oldStarts++);
    await _until(() => native.sources.isNotEmpty);
    await player.stop();
    final current = player.play(_clip(), onStarted: () => newStarts++);
    await Future<void>.delayed(Duration.zero);
    expect(native.sources, hasLength(1));
    ready.complete();
    await _until(() => newStarts == 1);
    expect(native.sources, hasLength(2));
    expect(oldStarts, 0);
    expect(native.resumes, 1);
    native.complete.add(null);
    await Future.wait([old, current]);
    await player.dispose();
  });

  test('长时间暂停不消耗播放超时，继续复用音频及位置', () async {
    final native = _AudioPlayer();
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    var completed = false;
    Object? error;
    final task = player
        .play(_clip(), volume: 0.4)
        .then<void>(
          (_) => completed = true,
          onError: (Object value) => error = value,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await player.pause();
    await Future<void>.delayed(const Duration(milliseconds: 2150));
    expect(completed, isFalse);
    expect(error, isNull);
    await player.resume();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(error, isNull);
    expect(native.sources, hasLength(1));
    expect(native.volumes, [0.4]);
    expect(native.resumes, 2);
    native.complete.add(null);
    await task;
    expect(completed, isTrue);
    await player.dispose();
  });

  test('播放超时明确失败，不能当作成功而跳过正文', () async {
    final native = _AudioPlayer();
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    Object? error;
    final task = player
        .play(_clip())
        .then<void>(
          (_) => fail('超时音频不能成功完成'),
          onError: (Object value) => error = value,
        );
    await task;
    expect(error, isA<StateError>());
    await player.dispose();
  });

  test('后台服务管理焦点时，离线播放器使用语音媒体且不再抢占焦点', () async {
    final native = _AudioPlayer();
    final player = AudioplayersReaderTtsPlayer(
      audioPlayer: native,
      externalAudioFocus: true,
    );
    for (var i = 0; i < 2; i++) {
      final task = player.play(_clip());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      native.complete.add(null);
      await task;
    }
    expect(native.contexts, hasLength(1));
    expect(
      native.contexts.single.android.contentType,
      AndroidContentType.speech,
    );
    expect(native.contexts.single.android.usageType, AndroidUsageType.media);
    expect(native.contexts.single.android.audioFocus, AndroidAudioFocus.none);
    await player.dispose();
  });

  test('跨页音频拼接仅裁剪接缝静音，实际采样点与 WAV 长度一致', () {
    final first = pcmTtsClip([
      ...List.filled(20, 0),
      ...List.filled(40, 8000),
      ...List.filled(80, 12),
    ]);
    final last = pcmTtsClip([
      ...List.filled(90, 12),
      ...List.filled(40, -8000),
      ...List.filled(30, 0),
    ]);
    final joined = ReaderTtsClip.join([first, last]);
    expect(joined.segmentStarts, [0, 70]);
    expect(joined.sampleCount, 150);
    expect(joined.wav.length, 44 + 150 * 2);
    final wav = ByteData.sublistView(joined.wav);
    expect(wav.getUint32(4, Endian.little), 36 + 150 * 2);
    expect(wav.getUint32(40, Endian.little), 150 * 2);
    expect(
      [for (var i = 0; i < 150; i++) wav.getInt16(44 + i * 2, Endian.little)],
      [
        ...List.filled(20, 0),
        ...List.filled(40, 8000),
        ...List.filled(20, 12),
        ...List.filled(40, -8000),
        ...List.filled(30, 0),
      ],
    );
    expect(identical(ReaderTtsClip.join([first]), first), isTrue);
  });

  test('真实播放位置在暂停与结束后不再转发，继续复用同一音频', () async {
    final native = _AudioPlayer();
    final player = AudioplayersReaderTtsPlayer(audioPlayer: native);
    final received = <Duration>[];
    final task = player.play(_clip(), onPosition: received.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    native.positions.add(const Duration(milliseconds: 1));
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    native.positions.add(const Duration(milliseconds: 2));
    await Future<void>.delayed(Duration.zero);
    await player.resume();
    native.positions.add(const Duration(milliseconds: 3));
    await Future<void>.delayed(Duration.zero);
    native.complete.add(null);
    await task;
    native.positions.add(const Duration(milliseconds: 4));
    await Future<void>.delayed(Duration.zero);
    expect(received.map((position) => position.inMilliseconds), [1, 3]);
    expect(native.sources, hasLength(1));
    await player.dispose();
  });
}

ReaderTtsClip _clip() => ReaderTtsClip(
  wav: Uint8List.fromList([0]),
  sampleRate: 1000,
  sampleCount: 30,
  index: 0,
);

class _AudioPlayer extends Fake implements AudioPlayer {
  final complete = StreamController<void>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final sources = <Source>[];
  final volumes = <double>[];
  final contexts = <AudioContext>[];
  Future<void>? sourceReady;
  int resumes = 0;
  PositionUpdater? _updater;
  StreamSubscription<Duration>? _positionSubscription;
  Duration currentPosition = Duration.zero;
  int positionReads = 0;

  @override
  set positionUpdater(PositionUpdater? updater) {
    _updater = updater;
    _positionSubscription = updater?.positionStream.listen(positions.add);
  }

  @override
  Future<Duration?> getCurrentPosition() async {
    positionReads++;
    return currentPosition;
  }

  @override
  Stream<void> get onPlayerComplete => complete.stream;
  @override
  Stream<Duration> get onPositionChanged => positions.stream;
  @override
  Future<void> setSource(Source source) async {
    sources.add(source);
    await sourceReady;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setAudioContext(AudioContext context) async {
    contexts.add(context);
  }

  @override
  Future<void> pause() async {
    _updater?.stop();
  }

  @override
  Future<void> resume() async {
    resumes++;
    _updater?.start();
  }

  @override
  Future<void> stop() async {
    _updater?.stop();
  }

  @override
  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _updater?.dispose();
    await positions.close();
    await complete.close();
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '预期的音源状态没有出现');
}
