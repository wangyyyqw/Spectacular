part of 'package_editor.dart';

/// 预览仅持有待写入资源，绑定已经保存的 EPUB 摘要。
class EpubRechapterPreview {
  EpubRechapterPreview._({
    required this.sourceFile,
    required this.baseRevision,
    required this.options,
    required this.detection,
    required this.diagnostics,
    required this.elementCfiMap,
    required List<String> samples,
    required Map<String, Uint8List?>? writes,
  }) : _samples = List.unmodifiable(samples),
       _writes = writes == null ? null : Map.unmodifiable(writes);

  final File sourceFile;
  final String baseRevision;
  final ChapterDetectionOptions options;
  final ChapterDetectionResult detection;
  final List<String> diagnostics;

  /// 完整 DOM 节点移动前后的元素 CFI；只供本次受版本校验的迁移使用。
  final Map<String, String> elementCfiMap;
  final List<String> _samples;
  final Map<String, Uint8List?>? _writes;

  bool get canApply => _writes != null && detection.boundaries.isNotEmpty;
  int get chapterCount => detection.boundaries.length;
  int get volumeCount => detection.boundaries.where((e) => e.isVolume).length;
  String sampleForChapter(int index) => _samples[index];
}

/// 仅处理由 TXT 转入的书籍；重分章以当前 EPUB 为真源。
abstract final class EpubRechapterService {
  static Future<EpubRechapterPreview> preview(
    File source, {
    ChapterDetectionOptions options = const ChapterDetectionOptions(),
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkRechapterCancelled(isCancelled);
    final book = await _rechapterWorker<_RechapterBook>(
      'read',
      source.path,
      isCancelled,
    );
    onProgress?.call(0.2);
    final detection = await ChapterDetector.preview(
      book.blocks.map((block) => block.text).toList(),
      options: options,
      candidateBlockIndexes: {
        for (var i = 0; i < book.blocks.length; i++)
          if (book.blocks[i].candidate) i,
      },
      onProgress: (value) => onProgress?.call(0.2 + value * 0.5),
      isCancelled: isCancelled,
    );
    return _finishRechapterPreview(
      source,
      book,
      detection,
      options,
      onProgress,
      isCancelled,
    );
  }

  /// 写入新文件，不移动、覆盖或删除原 EPUB。
  static Future<EpubEditSummary> write(
    EpubRechapterPreview preview,
    File target, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!preview.canApply) throw const EpubEditException('请先生成可应用的目录预览');
    if (await target.exists() ||
        target.absolute.path == preview.sourceFile.absolute.path) {
      throw const EpubEditException('重分章目标必须是新文件');
    }
    _checkRechapterCancelled(isCancelled);
    await target.parent.create(recursive: true);
    final stage = await target.parent.createTemp('.rechapter-');
    try {
      onProgress?.call(0.1);
      final output = File(p.join(stage.path, 'result.epub'));
      final summary = await _rechapterWorker<EpubEditSummary>('write', (
        preview,
        output.path,
      ), isCancelled);
      _checkRechapterCancelled(isCancelled);
      if (await target.exists()) throw const EpubEditException('输出文件已存在');
      await output.rename(target.path);
      onProgress?.call(1);
      return summary;
    } finally {
      await stage.delete(recursive: true);
    }
  }
}

Future<EpubRechapterPreview> _finishRechapterPreview(
  File source,
  _RechapterBook book,
  ChapterDetectionResult detection,
  ChapterDetectionOptions options,
  void Function(double)? progress,
  bool Function()? cancelled,
) async {
  final diagnostics = [...detection.warnings];
  Map<String, Uint8List?>? writes;
  Map<String, String> elementCfiMap = const {};
  if (detection.boundaries.isEmpty) {
    diagnostics.add('没有匹配到章节，请修改正则或选择按长度分节');
  } else {
    final prepared = await _rechapterWorker<_RechapterPrepared>('prepare', (
      source.path,
      book,
      detection,
      options,
    ), cancelled);
    writes = prepared.writes;
    elementCfiMap = prepared.elementCfiMap;
    diagnostics.addAll(prepared.errors);
  }
  _checkRechapterCancelled(cancelled);
  progress?.call(1);
  return EpubRechapterPreview._(
    sourceFile: source.absolute,
    baseRevision: book.revision,
    options: options,
    detection: detection,
    diagnostics: List.unmodifiable(diagnostics),
    elementCfiMap: Map.unmodifiable(elementCfiMap),
    samples: _chapterSamples(book, detection),
    writes: writes,
  );
}

List<String> _chapterSamples(
  _RechapterBook book,
  ChapterDetectionResult result,
) {
  return [
    for (var i = 0; i < result.boundaries.length; i++)
      _rechapterSample(
        book.blocks.sublist(
          result.boundaries[i].blockIndex,
          i + 1 < result.boundaries.length
              ? result.boundaries[i + 1].blockIndex
              : book.blocks.length,
        ),
      ),
  ];
}

String _rechapterSample(List<_RechapterBlock> blocks) {
  final sample = blocks
      .map((e) => e.text)
      .where((e) => e.trim().isNotEmpty)
      .take(6)
      .join('\n');
  if (sample.length <= 220) return sample;
  var end = 220;
  final unit = sample.codeUnitAt(end - 1);
  if (unit >= 0xd800 && unit <= 0xdbff) end--;
  return '${sample.substring(0, end)}…';
}

Future<EpubEditSummary> _writeRechapter(
  EpubRechapterPreview preview,
  File output,
) async {
  final session = await EpubEditSession.open(preview.sourceFile);
  try {
    if (session.baseDigest != preview.baseRevision) {
      throw const EpubEditException('书籍版本已变化，请重新预览章节');
    }
    _applyRechapterWrites(session, preview._writes!);
    session.validate();
    await EpubWriter.write(session, output);
    return session.summary;
  } finally {
    session.close();
  }
}

void _applyRechapterWrites(
  EpubEditSession session,
  Map<String, Uint8List?> writes,
) => session.transaction('按章节正则重新分章', (tx) {
  for (final entry in writes.entries) {
    if (entry.value case final bytes?) {
      tx.writeBytes(entry.key, bytes);
    } else {
      tx.remove(entry.key);
    }
  }
});

void _checkRechapterCancelled(bool Function()? cancelled) {
  if (cancelled?.call() == true) throw const EpubEditException('已取消重新分章');
}

/// 后台解析和写出可被宿主取消；被中止的产物由宿主暂存目录统一清理。
Future<T> _rechapterWorker<T>(
  String operation,
  Object input,
  bool Function()? cancelled,
) async {
  _checkRechapterCancelled(cancelled);
  final port = ReceivePort();
  final result = Completer<T>();
  final subscription = port.listen((message) {
    if (result.isCompleted) return;
    if (message case [true, final value]) {
      result.complete(value as T);
    } else if (message case [false, final error]) {
      result.completeError(EpubEditException('$error'));
    }
  });
  Isolate? worker;
  Timer? timer;
  try {
    worker = await Isolate.spawn(_runRechapterWorker, (
      operation,
      input,
      port.sendPort,
    ));
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!result.isCompleted && cancelled?.call() == true) {
        result.completeError(const EpubEditException('已取消重新分章'));
      }
    });
    return await result.future;
  } finally {
    timer?.cancel();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}

Future<void> _runRechapterWorker((String, Object, SendPort) request) async {
  try {
    final Object result;
    switch (request.$1) {
      case 'read':
        result = await _readRechapterBook(request.$2 as String);
      case 'prepare':
        final input =
            request.$2
                as (
                  String,
                  _RechapterBook,
                  ChapterDetectionResult,
                  ChapterDetectionOptions,
                );
        result = await _prepareRechapter(
          input.$1,
          input.$2,
          input.$3,
          input.$4,
        );
      case 'write':
        final input = request.$2 as (EpubRechapterPreview, String);
        result = await _writeRechapter(input.$1, File(input.$2));
      default:
        throw const EpubEditException('未知重分章任务');
    }
    request.$3.send([true, result]);
  } catch (error) {
    request.$3.send([false, '$error']);
  }
}
