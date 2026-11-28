import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/font_mapping_inspector.dart';

import '../ocr/local_ocr_worker.dart';

typedef ReaderImageRecognizer = Future<List<LocalOcrLine>> Function(Uint8List);

/// 封面和选区共用同一个离线 OCR worker；只对可见字形取字，不上传内容。
class ReaderSelectionOcr {
  ReaderSelectionOcr({ReaderImageRecognizer? recognize})
    : _recognize = recognize ?? localOcrWorker.recognizeLine;

  final ReaderImageRecognizer _recognize;
  static final _fontResults = <String, bool>{};
  final _lineResults = <String, Future<String>>{};

  /// 图片摘要同时区分选区、字体与字号；只缓存成功结果，不持有图片数据。
  /// 正在识别的同一行共享任务，失败后可立即重试。
  Future<String> recognize(Uint8List image) async {
    final key = sha256.convert(image).toString();
    final existing = _lineResults.remove(key);
    if (existing != null) {
      _lineResults[key] = existing;
      return existing;
    }
    final task = _recognizeText(image);
    _lineResults[key] = task;
    if (_lineResults.length > 64) {
      unawaited(_lineResults.remove(_lineResults.keys.first));
    }
    try {
      return await task;
    } catch (_) {
      if (identical(_lineResults[key], task)) {
        unawaited(_lineResults.remove(key));
      }
      rethrow;
    }
  }

  Future<String> _recognizeText(Uint8List image) async {
    final lines = await _recognize(image);
    if (lines.isEmpty || lines.any((line) => line.confidence < .75)) {
      throw const FormatException('未能可靠识别所选文字，请调整选区后重试');
    }
    final sorted = [...lines]
      ..sort(
        (a, b) =>
            (a.bounds.center.dy - b.bounds.center.dy).abs() <
                (a.bounds.height + b.bounds.height) / 4
            ? a.bounds.left.compareTo(b.bounds.left)
            : a.bounds.top.compareTo(b.bounds.top),
      );
    final text = sorted.map((line) => line.text.trim()).join();
    if (text.isEmpty) throw const FormatException('未识别到文字，请重新选择');
    return text;
  }

  /// 字形名被删的字体先以 cmap 乱序筛选，再用 OCR 对照两行样字。
  /// 不把“乱序”本身作为判定，不依赖书名、类名或资源名称。
  /// null 表示候选字体无法确认；仍可阅读，但文字操作须经 OCR，不能退回乱码。
  Future<bool?> requiresOcr(EpubDocumentImpl document) async {
    var uncertain = false;
    for (final path in document.archive.names) {
      if (!const {
        '.ttf',
        '.otf',
      }.contains(p.posix.extension(path).toLowerCase())) {
        continue;
      }
      final href = Uri(
        path: p.posix.relative(path, from: p.posix.dirname(document.opfPath)),
      ).toString();
      Uint8List? bytes;
      try {
        bytes = await document.readFontBytes(href);
      } on FormatException {
        uncertain = true;
        continue;
      }
      if (bytes == null) continue;
      final suspicious = await _inspectFont(bytes);
      if (suspicious == null) {
        uncertain = true;
        continue;
      }
      if (suspicious) return true;
    }
    return uncertain ? null : false;
  }

  Future<bool?> _inspectFont(Uint8List bytes) async {
    final key = sha256.convert(bytes).toString();
    if (_fontResults.containsKey(key)) return _fontResults[key];
    final inspection = await Isolate.run(
      () => (
        FontMappingInspector.inspect(bytes).reason,
        FontMappingInspector.visualProbe(bytes),
      ),
    );
    final suspicious = inspection.$1 != null
        ? true
        : inspection.$2 == null
        ? false
        : await _confirmFont(key, bytes, inspection.$2!);
    if (suspicious != null) {
      if (_fontResults.length >= 64) {
        _fontResults.remove(_fontResults.keys.first);
      }
      _fontResults[key] = suspicious;
    }
    return suspicious;
  }

  Future<bool?> _confirmFont(String key, Uint8List bytes, String sample) async {
    try {
      return await _compareFont(key, bytes, sample);
    } on Object {
      // 模型不可用或识别不足不能让书籍无法打开，也不能判为普通字体。
      return null;
    }
  }

  Future<bool> _compareFont(String key, Uint8List bytes, String sample) async {
    final family = 'ocr_probe_$key';
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    var mismatched = 0;
    for (var start = 0; start < 24; start += 12) {
      final expected = sample.substring(start, start + 12);
      final lines = await _recognize(await _sampleImage(family, expected));
      if (lines.isEmpty || lines.any((line) => line.confidence < .85)) {
        throw const FormatException('无法确认书内字体文字映射，请重试');
      }
      final text = lines
          .map((line) => line.text)
          .join()
          .replaceAll(RegExp(r'\s'), '');
      if (text.runes.length < 8) throw const FormatException('字体样字识别不完整，请重试');
      final overlap = text.runes.where(expected.runes.toSet().contains).length;
      if (overlap / text.runes.length < .35) mismatched++;
    }
    return mismatched == 2;
  }

  Future<Uint8List> _sampleImage(String family, String expected) async {
    final painter = TextPainter(
      text: TextSpan(
        text: expected,
        style: TextStyle(
          fontFamily: family,
          fontSize: 42,
          color: const Color(0xff000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xffffffff), BlendMode.src);
    painter.paint(canvas, const Offset(16, 16));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (painter.width + 32).ceil(),
      (painter.height + 32).ceil(),
    );
    painter.dispose();
    picture.dispose();
    try {
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      return encoded!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
