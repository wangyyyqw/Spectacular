import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader_ui/reading_highlight.dart';

import '../diagnostics/reader_log.dart';
import 'reader_offline_tts.dart';
import 'reader_settings.dart';
import 'reader_system_tts.dart';
import 'reader_tts_background.dart';
import 'reader_tts_text.dart';

export 'reader_system_tts.dart' show ReaderTtsVoice;

/// 播放阶段与按钮状态使用同一个状态来源。
enum ReaderTtsPhase { idle, loading, playing, paused, completed, failed }

/// 面板状态；原文位置由独立高亮通知器提供，正文不用随状态重建。
class ReaderTtsSnapshot {
  const ReaderTtsSnapshot({
    required this.phase,
    this.mode = ReaderTtsMode.system,
    this.chunk,
    this.segment,
    this.error,
  });

  final ReaderTtsPhase phase;
  final ReaderTtsMode mode;
  final ReaderTtsTextChunk? chunk;
  final ReaderTtsSegment? segment;
  final Object? error;

  String get chapterTitle => chunk?.title ?? '';
  String get text => segment?.text ?? '';
}

typedef _PreparedClip = ({
  ReaderTtsClip? clip,
  Object? error,
  StackTrace? stack,
});
typedef _OfflineVoices = ({
  ReaderOfflineVoiceInstance narrator,
  ReaderOfflineVoiceInstance? dialogue,
});

/// 在本次阅读会话中保留听书游标，逐段播放与屏幕导航彼此独立。
class ReaderTtsController {
  ReaderTtsController({
    required this.textSource,
    this.offlineSynthesizer,
    this.player,
    this.resolveOfflineVoice,
    this.backgroundPlayback,
  }) {
    backgroundPlayback?.onCommand = (command) => switch (command) {
      ReaderTtsMediaCommand.play => resume(),
      ReaderTtsMediaCommand.pause => pause(),
      ReaderTtsMediaCommand.stop => stop(),
    };
  }

  final ReaderTtsTextSource textSource;
  final ReaderOfflineTtsSynthesizer? offlineSynthesizer;
  final ReaderTtsPlayer? player;
  final ReaderTtsBackgroundPlayback? backgroundPlayback;
  final Future<ReaderOfflineVoiceInstance?> Function(String id)?
  resolveOfflineVoice;
  final state = ValueNotifier(
    const ReaderTtsSnapshot(phase: ReaderTtsPhase.idle),
  );
  final highlight = ValueNotifier<ReaderReadingHighlight?>(null);
  final _system = ReaderSystemTts();

  void Function(Object error)? onError;
  Future<void> Function(ReaderReadingHighlight range)? onPositionChanged;

  ReaderTtsSettings _settings = ReaderTtsSettings.defaults;
  ReaderTtsSettings _pieceSettings = ReaderTtsSettings.defaults;
  ReaderTtsMode _activeMode = ReaderTtsMode.system;
  ReaderTtsTextChunk? _chunk;
  int _segmentIndex = 0;
  int _generation = 0;
  int _settingsRevision = 0;
  int _pieceRevision = 0;
  int _systemSettingsRevision = -1;
  Completer<void>? _cancel;
  Completer<void>? _resume;
  Future<void> _transition = Future.value();
  Stopwatch? _startupWatch;
  String? _voiceKey;
  Future<_OfflineVoices>? _voices;
  ({
    ReaderTtsSegment segment,
    int index,
    ReaderTtsSettings settings,
    Future<_PreparedClip> result,
  })?
  _prefetch;

  ReaderTtsSnapshot get snapshot => state.value;
  ReaderTtsSettings get settings => _settings;
  bool get speaking =>
      snapshot.phase == ReaderTtsPhase.playing ||
      snapshot.phase == ReaderTtsPhase.loading;
  bool get paused => snapshot.phase == ReaderTtsPhase.paused;
  bool get hasSession => speaking || paused;
  bool get supportsBackgroundPlayback => backgroundPlayback?.supported ?? false;
  ReaderReadingHighlight? get position =>
      highlight.value ??
      (_segment == null ? null : _chunk!.highlightFor(_segment!));
  ReaderTtsMode get _mode => _activeMode;
  ReaderTtsSegment? get _segment =>
      _chunk != null && _segmentIndex < _chunk!.segments.length
      ? _chunk!.segments[_segmentIndex]
      : null;

  List<ReaderTtsSegment> _playbackSegments(int index) {
    final segments = _chunk!.segments;
    var end = index + 1;
    while (end < segments.length && segments[end - 1].continuesOnNextPage) {
      end++;
    }
    return segments.sublist(index, end);
  }

  Future<List<ReaderTtsVoice>> loadVoices() => _system.voices();

  /// 正文首屏就绪后预热旁白，不改变播放状态；对白按需加载。
  Future<void> prepare(ReaderTtsSettings settings) async {
    if (settings.mode != ReaderTtsMode.offline || !settings.hasOfflineVoice) {
      return;
    }
    final generation = _generation;
    final voice = await resolveOfflineVoice?.call(settings.narratorVoiceId);
    if (voice != null && _valid(generation)) {
      await offlineSynthesizer?.prepare(voice);
    }
  }

  void _publish(ReaderTtsPhase phase, {Object? error}) {
    state.value = ReaderTtsSnapshot(
      phase: phase,
      mode: _mode,
      chunk: _chunk,
      segment: _segment,
      error: error,
    );
    final update = backgroundPlayback?.update(
      phase: phase.name,
      chapterTitle: snapshot.chapterTitle,
    );
    if (update != null) {
      unawaited(
        update.then<void>(
          (_) {},
          onError: (Object error) => onError?.call(error),
        ),
      );
    }
  }

  bool _valid(int generation) => generation == _generation;

  /// 开始一个新会话；暂停后的继续应调用 resume，不能重新开始。
  Future<void> start(ReaderTtsSettings settings) => _start(settings);

  /// 保留失败片段，已完成的正文不因重试而再次朗读。
  Future<void> retry(ReaderTtsSettings settings) => _start(
    settings,
    chunk: snapshot.phase == ReaderTtsPhase.failed ? _chunk : null,
    segmentIndex: snapshot.phase == ReaderTtsPhase.failed ? _segmentIndex : 0,
  );

  Future<void> _start(
    ReaderTtsSettings settings, {
    ReaderTtsTextChunk? chunk,
    int segmentIndex = 0,
  }) async {
    final stopping = stop();
    final generation = _generation;
    _startupWatch = Stopwatch()..start();
    _cancel = Completer<void>();
    _settings = settings;
    _activeMode = settings.mode;
    _settingsRevision++;
    _systemSettingsRevision = -1;
    _publish(ReaderTtsPhase.loading);
    try {
      await stopping;
      if (!_valid(generation)) return;
      await _wait(
        backgroundPlayback?.start() ?? Future<void>.value(),
        generation,
      );
      if (!_valid(generation)) return;
      _chunk =
          chunk ??
          await _wait<ReaderTtsTextChunk?>(
            textSource.first(autoTurnPage: settings.autoTurnPage),
            generation,
          );
      _segmentIndex = segmentIndex;
      if (settings.mode == ReaderTtsMode.offline) {
        _chunk = _chunk?.withShortLead(segmentIndex);
      }
      if (_valid(generation)) await _run(generation);
    } catch (error) {
      await _fail(generation, error);
    }
  }

  Future<void> _fail(int generation, Object error) async {
    if (!_valid(generation)) return;
    await _stopBackends();
    if (!_valid(generation)) return;
    highlight.value = null;
    _publish(ReaderTtsPhase.failed, error: error);
    onError?.call(error);
  }

  Future<void> _run(int generation) async {
    while (_valid(generation) && _chunk != null) {
      if (!await _waitResumed(generation)) return;
      if (_segmentIndex >= _chunk!.segments.length) {
        if (!_settings.autoTurnPage) break;
        _chunk = await _wait<ReaderTtsTextChunk?>(
          textSource.next(_chunk!.spineIndex),
          generation,
        );
        _segmentIndex = 0;
        continue;
      }
      _pieceSettings = _settings;
      _pieceRevision = _settingsRevision;
      _activeMode = _pieceSettings.mode;
      _publish(ReaderTtsPhase.loading);
      final range = _chunk!.highlightFor(_segment!);
      if (range != null) await onPositionChanged?.call(range);
      if (!await _waitResumed(generation)) return;
      final completed = _mode == ReaderTtsMode.offline
          ? await _playOffline(generation)
          : await _playSystem(generation);
      if (!completed || !await _waitResumed(generation)) return;
      _segmentIndex++;
    }
    if (_valid(generation)) {
      highlight.value = null;
      _publish(ReaderTtsPhase.completed);
      await offlineSynthesizer?.stop();
      await backgroundPlayback?.stop();
    }
  }

  Future<T?> _wait<T>(Future<T> operation, int generation) async {
    final result = await Future.any<T?>([
      operation,
      _cancel!.future.then<T?>((_) => null),
    ]);
    return _valid(generation) ? result : null;
  }

  Future<bool> _waitResumed(int generation) async {
    while (_valid(generation) && paused) {
      final resumed = _resume ??= Completer<void>();
      await Future.any([resumed.future, _cancel!.future]);
    }
    return _valid(generation);
  }

  void _started(int generation) {
    if (!_valid(generation) || paused) return;
    final watch = _startupWatch;
    if (watch != null) {
      watch.stop();
      _startupWatch = null;
      recordAppEvent(
        'tts_started',
        fields: {
          'ms': watch.elapsedMilliseconds,
          'mode': _mode,
          'characters': _segment?.text.length,
        },
      );
    }
    final range = _chunk?.highlightFor(_segment!);
    if (range != null) highlight.value = range;
    _publish(ReaderTtsPhase.playing);
  }

  void _progress(
    int generation,
    int start,
    int end, {
    ReaderTtsSegment? segment,
  }) {
    if (!_valid(generation) || paused || _segment == null) return;
    final range = _chunk!.highlightFor(
      segment ?? _segment!,
      wordStart: start,
      wordEnd: end,
    );
    if (range == null) return;
    highlight.value = range;
    _publish(ReaderTtsPhase.playing);
    _followProgress(range, generation);
  }

  void _followProgress(ReaderReadingHighlight range, int generation) {
    final follow = onPositionChanged?.call(range);
    if (follow != null) {
      unawaited(
        follow.then<void>(
          (_) {},
          onError: (Object error) {
            if (_valid(generation)) onError?.call(error);
          },
        ),
      );
    }
  }

  void _offlineProgress(
    int generation,
    int first,
    ReaderTtsClip clip,
    Duration position,
  ) {
    if (!_valid(generation) || paused) return;
    final sample = position.inMicroseconds * clip.sampleRate ~/ 1000000;
    var index = _segmentIndex - first;
    while (index + 1 < clip.segmentStarts.length &&
        clip.segmentStarts[index + 1] <= sample) {
      index++;
    }
    if (first + index <= _segmentIndex) return;
    _segmentIndex = first + index;
    final range = _chunk!.highlightFor(_segment!);
    if (range == null) return;
    highlight.value = range;
    _publish(ReaderTtsPhase.playing);
    _followProgress(range, generation);
  }

  Future<bool> _playSystem(int generation) async {
    final segments = _playbackSegments(_segmentIndex);
    final spoken = segments.length == 1
        ? segments.single
        : ReaderTtsSegment(
            text: segments.map((segment) => segment.text).join(),
            kind: segments.first.kind,
            sourceOffsets: [
              for (final segment in segments) ...segment.sourceOffsets,
            ],
          );
    while (_valid(generation)) {
      if (!await _waitResumed(generation)) return false;
      final revision = _pieceRevision;
      if (_systemSettingsRevision != revision) {
        await _wait(_system.configure(_pieceSettings), generation);
        if (!_valid(generation)) return false;
        _systemSettingsRevision = revision;
      }
      if (!await _waitResumed(generation)) return false;
      final completed = await _wait(
        _system.speak(
          spoken.text,
          focus: !supportsBackgroundPlayback,
          onStarted: () => _started(generation),
          onProgress: (start, end) =>
              _progress(generation, start, end, segment: spoken),
        ),
        generation,
      );
      if (!_valid(generation)) return false;
      if (completed == true) {
        _segmentIndex += segments.length - 1;
        return true;
      }
      if (!paused) throw StateError('系统朗读已中断');
    }
    return false;
  }

  Future<bool> _playOffline(int generation) async {
    final audioPlayer = player;
    if (audioPlayer == null) throw StateError('离线播放器未配置');
    if (!_valid(generation)) return false;
    final first = _segmentIndex;
    final segments = _playbackSegments(first);
    final clip = await _clipFor(segments, generation);
    if (clip == null || !await _waitResumed(generation)) return false;
    _prefetchNext(generation, first + segments.length);
    await _wait(
      audioPlayer.play(
        clip,
        volume: _pieceSettings.volume,
        onStarted: () => _started(generation),
        onPosition: segments.length == 1
            ? null
            : (position) => _offlineProgress(generation, first, clip, position),
      ),
      generation,
    );
    if (_valid(generation)) {
      _offlineProgress(generation, first, clip, clip.duration);
      _segmentIndex = first + segments.length - 1;
    }
    return _valid(generation);
  }

  Future<ReaderTtsClip?> _clipFor(
    List<ReaderTtsSegment> segments,
    int generation,
  ) async {
    final cached = _prefetch;
    final pending =
        cached?.segment == segments.first &&
            _sameOfflineAudio(cached!.settings, _pieceSettings)
        ? cached.result
        : _prepareClip(segments, _pieceSettings, generation);
    _prefetch = null;
    final prepared = await _wait(pending, generation);
    if (!_valid(generation) || prepared == null) return null;
    if (prepared.error != null) {
      Error.throwWithStackTrace(prepared.error!, prepared.stack!);
    }
    return prepared.clip;
  }

  void _prefetchNext(int generation, int nextIndex) {
    if (_settings.mode != ReaderTtsMode.offline) return;
    final segments = _chunk!.segments;
    if (nextIndex >= segments.length) return;
    final next = _playbackSegments(nextIndex);
    _prefetch = (
      segment: next.first,
      index: nextIndex,
      settings: _settings,
      result: _prepareClip(next, _settings, generation),
    );
  }

  Future<_PreparedClip> _prepareClip(
    List<ReaderTtsSegment> segments,
    ReaderTtsSettings settings,
    int generation,
  ) {
    // 立即接住预合成错误，播放当前段期间不会产生未处理的异步异常。
    return _generateClip(segments, settings, generation).then<_PreparedClip>(
      (clip) => (clip: clip, error: null, stack: null),
      onError: (Object error, StackTrace stack) =>
          (clip: null, error: error, stack: stack),
    );
  }

  Future<ReaderTtsClip> _generateClip(
    List<ReaderTtsSegment> segments,
    ReaderTtsSettings settings,
    int generation,
  ) async {
    final synthesizer = offlineSynthesizer;
    if (synthesizer == null) throw StateError('离线合成器未配置');
    final key = '${settings.narratorVoiceId}|${settings.dialogueVoiceId}';
    if (_voiceKey != key) {
      _voiceKey = key;
      _voices = _resolveVoices(settings);
    }
    final voices = await _voices!;
    if (!_valid(generation)) throw StateError('听书已结束');
    final clips = await synthesizer
        .synthesize(
          segments: segments,
          narrator: voices.narrator,
          dialogue: voices.dialogue,
          settings: settings,
        )
        .toList();
    if (!_valid(generation)) throw StateError('听书已结束');
    return ReaderTtsClip.join(clips);
  }

  Future<_OfflineVoices> _resolveVoices(ReaderTtsSettings settings) async {
    final resolver = resolveOfflineVoice;
    if (resolver == null || !settings.hasOfflineVoice) {
      throw StateError('尚未选择离线旁白音色');
    }
    final narrator = await resolver(settings.narratorVoiceId);
    if (narrator == null) throw StateError('所选旁白音色尚未下载');
    final dialogue =
        settings.dialogueVoiceId.isNotEmpty &&
            settings.dialogueVoiceId != settings.narratorVoiceId
        ? await resolver(settings.dialogueVoiceId)
        : null;
    if (settings.dialogueVoiceId.isNotEmpty &&
        settings.dialogueVoiceId != settings.narratorVoiceId &&
        dialogue == null) {
      throw StateError('所选对白音色尚未下载');
    }
    return (narrator: narrator, dialogue: dialogue);
  }

  /// 设置在下一片段生效；已暂停或播放中的音频不重新合成。
  void updateSettings(ReaderTtsSettings settings) {
    if (_settings == settings) return;
    _settings = settings;
    _settingsRevision++;
    final cached = _prefetch;
    if (settings.mode != ReaderTtsMode.offline) {
      _prefetch = null;
    } else if (cached != null &&
        !_sameOfflineAudio(cached.settings, settings)) {
      _prefetchNext(_generation, cached.index);
    }
    if (!hasSession) {
      _activeMode = settings.mode;
      _publish(snapshot.phase, error: snapshot.error);
    }
  }

  // 音量和续读开关不改变 WAV，保留已经准备的下一句。
  bool _sameOfflineAudio(ReaderTtsSettings left, ReaderTtsSettings right) =>
      left.narratorVoiceId == right.narratorVoiceId &&
      left.dialogueVoiceId == right.dialogueVoiceId &&
      left.narratorSpeakerId == right.narratorSpeakerId &&
      left.narratorSpeed == right.narratorSpeed &&
      left.dialogueSpeed == right.dialogueSpeed;

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _transition.then((_) => action());
    _transition = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> pause() {
    final generation = _generation;
    if (!speaking) return Future.value();
    _publish(ReaderTtsPhase.paused);
    return _serialize(() async {
      if (!_valid(generation) || !paused) return;
      if (_mode == ReaderTtsMode.offline) {
        await player?.pause();
      } else {
        await _system.pause();
      }
    });
  }

  Future<void> resume() {
    final generation = _generation;
    return _serialize(() async {
      if (!_valid(generation) || !paused) return;
      await backgroundPlayback?.activate();
      if (!_valid(generation) || !paused) return;
      _publish(ReaderTtsPhase.loading);
      final resumed = _resume;
      _resume = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
      if (_mode == ReaderTtsMode.offline) await player?.resume();
    });
  }

  Future<void> _stopBackends() async {
    await Future.wait([
      _system.stop(),
      if (player != null) player!.stop(),
      if (offlineSynthesizer != null) offlineSynthesizer!.stop(),
      if (backgroundPlayback != null) backgroundPlayback!.stop(),
    ]);
  }

  Future<void> stop() async {
    _generation++;
    _startupWatch = null;
    final cancellation = _cancel;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final resumed = _resume;
    _resume = null;
    if (resumed != null && !resumed.isCompleted) resumed.complete();
    _prefetch = null;
    _voices = null;
    _voiceKey = null;
    _chunk = null;
    _segmentIndex = 0;
    highlight.value = null;
    _publish(ReaderTtsPhase.idle);
    await _transition;
    await _stopBackends();
  }

  Future<void> dispose() async {
    await stop();
    await player?.dispose();
    await offlineSynthesizer?.dispose();
    await backgroundPlayback?.dispose();
    onError = null;
    onPositionChanged = null;
    highlight.dispose();
    state.dispose();
  }
}
