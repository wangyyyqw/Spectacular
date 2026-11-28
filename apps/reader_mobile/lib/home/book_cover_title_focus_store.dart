import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_cover_title_focus.dart';
import '../ocr/local_ocr_worker.dart';

typedef CoverTitleRecognizer = Future<List<CoverTitleLine>> Function(
  Uint8List imageBytes,
);
typedef CoverImageSizeReader = Future<Size> Function(Uint8List imageBytes);

const _modelCacheVersion = 'snapfind-ppocrv4-v2';

/// 书名焦点缓存；图片版本或书名变化时重新 OCR。
class BookCoverTitleFocusStore {
  BookCoverTitleFocusStore({
    Future<Directory> Function()? directoryProvider,
    CoverTitleRecognizer? recognizer,
    CoverImageSizeReader? imageSizeReader,
    bool Function()? supportsPlatform,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _recognizer = recognizer ?? _recognizeCoverTitle,
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
  final _resolved = <(String, String, String?), CoverTitleFocus?>{};

  /// 重建拼图时立即复用已识别焦点；后续异步请求仍校验文件版本。
  CoverTitleFocus? peek(String? imagePath, String title, {String? revision}) =>
      _resolved[(imagePath ?? '', normalizeCoverTitle(title), revision)];

  Future<CoverTitleFocus?> resolve(
    String? imagePath,
    String title, {
    String? revision,
  }) async {
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
    final CoverTitleFocus? focus;
    if (_memory.containsKey(key)) {
      focus = _memory[key];
    } else {
      final pending = _pending[key];
      if (pending != null) {
        focus = await pending.future;
      } else {
        final completer = Completer<CoverTitleFocus?>();
        _pending[key] = completer;
        unawaited(_completePending(key, image, title, completer));
        focus = await completer.future;
      }
    }
    final displayKey = (imagePath, normalizedTitle, revision);
    _resolved.remove(displayKey);
    _resolved[displayKey] = focus;
    if (_resolved.length > 128) _resolved.remove(_resolved.keys.first);
    return focus;
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

Future<List<CoverTitleLine>> _recognizeCoverTitle(Uint8List bytes) async => [
  for (final line in await localOcrWorker.recognize(bytes))
    (text: line.text, bounds: line.bounds),
];
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
