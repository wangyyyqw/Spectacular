import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'reader_tts_voice_store.dart';

/// 原生模型只属于工作 isolate，主 isolate 只接收完成的音频。
class ReaderOfflineTtsWorker {
  ReaderOfflineTtsWorker._(this._responses) {
    _subscription = _responses.listen(_receive);
  }

  final ReceivePort _responses;
  final _ready = Completer<SendPort>();
  final _requests = <int, Completer<Map<String, Object?>>>{};
  late final StreamSubscription<Object?> _subscription;
  int _requestId = 0;
  Object? _failure;

  bool get available => _failure == null;

  static Future<ReaderOfflineTtsWorker> open() async {
    final worker = ReaderOfflineTtsWorker._(ReceivePort());
    try {
      await Isolate.spawn(
        _ttsWorkerMain,
        worker._responses.sendPort,
        onError: worker._responses.sendPort,
        onExit: worker._responses.sendPort,
      );
      await worker._ready.future;
      return worker;
    } catch (_) {
      await worker._subscription.cancel();
      worker._responses.close();
      rethrow;
    }
  }

  void _receive(Object? message) {
    switch (message) {
      case (0, final SendPort commands):
        if (!_ready.isCompleted) _ready.complete(commands);
      case (final int id, final Map<String, Object?> audio):
        _requests.remove(id)?.complete(audio);
      case (final int id, final String error):
        _requests.remove(id)?.completeError(StateError(error));
      default:
        final error = StateError('离线语音工作线程已退出');
        _failure = error;
        if (!_ready.isCompleted) _ready.completeError(error);
        for (final request in _requests.values) {
          request.completeError(error);
        }
        _requests.clear();
    }
  }

  Future<Map<String, Object?>> generate(Map<String, Object?> input) =>
      _request('generate', input);

  Future<void> prepare(Map<String, Object?> input) async {
    await _request('prepare', input);
  }

  Future<Map<String, Object?>> _request(
    String operation,
    Map<String, Object?> input,
  ) async {
    final commands = await _ready.future;
    if (_failure != null) throw _failure!;
    final id = ++_requestId;
    final result = Completer<Map<String, Object?>>();
    _requests[id] = result;
    commands.send((id, operation, input));
    return result.future;
  }

  Future<void> close() async {
    try {
      if (available) await _request('close', const {});
    } finally {
      await _subscription.cancel();
      _responses.close();
    }
  }
}

Future<void> _ttsWorkerMain(SendPort responses) async {
  sherpa.initBindings();
  final commands = ReceivePort();
  final models = <String, sherpa.OfflineTts>{};
  responses.send((0, commands.sendPort));
  try {
    await for (final message in commands) {
      final (id, operation, input) =
          message as (int, String, Map<String, Object?>);
      try {
        if (operation == 'generate') {
          responses.send((id, _generate(models, input)));
        } else if (operation == 'prepare') {
          _modelFor(models, input);
          responses.send((id, <String, Object?>{}));
        } else {
          for (final model in models.values) {
            model.free();
          }
          models.clear();
          responses.send((id, <String, Object?>{}));
          if (operation == 'close') break;
        }
      } catch (error) {
        responses.send((id, '$error'));
      }
    }
  } finally {
    for (final model in models.values) {
      model.free();
    }
    commands.close();
  }
}

Map<String, Object?> _generate(
  Map<String, sherpa.OfflineTts> models,
  Map<String, Object?> input,
) {
  final tts = _modelFor(models, input);
  final audio = tts.generate(
    text: input['text']! as String,
    sid: (input['speaker']! as int).clamp(0, tts.numSpeakers - 1),
    speed: (input['speed']! as double).clamp(0.5, 2),
  );
  if (audio.samples.isEmpty || audio.sampleRate <= 0) {
    throw StateError('所选音色未能合成当前片段');
  }
  return {
    'wav': _encodeWav(audio.samples, audio.sampleRate),
    'sampleRate': audio.sampleRate,
    'sampleCount': audio.samples.length,
  };
}

sherpa.OfflineTts _modelFor(
  Map<String, sherpa.OfflineTts> models,
  Map<String, Object?> input,
) {
  final root = input['root']! as String;
  final description = input['model']! as Map<String, Object?>;
  final key = '$root:${jsonEncode(description)}';
  var tts = models.remove(key);
  if (tts == null) {
    if (models.length >= 2) models.remove(models.keys.first)!.free();
    tts = sherpa.OfflineTts(
      _ttsConfig(ReaderOfflineVoiceModel.fromJson(description), root),
    );
  }
  models[key] = tts;
  return tts;
}

// 上游四种模型的字段各异，集中保持配置对应关系，避免分散模型路径规则。
// 此声明式映射保留在一处；升级模型配置时需逐项核对上游字段，防止路径错配。
sherpa.OfflineTtsConfig _ttsConfig(ReaderOfflineVoiceModel model, String root) {
  String resolve(String value) => value.isEmpty ? '' : p.join(root, value);
  final ruleFsts = [for (final value in model.ruleFsts) resolve(value)]
      .join(',');
  final lexicons = [for (final value in model.lexicons) resolve(value)];
  final config = switch (model.kind) {
    ReaderOfflineModelKind.vits => sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: resolve(model.model),
        tokens: resolve(model.tokens),
        lexicon: lexicons.firstOrNull ?? '',
        dataDir: resolve(model.dataDir),
      ),
      numThreads: 2,
    ),
    ReaderOfflineModelKind.matcha => sherpa.OfflineTtsModelConfig(
      matcha: sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: resolve(model.acousticModel),
        vocoder: resolve(model.vocoder),
        tokens: resolve(model.tokens),
        lexicon: lexicons.firstOrNull ?? '',
        dataDir: resolve(model.dataDir),
      ),
      numThreads: 2,
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
      numThreads: 2,
    ),
    ReaderOfflineModelKind.kitten => sherpa.OfflineTtsModelConfig(
      kitten: sherpa.OfflineTtsKittenModelConfig(
        model: resolve(model.model),
        voices: resolve(model.voices),
        tokens: resolve(model.tokens),
        dataDir: resolve(model.dataDir),
        lexicon: lexicons.firstOrNull ?? '',
      ),
      numThreads: 2,
    ),
  };
  return sherpa.OfflineTtsConfig(model: config, ruleFsts: ruleFsts);
}

Uint8List _encodeWav(Float32List samples, int sampleRate) {
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
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
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
