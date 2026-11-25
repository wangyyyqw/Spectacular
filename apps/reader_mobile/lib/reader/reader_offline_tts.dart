import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'reader_offline_tts_worker.dart';
import 'reader_settings.dart';
import 'reader_tts_segment.dart';
import 'reader_tts_voice_store.dart';

export 'reader_tts_segment.dart';

/// 已解析到本地目录的离线音色。
class ReaderOfflineVoiceInstance {
  const ReaderOfflineVoiceInstance({
    required this.id,
    required this.rootPath,
    required this.model,
  });

  final String id;
  final String rootPath;
  final ReaderOfflineVoiceModel model;
}

/// 合成完成的一段 WAV。
class ReaderTtsClip {
  const ReaderTtsClip({
    required this.wav,
    required this.sampleRate,
    required this.sampleCount,
    required this.index,
    this.segmentStarts = const [0],
  });

  final Uint8List wav;
  final int sampleRate;
  final int sampleCount;
  final int index;

  /// 连续音频里各页片段的真实起始采样点，翻页不依赖字数估时。
  final List<int> segmentStarts;

  Duration get duration => readerTtsDuration(sampleCount, sampleRate);

  /// 同一句的跨页音频只设置一次播放器来源，去除拼接处额外的低幅静音。
  static ReaderTtsClip join(List<ReaderTtsClip> clips) {
    if (clips.length == 1) return clips.single;
    final first = clips.first;
    final pcm = BytesBuilder(copy: false);
    final starts = <int>[];
    var count = 0;
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      if (clip.sampleRate != first.sampleRate ||
          clip.wav.length != 44 + clip.sampleCount * 2) {
        throw StateError('跨页音频格式不一致，无法连续播放');
      }
      final (start, end) = _joinedSampleRange(
        clip,
        trimStart: i > 0,
        trimEnd: i + 1 < clips.length,
      );
      starts.add(count);
      pcm.add(Uint8List.sublistView(clip.wav, 44 + start * 2, 44 + end * 2));
      count += end - start;
    }
    final wav = Uint8List(44 + count * 2)
      ..setRange(0, 44, first.wav)
      ..setRange(44, 44 + count * 2, pcm.takeBytes());
    final header = ByteData.sublistView(wav);
    header.setUint32(4, 36 + count * 2, Endian.little);
    header.setUint32(40, count * 2, Endian.little);
    return ReaderTtsClip(
      wav: wav,
      sampleRate: first.sampleRate,
      sampleCount: count,
      index: first.index,
      segmentStarts: List.unmodifiable(starts),
    );
  }
}

(int, int) _joinedSampleRange(
  ReaderTtsClip clip, {
  required bool trimStart,
  required bool trimEnd,
}) {
  final pcm = ByteData.sublistView(clip.wav, 44);
  // 只裁剪接缝外缘约 -60 dB 以下的部分，各保留 10 ms，保护轻声字音。
  final padding = clip.sampleRate ~/ 100;
  var start = 0;
  var end = clip.sampleCount;
  if (trimStart) {
    while (start < end && pcm.getInt16(start * 2, Endian.little).abs() <= 32) {
      start++;
    }
    start = math.max(0, start - padding);
  }
  if (trimEnd) {
    while (end > start &&
        pcm.getInt16((end - 1) * 2, Endian.little).abs() <= 32) {
      end--;
    }
    end = math.min(clip.sampleCount, end + padding);
  }
  return (start, end);
}

/// 合成按原文顺序逐段交付，调用方负责限制预合成数量。
abstract interface class ReaderOfflineTtsSynthesizer {
  /// 只加载模型，不合成正文、不申请音频焦点。
  Future<void> prepare(ReaderOfflineVoiceInstance voice);

  Stream<ReaderTtsClip> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  });

  Future<void> stop();
  Future<void> dispose();
}

/// 阅读期间复用最多两个模型；停止取消交付，退出阅读页才释放模型。
class SherpaReaderOfflineTtsSynthesizer implements ReaderOfflineTtsSynthesizer {
  SherpaReaderOfflineTtsSynthesizer({
    Future<ReaderOfflineTtsWorker> Function()? openWorker,
  }) : _createWorker = openWorker ?? ReaderOfflineTtsWorker.open;

  final Future<ReaderOfflineTtsWorker> Function() _createWorker;
  Future<ReaderOfflineTtsWorker>? _worker;
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> prepare(ReaderOfflineVoiceInstance voice) async {
    final worker = await _openWorker();
    if (_disposed) return;
    await worker.prepare({
      'root': voice.rootPath,
      'model': voice.model.toJson(),
    });
  }

  @override
  Stream<ReaderTtsClip> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async* {
    final generation = _generation;
    final worker = await _openWorker();
    for (var index = 0; index < segments.length; index++) {
      if (generation != _generation) return;
      final segment = segments[index];
      final voice = segment.isDialogue && dialogue != null
          ? dialogue
          : narrator;
      final audio = await worker.generate({
        'root': voice.rootPath,
        'model': voice.model.toJson(),
        'text': segment.text,
        'speaker': identical(voice, narrator) ? settings.narratorSpeakerId : 0,
        'speed': segment.isDialogue
            ? settings.dialogueSpeed
            : settings.narratorSpeed,
      });
      if (generation != _generation) return;
      yield ReaderTtsClip(
        wav: audio['wav']! as Uint8List,
        sampleRate: audio['sampleRate']! as int,
        sampleCount: audio['sampleCount']! as int,
        index: index,
      );
    }
  }

  Future<ReaderOfflineTtsWorker> _openWorker() async {
    if (_disposed) throw StateError('离线语音已关闭');
    final opening = _worker ??= _createWorker();
    try {
      return await opening;
    } catch (_) {
      if (identical(_worker, opening)) _worker = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      await worker.then<void>(
        (worker) => worker.close(),
        onError: (Object _) {},
      );
    }
  }
}

/// 播放一段音频的 Future 只在播放完成、停止或失败时结束。
abstract interface class ReaderTtsPlayer {
  Future<void> play(
    ReaderTtsClip clip, {
    double volume = 1,
    void Function()? onStarted,
    void Function(Duration position)? onPosition,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

/// 暂停保留播放器与音频位置，超时预算只在实际播放期间消耗。
class AudioplayersReaderTtsPlayer implements ReaderTtsPlayer {
  AudioplayersReaderTtsPlayer({
    AudioPlayer? audioPlayer,
    this.externalAudioFocus = false,
  }) : _player = audioPlayer;

  final bool externalAudioFocus;
  AudioPlayer? _player;
  bool _positionConfigured = false;
  Future<void>? _configuration;
  Future<void> _sourceWork = Future.value();
  bool _sourceReady = false;
  Completer<void>? _completion;
  Timer? _timeout;
  final _playingTime = Stopwatch();
  Duration _budget = Duration.zero;
  bool _paused = false;
  void Function()? _onStarted;

  @override
  Future<void> play(
    ReaderTtsClip clip, {
    double volume = 1,
    void Function()? onStarted,
    void Function(Duration position)? onPosition,
  }) async {
    final player = _player ??= AudioPlayer();
    if (!_positionConfigured) {
      // 锁屏后 Flutter 不再调度界面帧；按播放器实测位置更新跨页游标。
      player.positionUpdater = TimerPositionUpdater(
        getPosition: player.getCurrentPosition,
        interval: const Duration(milliseconds: 200),
      );
      _positionConfigured = true;
    }
    final completion = _completion = Completer<void>();
    _paused = false;
    _sourceReady = false;
    _onStarted = onStarted;
    _budget = clip.duration + const Duration(seconds: 2);
    _playingTime.reset();
    final subscription = player.onPlayerComplete.listen((_) {
      if (identical(_completion, completion) && !completion.isCompleted) {
        completion.complete();
      }
    });
    final positions = _observePositions(player, completion, onPosition);
    try {
      await _prepareSource(player, completion, clip, volume);
      if (identical(_completion, completion) && !completion.isCompleted) {
        _sourceReady = true;
        if (!_paused) await resume();
      }
      await completion.future;
    } finally {
      await positions?.cancel();
      await subscription.cancel();
      if (identical(_completion, completion)) {
        _timeout?.cancel();
        _playingTime.stop();
        _completion = null;
        _sourceReady = false;
        _onStarted = null;
      }
    }
  }

  Future<void> _prepareSource(
    AudioPlayer player,
    Completer<void> completion,
    ReaderTtsClip clip,
    double volume,
  ) {
    // 取消可立即返回；后一次设置音源仍等待旧准备结束，避免原生音源互相覆盖。
    bool current() =>
        identical(_completion, completion) && !completion.isCompleted;
    final operation = _sourceWork.then((_) async {
      if (!current()) return;
      if (externalAudioFocus) {
        await (_configuration ??= player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.speech,
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        ));
      }
      if (!current()) return;
      await player.setVolume(volume.clamp(0, 1));
      if (!current()) return;
      await player.setSource(BytesSource(clip.wav, mimeType: 'audio/wav'));
    });
    _sourceWork = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  StreamSubscription<Duration>? _observePositions(
    AudioPlayer player,
    Completer<void> completion,
    void Function(Duration position)? onPosition,
  ) => onPosition == null
      ? null
      : player.onPositionChanged.listen((position) {
          if (identical(_completion, completion) &&
              !completion.isCompleted &&
              !_paused &&
              _playingTime.isRunning) {
            onPosition(position);
          }
        });

  @override
  Future<void> pause() async {
    _paused = true;
    _timeout?.cancel();
    _playingTime.stop();
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    final completion = _completion;
    if (completion == null || completion.isCompleted) return;
    _paused = false;
    if (!_sourceReady) return;
    await _player?.resume();
    if (!identical(completion, _completion) ||
        _paused ||
        completion.isCompleted) {
      return;
    }
    _playingTime.start();
    _timeout?.cancel();
    final remaining = _budget - _playingTime.elapsed;
    _timeout = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!completion.isCompleted) {
        completion.completeError(StateError('离线音频播放未完成'));
      }
    });
    _onStarted?.call();
  }

  @override
  Future<void> stop() async {
    _timeout?.cancel();
    _playingTime.stop();
    final completion = _completion;
    _completion = null;
    _sourceReady = false;
    _onStarted = null;
    if (completion != null && !completion.isCompleted) completion.complete();
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _sourceWork;
    final player = _player;
    _player = null;
    _positionConfigured = false;
    _configuration = null;
    await player?.dispose();
  }
}

/// 计算音频时长。
Duration readerTtsDuration(int sampleCount, int sampleRate) => Duration(
  milliseconds: sampleRate <= 0
      ? 0
      : math.max(1, (sampleCount * 1000 / sampleRate).round()),
);
