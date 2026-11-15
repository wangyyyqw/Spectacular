import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../epub/epub_document.dart';
import '../epub/epub_limits.dart';
import 'editable_document.dart';
import 'epub_edit_session.dart';

/// 写到新的文件，原书替换及书架事务由宿主负责。
abstract final class EpubWriter {
  static Future<void> write(EpubEditSession session, File target) async {
    session.validate();
    if (target.absolute.path == session.baseFile.absolute.path ||
        await target.exists()) {
      throw const EpubEditException('导出目标必须是新文件，不能直接覆盖原书');
    }
    final revision = session.revision;
    final request = (
      source: session.baseFile.path,
      digest: session.baseDigest,
      output: target.absolute.path,
      changes: session.resourceOverrides,
    );
    await Isolate.run(() => _write(request));
    if (session.isClosed || session.revision != revision) {
      await target.delete();
      throw const EpubEditException('导出期间内容已变化，请重试保存');
    }
  }
}

typedef _WriteRequest = ({
  String source,
  String digest,
  String output,
  Map<String, Uint8List?> changes,
});

Future<void> _write(_WriteRequest request) async {
  await _checkBase(request);
  final target = File(request.output);
  await target.parent.create(recursive: true);
  final temporary = await target.parent.createTemp('.epub-edit-');
  final staged = File('${temporary.path}/result.epub');
  try {
    _copyArchive(request, staged);
    await _checkBase(request);
    await _validateOutput(staged);
    if (await target.exists()) throw const EpubEditException('导出目标已被其他操作创建');
    await staged.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> _checkBase(_WriteRequest request) async {
  final digest = await sha256.bind(File(request.source).openRead()).first;
  if (digest.toString() != request.digest) {
    throw const EpubEditException('原书文件已被外部修改，不能覆盖草稿基线');
  }
}

void _copyArchive(_WriteRequest request, File staged) {
  final input = InputFileStream(request.source);
  final output = OutputFileStream(staged.path);
  try {
    _checkSourceZipBudget(input);
    final archive = ZipDecoder().decodeStream(input);
    final encoder = ZipEncoder()..startEncode(output);
    encoder.add(
      ArchiveFile.noCompress('mimetype', 20, 'application/epub+zip'.codeUnits),
    );
    final written = <String>{'mimetype'};
    for (final entry in archive.files) {
      final name = normalizePath(entry.name);
      if (name == 'mimetype') continue;
      if (!written.add(name)) throw EpubEditException('归档含重复资源路径：$name');
      if (request.changes.containsKey(name)) {
        _addChanged(encoder, name, request.changes[name]);
      } else {
        // 保留原压缩内容，不展开图片与字体；输出流按块复制。
        encoder.add(entry, autoClose: false);
      }
    }
    for (final entry in request.changes.entries) {
      if (written.add(entry.key)) _addChanged(encoder, entry.key, entry.value);
    }
    encoder.endEncode(comment: archive.comment);
  } finally {
    output.closeSync();
    input.closeSync();
  }
}

void _checkSourceZipBudget(InputStream input) {
  const limits = EpubArchiveLimits();
  final directory = ZipDirectory()..read(input);
  final budget = EpubDecodeBudget(limits);
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    final failure = limits.entryFailure(
      header.filename,
      header.compressedSize,
      header.uncompressedSize,
    );
    if (failure != null ||
        !budget.admit(
          file.filename,
          file.compressedSize,
          file.uncompressedSize,
        )) {
      throw EpubEditException(failure ?? budget.diagnostics.last);
    }
  }
}

void _addChanged(ZipEncoder encoder, String path, Uint8List? bytes) {
  if (bytes != null) encoder.add(ArchiveFile.bytes(path, bytes));
}

Future<void> _validateOutput(File staged) async {
  final opened = await openEpubFile(staged, verifyCrc: true);
  final document = opened.document;
  try {
    if (document == null ||
        document.archive.diagnostics.any(
          (note) =>
              note.startsWith('E_ZIP_ENTRY_TRUNCATED') ||
              note.startsWith('E_ZIP_RESOURCE_LIMIT'),
        )) {
      throw EpubEditException(
        '导出 EPUB 校验失败：${opened.report.message ?? opened.report.warnings.join('；')}',
      );
    }
  } finally {
    document?.archive.close();
  }
}
