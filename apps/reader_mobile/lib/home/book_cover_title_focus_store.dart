import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnx_ocr/flutter_onnx_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_cover_title_focus.dart';

typedef CoverTitleRecognizer = Future<List<CoverTitleLine>> Function(
  Uint8List imageBytes,
);
typedef CoverImageSizeReader = Future<Size> Function(Uint8List imageBytes);

const _modelAssets = 'assets/ocr/snapfind_ppocrv4';
const _modelCacheVersion = 'snapfind-ppocrv4-v2';

/// 书名焦点缓存；图片版本或书名变化时重新 OCR。
class BookCoverTitleFocusStore {
  BookCoverTitleFocusStore({
    Future<Directory> Function()? directoryProvider,
    CoverTitleRecognizer? recognizer,
    CoverImageSizeReader? imageSizeReader,
    bool Function()? supportsPlatform,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _recognizer = recognizer ?? _coverTitleOcrWorker.recognize,
       _imageSizeReader = imageSizeReader ?? _readImageSize,
       _supportsPlatform =
           supportsPlatform ??
           (() =>
               Platform.isAndroid ||
               Platform.isIOS ||
               Platform.isMacOS ||
               Platform.isWindows);

  final Future<Directory> Function() _directoryProvider;
  final CoverTitleRecognizer _recognizer;
  final CoverImageSizeReader _imageSizeReader;
  final bool Function() _supportsPlatform;
  final Map<String, CoverTitleFocus?> _memory = {};
  final Map<String, Completer<CoverTitleFocus?>> _pending = {};

  Future<CoverTitleFocus?> resolve(String? imagePath, String title) async {
    final normalizedTitle = normalizeCoverTitle(title);
    if (!_supportsPlatform() || imagePath == null || normalizedTitle.isEmpty) {
      return null;
    }
    final image = File(imagePath);
    if (!await image.exists()) return null;
    final stat = await image.stat();
    final key = sha256
        .convert(
          utf8.encode(
            '$imagePath|${stat.size}|${stat.modified.microsecondsSinceEpoch}|$normalizedTitle|$_modelCacheVersion',
          ),
        )
        .toString();
    if (_memory.containsKey(key)) return _memory[key];
    final pending = _pending[key];
    if (pending != null) return await pending.future;

    final completer = Completer<CoverTitleFocus?>();
    _pending[key] = completer;
    unawaited(_completePending(key, image, title, completer));
    return completer.future;
  }

  Future<void> _completePending(
    String key,
    File image,
    String title,
    Completer<CoverTitleFocus?> completer,
  ) async {
    try {
      completer.complete(await _resolveUncached(key, image, title));
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _pending.remove(key);
    }
  }

  Future<CoverTitleFocus?> _resolveUncached(
    String key,
    File image,
    String title,
  ) async {
    final cacheDirectory = Directory(
      p.join((await _directoryProvider()).path, 'cover-title-focus'),
    );
    final cacheFile = File(p.join(cacheDirectory.path, '$key.json'));
    final cached = await _readCache(cacheFile);
    if (cached.found) {
      _memory[key] = cached.focus;
      return cached.focus;
    }

    final imageBytes = await image.readAsBytes();
    final imageSize = await _imageSizeReader(imageBytes);
    // 模型按最短边预处理，不会缩小大封面；先限制长边以约束推理内存。
    final ratio = math.min(1.0, 1536 / imageSize.longestSide);
    final recognitionSize = Size(
      (imageSize.width * ratio).roundToDouble(),
      (imageSize.height * ratio).roundToDouble(),
    );
    final lines = await _recognizer(
      ratio == 1
          ? imageBytes
          : await _resizeCoverForOcr(imageBytes, recognitionSize),
    );
    final pixelBounds = findCoverTitleBounds(title, lines);
    final focus = pixelBounds == null || imageSize.isEmpty
        ? null
        : CoverTitleFocus(
            imageSize: imageSize,
            titleBounds: Rect.fromLTRB(
              (pixelBounds.left / recognitionSize.width).clamp(0.0, 1.0),
              (pixelBounds.top / recognitionSize.height).clamp(0.0, 1.0),
              (pixelBounds.right / recognitionSize.width).clamp(0.0, 1.0),
              (pixelBounds.bottom / recognitionSize.height).clamp(0.0, 1.0),
            ),
          );
    _memory[key] = focus;
    await _writeCache(cacheFile, focus);
    return focus;
  }

  Future<({bool found, CoverTitleFocus? focus})> _readCache(
    File cacheFile,
  ) async {
    if (!await cacheFile.exists()) return (found: false, focus: null);
    try {
      final value = jsonDecode(await cacheFile.readAsString());
      if (value is Map<String, dynamic> &&
          value['version'] == 1 &&
          value.containsKey('focus')) {
        if (value['focus'] == null) return (found: true, focus: null);
        final focus = CoverTitleFocus.fromJson(value['focus']);
        if (focus != null) return (found: true, focus: focus);
      }
    } on FormatException {
      // 缓存损坏时重新识别；不影响封面显示。
    } on FileSystemException {
      // 缓存不可读时重新识别。
    }
    return (found: false, focus: null);
  }

  Future<void> _writeCache(File file, CoverTitleFocus? focus) async {
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'focus': focus?.toJson()}),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } on FileSystemException {
      // OCR 仍可用于本次绘制；缓存写入失败只会导致下次重新识别。
    }
  }
}

final _coverTitleOcrWorker = _CoverTitleOcrWorker();
final coverTitleFocusStore = BookCoverTitleFocusStore();

Future<Uint8List> _resizeCoverForOcr(Uint8List bytes, Size size) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: size.width.toInt(),
    targetHeight: size.height.toInt(),
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final encoded = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return encoded!.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<Size> _readImageSize(Uint8List imageBytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

class _CoverTitleOcrWorker {
  Future<void>? _startup;
  SendPort? _commands;
  Isolate? _isolate;
  ReceivePort? _responses;
  Completer<void>? _ready;
  int _nextRequestId = 0;
  final Map<int, Completer<List<CoverTitleLine>>> _pending = {};

  Future<List<CoverTitleLine>> recognize(Uint8List imageBytes) async {
    await _ensureStarted();
    final id = ++_nextRequestId;
    final completer = Completer<List<CoverTitleLine>>();
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
        _coverTitleOcrWorkerMain,
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
      _stop(StateError('封面识别中断：$detail'));
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

  List<CoverTitleLine> _decodeLines(Object? value) {
    if (value is! List) return [];
    return [
      for (final item in value)
        if (item is Map &&
            item['text'] is String &&
            item['bounds'] is List &&
            (item['bounds'] as List).length == 4)
          (
            text: item['text'] as String,
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
Future<void> _coverTitleOcrWorkerMain(Map<String, Object?> message) async {
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
