import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/epub/resource_index.dart';
import 'package:reader_core/txt.dart';

import '../library/library_store.dart';

class TxtBookInfo {
  const TxtBookInfo({
    required this.options,
    required this.encoding,
    required this.sourceDigest,
  });

  final ChapterDetectionOptions options;
  final String encoding;
  final String sourceDigest;
}

/// 书籍当前 EPUB 是唯一正文来源；规则页面不能回退到导入时的 TXT。
class TxtBookService {
  const TxtBookService(this.library);

  final LibraryStore library;

  Future<bool> canRechapter(BookEntry entry) async =>
      library.supportsPersistence && await info(entry) != null;

  Future<TxtBookInfo?> info(BookEntry entry) async {
    if (entry.filePath.isEmpty) return null;
    final archive = await EpubArchive.fromFile(
      File(entry.filePath),
      verify: false,
    );
    try {
      final opfPath = EpubContainer.parse(archive).rootfilePath;
      final package = OpfParser.parse(archive.readString(opfPath)!);
      final item = package.itemById(txtMetadataManifestId);
      if (item == null) return null;
      final path = ResourceIndex.build(
        archive: archive,
        manifest: package.manifest,
        opfPath: opfPath,
      ).resolve(item.href, baseDir: p.posix.dirname(opfPath));
      if (path == null) return null;
      final content = archive.readString(path);
      if (content == null) return null;
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json['schema'] != 1) return null;
      return TxtBookInfo(
        options: ChapterDetectionOptions.fromJson(
          json['options'] as Map<String, dynamic>,
        ),
        encoding: json['encoding'] as String,
        sourceDigest: json['sourceDigest'] as String,
      );
    } finally {
      archive.close();
    }
  }

  Future<bool> hasDraft(BookEntry entry) async =>
      await library.loadEditDraft(entry.id, allowStale: true) != null;

  Future<EpubRechapterPreview> preview(
    BookEntry entry,
    ChapterDetectionOptions options, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final current = await _current(entry);
    if (await hasDraft(current)) {
      throw const LibraryImportException('本书有未完成的编辑草稿，请先在编辑器保存或放弃草稿');
    }
    return EpubRechapterService.preview(
      File(current.filePath),
      options: options,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  Future<BookEntry> apply(
    BookEntry entry,
    EpubRechapterPreview preview, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final current = await _current(entry);
    if (current.contentRevision != preview.baseRevision ||
        current.filePath != preview.sourceFile.path) {
      throw const LibraryImportException(
        '书籍已更新，请重新预览章节',
        errorCode: 'E_STALE_REVISION',
      );
    }
    final stage = await Directory.systemTemp.createTemp(
      'spectacular-rechapter-',
    );
    try {
      final file = File('${stage.path}/book.epub');
      final summary = await EpubRechapterService.write(
        preview,
        file,
        onProgress: (value) => onProgress?.call(value * 0.7),
        isCancelled: isCancelled,
      );
      final saved = await library.commitEditedFile(
        entry.id,
        preview.baseRevision,
        file,
        summary,
        preserveTextPositions: true,
        elementCfiMap: preview.elementCfiMap,
        requireNoDraft: true,
        isCancelled: isCancelled,
      );
      onProgress?.call(1);
      return saved;
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<BookEntry> restorePrevious(BookEntry entry) async {
    final current = await _current(entry);
    final versions = await library.editVersions(entry.id);
    final previous = versions
        .where((version) => version.kind == 'previous')
        .firstOrNull;
    if (previous == null) throw const LibraryImportException('没有可恢复的上一版本');
    return library.commitEditedFile(
      entry.id,
      current.contentRevision!,
      previous.sourceFile,
      const EpubEditSummary(changedPaths: {}, cssOnly: false),
      requireNoDraft: true,
    );
  }

  Future<BookEntry> _current(BookEntry entry) async {
    final current = await library.bookById(entry.id);
    if (current == null || await info(current) == null) {
      throw const LibraryImportException('只有 TXT 转入的书籍可以按正则重新分章');
    }
    if (current.contentRevision != entry.contentRevision) {
      throw const LibraryImportException(
        '书籍已更新，请重新打开章节正则',
        errorCode: 'E_STALE_REVISION',
      );
    }
    return current;
  }
}
