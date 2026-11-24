import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';

import '../support/reader_tts_fakes.dart';

void main() {
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
  int resumes = 0;

  @override
  Stream<void> get onPlayerComplete => complete.stream;
  @override
  Stream<Duration> get onPositionChanged => positions.stream;
  @override
  Future<void> setSource(Source source) async {
    sources.add(source);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await positions.close();
    await complete.close();
  }
}
