import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_onnx_ocr/flutter_onnx_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 本地 OCR 结果；识别模型仅在后台 isolate 初始化一次。
typedef LocalOcrLine = ({String text, Rect bounds, double confidence});

const _modelAssets = 'assets/ocr/snapfind_ppocrv4';
const _modelCacheVersion = 'snapfind-ppocrv4-v2';
final localOcrWorker = LocalOcrWorker();

class LocalOcrWorker {
  Future<void>? _startup;
  SendPort? _commands;
  Isolate? _isolate;
  ReceivePort? _responses;
  Completer<void>? _ready;
  int _nextRequestId = 0;
  final Map<int, Completer<List<LocalOcrLine>>> _pending = {};

  Future<List<LocalOcrLine>> recognize(Uint8List imageBytes) async {
    await _ensureStarted();
    final id = ++_nextRequestId;
    final completer = Completer<List<LocalOcrLine>>();
    _pending[id] = completer;
    try {
      _commands!.send({
        'id': id,
        'image': TransferableTypedData.fromList([imageBytes]),
      });
    } on Object {
      _pending.remove(id);
      rethrow;
    }
    return completer.future;
  }

  Future<void> _ensureStarted() async {
    final startup = _startup;
    if (startup != null) return startup;
    final request = _start();
    _startup = request;
    try {
      await request;
    } on Object {
      if (identical(_startup, request)) _startup = null;
      rethrow;
    }
  }

  Future<void> _start() async {
    final bundle = await _prepareModels();
    final responses = ReceivePort();
    _responses = responses;
    final ready = Completer<void>();
    _ready = ready;
    responses.listen(_handleMessage);
    try {
      _isolate = await Isolate.spawn<Map<String, Object?>>(
        _localOcrWorkerMain,
        {
          'reply': responses.sendPort,
          'detectionPath': bundle.detectionPath,
          'recognitionPath': bundle.recognitionPath,
          'characterDict': bundle.characterDict,
        },
        onError: responses.sendPort,
        onExit: responses.sendPort,
      );
      await ready.future;
    } on Object catch (error) {
      if (identical(_responses, responses)) _stop(error);
      rethrow;
    }
  }

  void _handleMessage(Object? message) {
    if (message == null || message is List) {
      final detail = message is List && message.isNotEmpty
          ? message.first
          : '识别进程已退出';
      _stop(StateError('文字识别中断：$detail'));
      return;
    }
    if (message is! Map) return;
    switch (message['type']) {
      case 'commands':
        _commands = message['port'] as SendPort;
        break;
      case 'ready':
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
        break;
      case 'init_error':
        _stop(StateError('OCR 初始化失败：${message['error']}'));
        break;
      case 'result':
        final id = message['id'] as int;
        final completer = _pending.remove(id);
        if (completer != null) {
          completer.complete(_decodeLines(message['lines']));
        }
        break;
      case 'result_error':
        final id = message['id'] as int;
        _pending
            .remove(id)
            ?.completeError(StateError('OCR 识别失败：${message['error']}'));
        break;
    }
  }

  List<LocalOcrLine> _decodeLines(Object? value) {
    if (value is! List) return [];
    return [
      for (final item in value)
        if (item is Map &&
            item['text'] is String &&
            item['bounds'] is List &&
            (item['bounds'] as List).length == 4)
          (
            text: item['text'] as String,
            confidence: (item['confidence'] as num).toDouble(),
            bounds: Rect.fromLTRB(
              ((item['bounds'] as List)[0] as num).toDouble(),
              ((item['bounds'] as List)[1] as num).toDouble(),
              ((item['bounds'] as List)[2] as num).toDouble(),
              ((item['bounds'] as List)[3] as num).toDouble(),
            ),
          ),
    ];
  }

  void _stop(Object error) {
    _responses?.close();
    _responses = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _startup = null;
    if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error);
    _ready = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<
    ({String detectionPath, String recognitionPath, List<String> characterDict})
  >
  _prepareModels() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'ocr', _modelCacheVersion),
    );
    await directory.create(recursive: true);
    final detectionPath = await _materializeModel(
      'ch_PP-OCRv4_det_mobile.onnx',
      directory,
    );
    final recognitionPath = await _materializeModel(
      'ch_PP-OCRv4_rec_mobile.onnx',
      directory,
    );
    final dictionary =
        (await rootBundle.loadString('$_modelAssets/ppocr_keys.txt'))
            .split('\n')
            .map((line) => line.replaceAll('\r', ''))
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
    return (
      detectionPath: detectionPath,
      recognitionPath: recognitionPath,
      characterDict: dictionary,
    );
  }

  Future<String> _materializeModel(String name, Directory directory) async {
    final file = File(p.join(directory.path, name));
    if (await file.exists() && await file.length() > 0) return file.path;
    final data = await rootBundle.load('$_modelAssets/$name');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await temporary.rename(file.path);
    return file.path;
  }
}

@pragma('vm:entry-point')
Future<void> _localOcrWorkerMain(Map<String, Object?> message) async {
  final reply = message['reply'] as SendPort;
  final commands = ReceivePort();
  var initialized = false;
  reply.send({'type': 'commands', 'port': commands.sendPort});
  try {
    await FlutterOnnxOcr.initialize(
      detectionModelPath: message['detectionPath'] as String,
      recognitionModelPath: message['recognitionPath'] as String,
      characterDict: (message['characterDict'] as List).cast<String>(),
    );
    initialized = true;
    reply.send({'type': 'ready'});
    await for (final command in commands) {
      if (command is! Map) continue;
      final id = command['id'] as int;
      try {
        final image = (command['image'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final results = await FlutterOnnxOcr.recognizeFromBytes(image);
        reply.send({
          'type': 'result',
          'id': id,
          'lines': [
            for (final result in results)
              if (result.text.trim().isNotEmpty && result.box.isNotEmpty)
                {
                  'text': result.text,
                  'confidence': result.confidence,
                  'bounds': [
                    result.box.map((point) => point.dx).reduce(math.min),
                    result.box.map((point) => point.dy).reduce(math.min),
                    result.box.map((point) => point.dx).reduce(math.max),
                    result.box.map((point) => point.dy).reduce(math.max),
                  ],
                },
          ],
        });
      } on Object catch (error) {
        reply.send({'type': 'result_error', 'id': id, 'error': '$error'});
      }
    }
  } on Object catch (error) {
    reply.send({'type': 'init_error', 'error': '$error'});
  } finally {
    commands.close();
    if (initialized) FlutterOnnxOcr.dispose();
  }
}
