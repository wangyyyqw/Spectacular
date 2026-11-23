import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'reader_settings.dart';
import 'reader_tts_voice_store.dart';

/// 朗读片段的类型。
enum ReaderTtsSegmentKind {
  /// 旁白。
  narration,

  /// 引号内的对白。
  dialogue,
}

/// 带类型的朗读片段。
class ReaderTtsSegment {
  /// 创建片段。
  const ReaderTtsSegment({required this.text, required this.kind});

  /// 朗读文字。
  final String text;

  /// 片段类型。
  final ReaderTtsSegmentKind kind;

  /// 是否对白。
  bool get isDialogue => kind == ReaderTtsSegmentKind.dialogue;
}

/// 结合中文引号与句读切分朗读片段。
abstract final class ReaderTtsSegmentation {
  static final RegExp _noise = RegExp(r'[※＊*·•●○◆◇■□━─—=~]{2,}');
  static final RegExp _sentence = RegExp(r'[^。！？!?；;]+[。！？!?；;]?');
  static final RegExp _softBreak = RegExp(r'(?<=[，,、：:\s])');

  /// 切分正文；对白与旁白分别标记。
  static List<ReaderTtsSegment> split(String text) {
    final normalized = text
        .replaceAll(_noise, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const <ReaderTtsSegment>[];
    final chunks = _splitQuotes(normalized);
    final result = <ReaderTtsSegment>[];
    for (final chunk in chunks) {
      for (final sentence in _splitSentences(chunk.text)) {
        result.add(ReaderTtsSegment(text: sentence, kind: chunk.kind));
      }
    }
    return result;
  }

  static List<({String text, ReaderTtsSegmentKind kind})> _splitQuotes(
    String text,
  ) {
    const openers = <String>{'“', '「', '『'};
    const closers = <String>{'”', '」', '』'};
    final result = <({String text, ReaderTtsSegmentKind kind})>[];
    final buffer = StringBuffer();
    String? closer;
    var dialogue = false;

    void flush(ReaderTtsSegmentKind kind) {
      final value = buffer.toString().trim();
      buffer.clear();
      if (value.isNotEmpty) {
        result.add((
          text: value,
          kind: kind == ReaderTtsSegmentKind.dialogue && value.isEmpty
              ? ReaderTtsSegmentKind.narration
              : kind,
        ));
      }
    }

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (dialogue) {
        if (char == closer || (closer == '"' && char == '"')) {
          flush(ReaderTtsSegmentKind.dialogue);
          dialogue = false;
          closer = null;
          continue;
        }
        buffer.write(char);
        continue;
      }
      if (openers.contains(char) || char == '"') {
        flush(ReaderTtsSegmentKind.narration);
        dialogue = true;
        closer = switch (char) {
          '“' => '”',
          '「' => '」',
          '『' => '』',
          _ => '"',
        };
        continue;
      }
      if (closers.contains(char)) {
        // 没有对应开引号时按普通标点处理，避免把整页误判成对白。
        buffer.write(char);
        continue;
      }
      buffer.write(char);
    }
    flush(
      dialogue ? ReaderTtsSegmentKind.dialogue : ReaderTtsSegmentKind.narration,
    );
    return result;
  }

  static List<String> _splitSentences(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const <String>[];
    final sentences = _sentence
        .allMatches(normalized)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final result = <String>[];
    for (final sentence in sentences) {
      if (sentence.length <= 160) {
        result.add(sentence);
        continue;
      }
      final parts = sentence.split(_softBreak);
      var buffer = '';
      for (final part in parts) {
        if (buffer.isNotEmpty && buffer.length + part.length > 160) {
          result.add(buffer.trim());
          buffer = '';
        }
        buffer += part;
      }
      if (buffer.trim().isNotEmpty) result.add(buffer.trim());
    }
    return result;
  }
}

/// 已解析到本地目录的离线音色。
class ReaderOfflineVoiceInstance {
  /// 创建实例。
  const ReaderOfflineVoiceInstance({
    required this.id,
    required this.rootPath,
    required this.model,
  });

  /// 音色标识。
  final String id;

  /// 模型目录。
  final String rootPath;

  /// 模型描述。
  final ReaderOfflineVoiceModel model;
}

/// 合成完成的一段 WAV。
class ReaderTtsClip {
  /// 创建片段。
  const ReaderTtsClip({
    required this.wav,
    required this.sampleRate,
    required this.sampleCount,
    required this.index,
  });

  /// 完整 WAV 字节。
  final Uint8List wav;

  /// 采样率。
  final int sampleRate;

  /// 采样点数。
  final int sampleCount;

  /// 原始片段序号。
  final int index;

  /// 音频时长。
  Duration get duration => readerTtsDuration(sampleCount, sampleRate);
}

/// 离线语音合成器。
abstract class ReaderOfflineTtsSynthesizer {
  /// 合成一页中的所有片段。
  Future<List<ReaderTtsClip>> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  });
}

/// 基于 sherpa-onnx 的隔离线程合成器。
class SherpaReaderOfflineTtsSynthesizer implements ReaderOfflineTtsSynthesizer {
  /// 创建合成器。
  const SherpaReaderOfflineTtsSynthesizer();

  @override
  Future<List<ReaderTtsClip>> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async {
    if (segments.isEmpty) return const <ReaderTtsClip>[];
    final raw = await Isolate.run(
      () => _synthesizeSync(<String, Object?>{
        'narrator': _instanceJson(narrator),
        'dialogue': dialogue == null ? null : _instanceJson(dialogue),
        'narratorSpeakerId': settings.narratorSpeakerId,
        'narratorSpeed': settings.narratorSpeed,
        'dialogueSpeed': settings.dialogueSpeed,
        'segments': <Map<String, Object?>>[
          for (final segment in segments)
            <String, Object?>{
              'text': segment.text,
              'dialogue': segment.isDialogue,
            },
        ],
      }),
    );
    return <ReaderTtsClip>[
      for (final item in raw)
        ReaderTtsClip(
          wav: item['wav']! as Uint8List,
          sampleRate: item['sampleRate']! as int,
          sampleCount: item['sampleCount']! as int,
          index: item['index']! as int,
        ),
    ]..sort((left, right) => left.index.compareTo(right.index));
  }
}

/// 音频播放器接口。
abstract class ReaderTtsPlayer {
  /// 播放一段 WAV。
  Future<void> play(ReaderTtsClip clip);

  /// 停止播放。
  Future<void> stop();

  /// 释放播放器。
  Future<void> dispose();
}

/// 使用 audioplayers 播放内存 WAV。
class AudioplayersReaderTtsPlayer implements ReaderTtsPlayer {
  AudioPlayer? _player;
  Completer<void>? _stopSignal;

  AudioPlayer get _ensurePlayer => _player ??= AudioPlayer();

  @override
  Future<void> play(ReaderTtsClip clip) async {
    final player = _ensurePlayer;
    final completed = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    final stopSignal = _stopSignal = Completer<void>();
    try {
      await player.play(BytesSource(clip.wav, mimeType: 'audio/wav'));
      await Future.any<void>(<Future<void>>[
        completed.future,
        stopSignal.future,
      ]).timeout(clip.duration + const Duration(seconds: 2), onTimeout: () {});
    } finally {
      await subscription.cancel();
      if (identical(_stopSignal, stopSignal)) _stopSignal = null;
    }
  }

  @override
  Future<void> stop() async {
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    try {
      await _player?.stop();
    } catch (_) {
      // 播放器已释放时忽略停止错误。
    }
  }

  @override
  Future<void> dispose() async {
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _stopSignal = null;
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (_) {
      // 平台播放器销毁失败不应影响阅读页退出。
    }
  }
}

Map<String, Object?> _instanceJson(ReaderOfflineVoiceInstance instance) =>
    <String, Object?>{
      'id': instance.id,
      'root': instance.rootPath,
      'model': instance.model.toJson(),
    };

List<Map<String, Object?>> _synthesizeSync(Map<String, Object?> request) {
  sherpa.initBindings();
  final rawSegments = request['segments']! as List<Object?>;
  final narrator = request['narrator']! as Map<String, Object?>;
  final dialogue = request['dialogue'] as Map<String, Object?>?;
  final narratorId = narrator['id']! as String;
  final dialogueId = dialogue?['id'] as String?;
  final speakerId = request['narratorSpeakerId']! as int;
  final narratorSpeed = (request['narratorSpeed']! as num).toDouble();
  final dialogueSpeed = (request['dialogueSpeed']! as num).toDouble();

  final narratorIndexes = <int>[];
  final dialogueIndexes = <int>[];
  for (var index = 0; index < rawSegments.length; index++) {
    final item = rawSegments[index]! as Map<String, Object?>;
    final isDialogue = item['dialogue'] == true;
    if (isDialogue && dialogue != null && dialogueId != narratorId) {
      dialogueIndexes.add(index);
    } else {
      narratorIndexes.add(index);
    }
  }

  final clips = <Map<String, Object?>>[];
  _synthesizeGroup(
    instance: narrator,
    indexes: narratorIndexes,
    segments: rawSegments,
    speed: narratorSpeed,
    dialogueSpeed: dialogueSpeed,
    speakerId: speakerId,
    clips: clips,
  );
  if (dialogueIndexes.isNotEmpty && dialogue != null) {
    _synthesizeGroup(
      instance: dialogue,
      indexes: dialogueIndexes,
      segments: rawSegments,
      speed: dialogueSpeed,
      speakerId: 0,
      clips: clips,
    );
  }
  return clips;
}

void _synthesizeGroup({
  required Map<String, Object?> instance,
  required List<int> indexes,
  required List<Object?> segments,
  required double speed,
  double? dialogueSpeed,
  required int speakerId,
  required List<Map<String, Object?>> clips,
}) {
  if (indexes.isEmpty) return;
  final root = instance['root']! as String;
  final modelMap = instance['model']! as Map<String, Object?>;
  final model = ReaderOfflineVoiceModel.fromJson(modelMap);
  final tts = sherpa.OfflineTts(_ttsConfig(model, root));
  try {
    for (final index in indexes) {
      final item = segments[index]! as Map<String, Object?>;
      final text = item['text']! as String;
      final effectiveSid = model.speakerCount <= 1
          ? 0
          : speakerId.clamp(0, model.speakerCount - 1);
      final audio = tts.generate(
        text: text,
        sid: effectiveSid,
        speed: (item['dialogue'] == true ? dialogueSpeed ?? speed : speed).clamp(
          0.5,
          2,
        ),
      );
      if (audio.samples.isEmpty || audio.sampleRate <= 0) continue;
      clips.add(<String, Object?>{
        'index': index,
        'wav': _encodeWav(audio.samples, audio.sampleRate),
        'sampleRate': audio.sampleRate,
        'sampleCount': audio.samples.length,
      });
    }
  } finally {
    tts.free();
  }
}

sherpa.OfflineTtsConfig _ttsConfig(ReaderOfflineVoiceModel model, String root) {
  String resolve(String value) => value.isEmpty ? '' : p.join(root, value);
  final ruleFsts = <String>[for (final value in model.ruleFsts) resolve(value)]
      .join(',');
  final lexicons = <String>[for (final value in model.lexicons) resolve(value)];
  final common = sherpa.OfflineTtsModelConfig(numThreads: 2, debug: false);
  final modelConfig = switch (model.kind) {
    ReaderOfflineModelKind.vits => sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: resolve(model.model),
        tokens: resolve(model.tokens),
        lexicon: lexicons.isEmpty ? '' : lexicons.first,
        dataDir: resolve(model.dataDir),
      ),
      numThreads: common.numThreads,
      debug: common.debug,
    ),
    ReaderOfflineModelKind.matcha => sherpa.OfflineTtsModelConfig(
      matcha: sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: resolve(model.acousticModel),
        vocoder: resolve(model.vocoder),
        tokens: resolve(model.tokens),
        lexicon: lexicons.isEmpty ? '' : lexicons.first,
        dataDir: resolve(model.dataDir),
      ),
      numThreads: common.numThreads,
      debug: common.debug,
    ),
    ReaderOfflineModelKind.kokoro => sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: resolve(model.model),
        voices: resolve(model.voices),
        tokens: resolve(model.tokens),
        dataDir: resolve(model.dataDir),
        lexicon: lexicons.join(','),
        lang: p.basename(root).toLowerCase().contains('multi-lang')
            ? 'zh'
            : 'en-us',
      ),
      numThreads: common.numThreads,
      debug: common.debug,
    ),
    ReaderOfflineModelKind.kitten => sherpa.OfflineTtsModelConfig(
      kitten: sherpa.OfflineTtsKittenModelConfig(
        model: resolve(model.model),
        voices: resolve(model.voices),
        tokens: resolve(model.tokens),
        dataDir: resolve(model.dataDir),
        lexicon: lexicons.isEmpty ? '' : lexicons.first,
      ),
      numThreads: common.numThreads,
      debug: common.debug,
    ),
  };
  return sherpa.OfflineTtsConfig(model: modelConfig, ruleFsts: ruleFsts);
}

Uint8List _encodeWav(Float32List samples, int sampleRate) {
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);
  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  writeAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    final sample = (samples[index].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + index * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// 计算音频时长，供测试和播放超时使用。
Duration readerTtsDuration(int sampleCount, int sampleRate) => Duration(
  milliseconds: sampleRate <= 0
      ? 0
      : math.max(1, (sampleCount * 1000 / sampleRate).round()),
);
