import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../epub/epub_document.dart';
import 'chapter_detector.dart';
import 'txt_decoding.dart';
import 'txt_models.dart';
import 'txt_package.dart';
import 'txt_worker.dart';

abstract final class TxtEpubConverter {
  static Future<TxtConversionResult> convertFile(
    File source,
    File target, {
    String? title,
    String? encoding,
    ChapterDetectionOptions options = const ChapterDetectionOptions(),
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => _convert(
    source.path,
    null,
    target,
    title,
    encoding,
    options,
    onProgress,
    isCancelled,
  );

  static Future<TxtConversionResult> convertBytes(
    Uint8List bytes,
    File target, {
    String? title,
    String? encoding,
    ChapterDetectionOptions options = const ChapterDetectionOptions(),
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => _convert(
    null,
    bytes,
    target,
    title,
    encoding,
    options,
    onProgress,
    isCancelled,
  );

  static Future<TxtConversionResult> _convert(
    String? path,
    Uint8List? bytes,
    File target,
    String? title,
    String? encoding,
    ChapterDetectionOptions options,
    void Function(double)? progress,
    bool Function()? cancelled,
  ) async {
    if (await target.exists()) {
      throw const TxtConversionException('E_TXT_TARGET', '转换目标必须是新文件');
    }
    if (cancelled?.call() == true) {
      throw const TxtConversionException('E_CANCELLED', '已取消');
    }
    await target.parent.create(recursive: true);
    final temporary = await target.parent.createTemp('.txt-convert-');
    try {
      final result = await runTxtWorker<TxtConversionResult>(
        _conversionWorker,
        (
          path: path,
          bytes: bytes,
          target: '${temporary.path}/book.epub',
          title: title ?? '未命名书籍',
          encoding: encoding,
          options: options,
        ),
        onProgress: progress,
        isCancelled: cancelled,
      );
      if (cancelled?.call() == true) {
        throw const TxtConversionException('E_CANCELLED', '已取消');
      }
      if (await target.exists()) {
        throw const TxtConversionException('E_TXT_TARGET', '转换目标已存在');
      }
      await result.file.rename(target.path);
      return TxtConversionResult(
        filePath: target.path,
        sourceDigest: result.sourceDigest,
        encoding: result.encoding,
        detection: result.detection,
      );
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }
}

typedef _ConversionInput = ({
  String? path,
  Uint8List? bytes,
  String target,
  String title,
  String? encoding,
  ChapterDetectionOptions options,
});

void _conversionWorker(TxtWorkerRequest request) async {
  Uint8List? sample;
  try {
    final input = request.input as _ConversionInput;
    request.output.send(('progress', 0.02));
    final source = _TxtInput(input.path, input.bytes);
    sample = await source.sample();
    if (sample.isEmpty) {
      throw const TxtConversionException('E_TXT_EMPTY', 'TXT 文件为空');
    }
    final encoding = selectTxtEncoding(sample, input.encoding);
    final decoded = await _readLines(
      source,
      encoding,
      (value) => request.output.send(('progress', value * 0.35)),
    );
    if (decoded.blocks.isEmpty) {
      throw const TxtConversionException('E_TXT_EMPTY', 'TXT 文件没有正文');
    }
    request.output.send(('watch', true));
    final detection = ChapterDetector.detect(
      decoded.blocks,
      options: input.options,
      onProgress: (value) =>
          request.output.send(('progress', 0.35 + value * 0.3)),
    );
    request.output.send(('watch', false));
    if (detection.boundaries.isEmpty) {
      throw const TxtConversionException('E_TXT_RULE_NO_MATCH', '章节正则没有匹配结果');
    }
    writeTxtEpub(
      input.target,
      decoded.blocks,
      detection,
      title: input.title,
      sourceDigest: decoded.digest,
      encoding: encoding,
      options: input.options,
      onProgress: (value) =>
          request.output.send(('progress', 0.65 + value * 0.3)),
    );
    await _validate(File(input.target));
    request.output.send((
      'result',
      TxtConversionResult(
        filePath: input.target,
        sourceDigest: decoded.digest,
        encoding: encoding,
        detection: detection,
      ),
    ));
  } on FormatException catch (error) {
    request.output.send((
      'error',
      TxtConversionException(
        'E_TXT_ENCODING',
        'TXT 解码失败，请检查编码：${error.message}',
        encodingCandidates: sample == null
            ? const []
            : txtEncodingCandidates(sample),
      ),
    ));
  } catch (error) {
    request.output.send(('error', error));
  }
}

class _TxtInput {
  _TxtInput(this.path, this.bytes);
  final String? path;
  final Uint8List? bytes;

  Future<Uint8List> sample() async {
    if (bytes case final data?) {
      return Uint8List.sublistView(data, 0, data.length.clamp(0, 65536));
    }
    final file = await File(path!).open();
    try {
      return await file.read(65536);
    } finally {
      await file.close();
    }
  }

  Stream<List<int>> read() async* {
    if (bytes case final data?) {
      for (var i = 0; i < data.length; i += 65536) {
        yield Uint8List.sublistView(data, i, (i + 65536).clamp(0, data.length));
      }
    } else {
      yield* File(path!).openRead();
    }
  }

  Future<int> get length async => bytes?.length ?? await File(path!).length();
}

Future<({List<String> blocks, String digest})> _readLines(
  _TxtInput source,
  String encoding,
  void Function(double) progress,
) async {
  final digest = _DigestSink();
  final hashing = sha256.startChunkedConversion(digest);
  final length = await source.length;
  var read = 0;
  Stream<List<int>> input() async* {
    await for (final chunk in source.read()) {
      hashing.add(chunk);
      read += chunk.length;
      progress(read / length);
      yield chunk;
    }
    hashing.close();
  }

  final blocks = <String>[];
  var first = true;
  await for (var line in const LineSplitter().bind(
    decodeTxtStream(input(), encoding),
  )) {
    if (first) {
      line = line.replaceFirst(RegExp(r'^\uFEFF'), '');
      first = false;
    }
    if (_invalidXml.hasMatch(line)) {
      throw const FormatException('正文含无法解码或 EPUB 不支持的控制字符');
    }
    // 首次转换统一由 CSS 缩进；只去段首空格，不改行内空白。
    if (line.trim().isEmpty) continue;
    line = line.replaceFirst(_leadingIndent, '');
    _appendLongLine(blocks, line);
  }
  return (blocks: blocks, digest: digest.value.toString());
}

final _invalidXml = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]');
final _leadingIndent = RegExp(r'^[ \t　]+');

void _appendLongLine(List<String> blocks, String line) {
  var start = 0;
  while (start < line.length) {
    var end = (start + 10000).clamp(0, line.length);
    if (end < line.length &&
        line.codeUnitAt(end - 1) >= 0xd800 &&
        line.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    blocks.add(line.substring(start, end));
    start = end;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<void> _validate(File file) async {
  final opened = await openEpubFile(file, verifyCrc: true);
  try {
    if (opened.document == null || !opened.report.ok) {
      throw TxtConversionException(
        'E_TXT_EPUB',
        '生成 EPUB 校验失败：${opened.report.message}',
      );
    }
  } finally {
    opened.document?.archive.close();
  }
}
