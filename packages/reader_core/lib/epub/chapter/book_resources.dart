import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/epub/xml_encoding.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/source/chapter_source.dart';

import '../../util/bounded_cache.dart';
import 'cancellable_isolate_worker.dart';
import 'chapter_preparation_job.dart';
import 'chapter_resource_dependencies.dart';
import 'network_image_loader.dart';

/// 一本书的归档与原始资源所有者；章节布局和缓存不持有关闭权限。
class BookResources {
  BookResources(
    this.document, {
    this.trackDependencies = false,
    Future<Directory> Function()? networkImageCacheDirectoryProvider,
  }) : _networkImages = NetworkImageLoader(
         directoryProvider: networkImageCacheDirectoryProvider,
       );
  final bool trackDependencies;
  final NetworkImageLoader _networkImages;

  static const imageHeaderProbeBytes = 256 * 1024;
  static const imageIntrinsicCacheLimit = 512;
  static const chapterIndexCacheLimit = 3;
  final EpubDocumentImpl document;
  final _imageIntrinsicCache = BoundedCache<String, ImageIntrinsicSize>(
    imageIntrinsicCacheLimit,
  );
  final _imageIntrinsicMiss = BoundedCache<String, bool>(
    imageIntrinsicCacheLimit,
  );
  final _footnoteReferenceCache =
      BoundedCache<int, Map<String, FootnoteAnchor>>(chapterIndexCacheLimit);
  final _parsed = BoundedCache<int, _ChapterResources>(chapterIndexCacheLimit);
  final _preparing = ChapterPreparationScheduler();
  final _preparingFootnotes = ChapterPreparationScheduler();
  final _imageReads = <String, Future<Uint8List?>>{};
  final preparationWorker = CancellableIsolateWorker();
  Map<String, int>? _spinePaths;
  Set<String>? _fontDirectories;
  bool _closed = false;
  int _prepareEpoch = 0;

  bool get isClosed => _closed;
  int get imageCacheCount => _imageIntrinsicCache.length;
  int get footnoteCacheCount => _footnoteReferenceCache.length;

  /// 关闭发出取消后，等待实际 isolate 退出及端口释放。
  Future<void> get preparationsStopped async {
    await Future.wait([
      _preparing.idle,
      _preparingFootnotes.idle,
      preparationWorker.idle,
      ..._imageReads.values.map(
        (read) => read.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    ]);
  }

  String chapterBase(int spineIndex) {
    final item = document.spine[spineIndex];
    return p.posix.dirname(
      document.resources.resolve(
            item.href,
            baseDir: p.posix.dirname(document.opfPath),
          ) ??
          item.href,
    );
  }

  /// 解压、文字解码和解析共用准备 isolate，归档凭据始终留在宿主。
  Future<ParsedDocument> prepareChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    Future<void>? cancelSignal,
  }) => awaitPreparation(
    scheduleChapter(spineIndex, priority: priority),
    cancelSignal: cancelSignal,
  );

  ChapterPreparationHandle<ParsedDocument> scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) => mapPreparation(
    _scheduleResources(spineIndex, priority: priority),
    (prepared) => prepared.document,
  );

  ChapterPreparationHandle<_ChapterResources> _scheduleResources(
    int spineIndex, {
    required ChapterLayoutPriority priority,
  }) {
    if (_closed) return cancelledPreparation();
    final cached = _parsed[spineIndex];
    if (cached != null) return completedPreparation(cached);
    final epoch = _prepareEpoch;
    return _preparing.schedule(
      'chapter:$spineIndex@$epoch',
      (task) => _parseAsync(spineIndex, epoch, task),
      priority: priority,
    );
  }

  Future<_ChapterResources> _parseAsync(
    int spineIndex,
    int epoch,
    PreparationTask task,
  ) async {
    late EpubEntryRead read;
    late String path;
    final result = await task.wait(
      preparationWorker.schedule(
        'parse:$spineIndex@$epoch',
        () {
          _checkPreparation(epoch);
          path = _chapterPath(spineIndex);
          read = document.archive.prepareEntry(path) ?? _missingChapter(path);
          return (
            payload: read.payload,
            spine: spineIndex,
            path: path,
            trackDependencies: trackDependencies,
          );
        },
        _parseChapterEntry,
        priority: task.priority,
      ),
    );
    _checkPreparation(epoch);
    task.check();
    if (!document.archive.commitEntry(read, result.error)) {
      throw const ChapterLoadCancelled();
    }
    final parsed = result.parsed ?? _missingChapter(path);
    _parsed[spineIndex] = parsed;
    return parsed;
  }

  void _checkPreparation(int epoch) {
    if (_closed || epoch != _prepareEpoch) throw const ChapterLoadCancelled();
  }

  /// 同步读取已准备的章节，不在读取时解压或解析文档。
  ParsedDocument parsedChapter(int spineIndex) {
    final prepared = _parsed[spineIndex];
    if (prepared == null) throw StateError('章节资源尚未准备，请先等待资源准备任务完成');
    return prepared.document;
  }

  Future<List<CssStyleSource>> prepareStyleSources(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    Future<void>? cancelSignal,
  }) => awaitPreparation(
    scheduleStyleSources(spineIndex, priority: priority),
    cancelSignal: cancelSignal,
  );

  ChapterPreparationHandle<List<CssStyleSource>> scheduleStyleSources(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) => mapPreparation(
    _scheduleResources(spineIndex, priority: priority),
    (prepared) => prepared.styleSources,
  );

  String _chapterPath(int spineIndex) {
    final href = document.spine[spineIndex].href;
    final base = p.posix.dirname(document.opfPath);
    return document.resources.resolve(href, baseDir: base) ??
        p.posix.normalize(p.posix.join(base, href));
  }

  String? _followingChapterPath(int spineIndex) =>
      spineIndex + 1 < document.spine.length
      ? _chapterPath(spineIndex + 1)
      : null;

  /// 缺失资源也记录规范候选路径，后续补图或补 CSS 时必须失效。
  Set<String> dependencyPaths(String raw, {String baseDir = ''}) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.hasAuthority || uri.path.isEmpty) {
      return const {};
    }
    return {
      ?document.resources.resolve(raw, baseDir: baseDir),
      p.posix.normalize(
        uri.path.startsWith('/')
            ? Uri.decodeComponent(uri.path.substring(1))
            : p.posix.join(baseDir, Uri.decodeComponent(uri.path)),
      ),
    };
  }

  Set<String> chapterDependencies(int spine) {
    final prepared = _parsed[spine]!;
    final path = _chapterPath(spine);
    return {
      path,
      document.opfPath,
      'META-INF/container.xml',
      'META-INF/duokan-extension.xml',
      'META-INF/encryption.xml',
      for (final item in document.package.manifest)
        if (item.properties.contains('nav') ||
            item.id == document.package.tocId)
          ...dependencyPaths(
            item.href,
            baseDir: p.posix.dirname(document.opfPath),
          ),
      for (final asset in prepared.assets)
        ...dependencyPaths(asset, baseDir: p.posix.dirname(path)),
      if (prepared.footnotes case final notes?)
        ...FootnoteParser.targetPaths(
          notes,
          document.archive.names,
          followingPath: _followingChapterPath(spine),
        ),
      for (final anchor
          in _footnoteReferenceCache[spine]?.values ?? <FootnoteAnchor>[])
        ...anchor.noteImages,
    };
  }

  void clearParsed() {
    _prepareEpoch += 1;
    _parsed.clear();
    _preparing.cancelAll();
    _preparingFootnotes.cancelAll();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _prepareEpoch += 1;
    _preparing.close();
    _preparingFootnotes.close();
    _networkImages.close();
    unawaited(preparationWorker.close());
    _parsed.clear();
    _imageIntrinsicCache.clear();
    _imageIntrinsicMiss.clear();
    _footnoteReferenceCache.clear();
    _spinePaths = null;
    _fontDirectories = null;
    document.archive.close();
  }

  /// 构块只读取已准备的直接注释引用。
  Map<String, FootnoteAnchor> footnotes(int spineIndex) {
    final notes = _footnoteReferenceCache[spineIndex];
    if (notes == null) throw StateError('章节注释尚未准备，请先等待注释准备任务完成');
    return notes;
  }

  /// 注释只准备目标章及其直接引用的定义文档，不扫描其它章节。
  Future<Map<String, FootnoteAnchor>> prepareFootnotes(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    Future<void>? cancelSignal,
  }) => awaitPreparation(
    scheduleFootnotes(spineIndex, priority: priority),
    cancelSignal: cancelSignal,
  );

  ChapterPreparationHandle<Map<String, FootnoteAnchor>> scheduleFootnotes(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) {
    if (_closed) return cancelledPreparation();
    final cached = _footnoteReferenceCache[spineIndex];
    if (cached != null) return completedPreparation(cached);
    final epoch = _prepareEpoch;
    return _preparingFootnotes.schedule(
      'footnotes:$spineIndex@$epoch',
      (task) => _prepareFootnotes(spineIndex, epoch, task),
      priority: priority,
    );
  }

  Future<Map<String, FootnoteAnchor>> _prepareFootnotes(
    int spineIndex,
    int epoch,
    PreparationTask task,
  ) async {
    final prepared = await task.wait(
      _scheduleResources(spineIndex, priority: task.priority),
    );
    _checkPreparation(epoch);
    final source = prepared.footnotes;
    final result = source == null
        ? const <String, FootnoteAnchor>{}
        : await _resolveNoteTargets(source, spineIndex, epoch, task);
    _checkPreparation(epoch);
    task.check();
    _footnoteReferenceCache[spineIndex] = result;
    return result;
  }

  Future<Map<String, FootnoteAnchor>> _resolveNoteTargets(
    FootnoteDocument source,
    int spineIndex,
    int epoch,
    PreparationTask task,
  ) async {
    final reads = <EpubEntryRead>[];
    final result = await task.wait(
      preparationWorker.schedule(
        'resolve-footnotes:$spineIndex@$epoch',
        () {
          _checkPreparation(epoch);
          return (source: source, inputs: _noteTargets(source, reads));
        },
        _resolvePreparedFootnotes,
        priority: task.priority,
      ),
    );
    _checkPreparation(epoch);
    task.check();
    for (var index = 0; index < reads.length; index++) {
      if (!document.archive.commitEntry(reads[index], result.errors[index])) {
        throw const ChapterLoadCancelled();
      }
    }
    return result.references;
  }

  List<_ChapterEntry> _noteTargets(
    FootnoteDocument source,
    List<EpubEntryRead> reads,
  ) {
    final result = <_ChapterEntry>[];
    final spines = _spinePaths ??= {
      for (final item in document.spine) _chapterPath(item.index): item.index,
    };
    for (final path in FootnoteParser.targetPaths(
      source,
      document.archive.names,
      followingPath: _followingChapterPath(source.spineIndex),
    )) {
      if (path == source.path) continue;
      final read = document.archive.prepareEntry(path);
      if (read != null) {
        reads.add(read);
        result.add((
          payload: read.payload,
          path: path,
          spine: spines[path] ?? -1,
          trackDependencies: false,
        ));
      }
    }
    return result;
  }

  /// 章内图片 src → 包内路径（相对 OPF 的章目录解析）。
  String imageUrl(int spineIndex, String src) {
    final item = document.spine[spineIndex];
    final chapterBase = p.posix.dirname(
      document.resources.resolve(
            item.href,
            baseDir: p.posix.dirname(document.opfPath),
          ) ??
          item.href,
    );
    return document.resources.resolve(src, baseDir: chapterBase) ?? src;
  }

  /// 包内图片异步读盘并在 worker 解压；网络图片按原网址读取与缓存。
  Future<Uint8List?> readImage(String url) async {
    if (_closed) return null;
    if (url.startsWith('data:')) return _inlineImageBytes(url);
    final uri = _networkImageUri(url);
    if (uri != null) {
      final key = uri.toString();
      final bytes = await _imageReads.putIfAbsent(
        key,
        () => _readNetworkImage(uri),
      );
      return _closed ? null : bytes;
    }
    final tried = <String>{};
    try {
      for (final path in _imagePaths(url)) {
        if (_closed) return null;
        if (!tried.add(path)) continue;
        final bytes = await _imageReads.putIfAbsent(
          path,
          () => _readImageEntry(path),
        );
        if (_closed) return null;
        if (bytes != null) return bytes;
      }
    } on ChapterLoadCancelled {
      // 关闭书籍或准备作业被取消后，旧图片不能回写到新阅读页。
    }
    return null;
  }

  static Uri? _networkImageUri(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? uri.removeFragment()
        : null;
  }

  Future<Uint8List?> _readNetworkImage(Uri uri) async {
    try {
      return await _networkImages.read(uri);
    } finally {
      _imageReads.remove(uri.toString())?.ignore();
    }
  }

  /// 图片测量需要自然尺寸时读取网络资源，失败仍沿用原占位布局。
  Future<ImageIntrinsicSize?> prepareImageIntrinsicSize(String url) async {
    if (_closed) return null;
    final cached = intrinsicSizeOfUrl(url);
    if (cached != null) return cached;
    final uri = _networkImageUri(url);
    if (uri == null) return null;
    final bytes = await readImage(uri.toString());
    if (bytes == null || _closed) return null;
    // 网络入口已经确认是引擎支持的图片，测量只消费其尺寸。
    final size = ImageSizeParser.readImageSize(bytes)!;
    final key = uri.toString();
    _imageIntrinsicMiss.remove(key);
    _imageIntrinsicCache[key] = size;
    return size;
  }

  /// 内嵌图片不属于归档条目；与包内图片共用上层解码和缓存。
  Uint8List? _inlineImageBytes(String url) {
    try {
      final data = UriData.parse(url);
      if (!data.mimeType.toLowerCase().startsWith('image/')) return null;
      return data.contentAsBytes();
    } on FormatException {
      return null;
    }
  }

  Iterable<String> _imagePaths(String url) sync* {
    final direct = url.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (document.archive.contains(direct)) yield direct;
    final resolved = document.resources.resolve(url);
    if (resolved != null) yield resolved;
    for (final item in document.spine.take(64)) {
      final slash = item.href.lastIndexOf('/');
      final base = slash < 0 ? '' : item.href.substring(0, slash);
      final candidate = document.resources.resolve(url, baseDir: base);
      if (candidate != null) yield candidate;
    }
  }

  Future<Uint8List?> _readImageEntry(String path) async {
    try {
      final read = await document.archive.prepareEntryAsync(path);
      if (_closed || read == null) return null;
      final result = await _decodeImageEntry(path, read);
      if (_closed) return null;
      return document.archive.commitEntry(read, result.error)
          ? result.bytes
          : null;
    } finally {
      // 调用方正在等待此 Future，清槽时不再次等待自身。
      _imageReads.remove(path)?.ignore();
    }
  }

  Future<EpubEntryDecodeResult> _decodeImageEntry(
    String path,
    EpubEntryRead read,
  ) async {
    while (!_closed) {
      try {
        return await preparationWorker
            .schedule(
              'image:$path',
              () => read.payload,
              decodeEpubEntry,
              priority: ChapterLayoutPriority.prefetch,
            )
            .result;
      } on ChapterLoadCancelled {
        // 前台章节可抢占图片；仍有等待者时排队重试，不把取消当作缺图。
      }
    }
    throw const ChapterLoadCancelled();
  }

  /// 图片原始尺寸（与 collect 的预取共用缓存；读不到时返回 null）。
  ImageIntrinsicSize? intrinsicSizeOfUrl(String url) {
    final key = _networkImageUri(url)?.toString() ?? url;
    final cached = _imageIntrinsicCache[key];
    if (cached != null) {
      return cached;
    }
    if (_imageIntrinsicMiss.containsKey(key)) {
      return null;
    }
    final bytes = url.startsWith('data:')
        ? _inlineImageBytes(url)
        : document.archive.readHead(url, imageHeaderProbeBytes);
    final size = bytes == null ? null : ImageSizeParser.readImageSize(bytes);
    if (size == null) {
      _imageIntrinsicMiss[key] = true;
    } else {
      _imageIntrinsicCache[key] = size;
    }
    return size;
  }

  Future<Uint8List?> readFont(String url) async {
    if (_closed) return null;
    // 只解析路径，不先读出原字节；所有成功分支统一经过解混淆入口。
    var path = document.archive.contains(url)
        ? url
        : document.resources.resolve(url);
    if (path == null) {
      // 同目录章节只试一次，保留首次出现顺序；缺失字体不逐章重复归一化。
      final directories = _fontDirectories ??= {
        for (final item in document.spine) p.posix.dirname(item.href),
      };
      for (final baseDir in directories) {
        path = document.resources.resolve(url, baseDir: baseDir);
        if (path != null) break;
      }
    }
    return path == null ? null : document.readFontBytes('/$path');
  }
}

typedef _ChapterText = ({
  String xhtml,
  String path,
  int spine,
  bool trackDependencies,
});
typedef _ChapterEntry = ({
  EpubEntryPayload payload,
  String path,
  int spine,
  bool trackDependencies,
});
typedef _ChapterEntryResult = ({_ChapterResources? parsed, String? error});
typedef _FootnoteEntryResult = ({
  Map<String, FootnoteAnchor> references,
  List<String?> errors,
});

Never _missingChapter(String path) =>
    throw EpubException('E_SPINE_MISSING', '章节文件不存在：$path');

class _ChapterResources {
  const _ChapterResources(
    this.document,
    this.styleSources,
    this.footnotes,
    this.assets,
  );
  final ParsedDocument document;
  final List<CssStyleSource> styleSources;
  final FootnoteDocument? footnotes;
  final List<String> assets;
}

_ChapterResources _parseChapterText(_ChapterText input) {
  final parsed = DocumentParser.parse(
    xhtml: input.xhtml,
    spineIndex: input.spine,
  );
  return _ChapterResources(
    parsed,
    CssParser.extractFromXhtml(input.xhtml).sources,
    FootnoteParser.mayContainReferences(input.xhtml)
        ? FootnoteParser.parse(
            spineIndex: input.spine,
            path: input.path,
            xhtml: input.xhtml,
          )
        : null,
    input.trackDependencies ? chapterAssetReferences(parsed) : const [],
  );
}

_ChapterEntryResult _parseChapterEntry(_ChapterEntry input) {
  final decoded = decodeEpubEntry(input.payload);
  final bytes = decoded.bytes;
  return (
    parsed: bytes == null
        ? null
        : _parseChapterText((
            xhtml: decodeXmlBytes(bytes),
            path: input.path,
            spine: input.spine,
            trackDependencies: input.trackDependencies,
          )),
    error: decoded.error,
  );
}

_FootnoteEntryResult _resolvePreparedFootnotes(
  ({FootnoteDocument source, List<_ChapterEntry> inputs}) input,
) {
  final source = input.source;
  final documents = <String, FootnoteDocument>{source.path: source};
  final errors = <String?>[];
  for (final target in input.inputs) {
    final decoded = decodeEpubEntry(target.payload);
    errors.add(decoded.error);
    final bytes = decoded.bytes;
    if (bytes == null) continue;
    documents[target.path] = FootnoteParser.parse(
      spineIndex: target.spine,
      path: target.path,
      xhtml: decodeXmlBytes(bytes),
    );
  }
  final result = <String, FootnoteAnchor>{};
  for (final anchor in FootnoteParser.resolve(
    source: source,
    documents: documents,
  )) {
    result.putIfAbsent(anchor.referenceKey, () => anchor);
  }
  return (references: Map.unmodifiable(result), errors: errors);
}
