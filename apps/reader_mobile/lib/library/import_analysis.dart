import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_core/api.dart' show BookMeta, ImportReport, SpineItem;
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/opf.dart';

/// isolate 可安全传回的新书导入摘要。
///
/// 不携带 ZIP、XML 节点或样式对象，只保留主线程落盘和写库所需的轻量数据。
class ImportBookSummary {
  const ImportBookSummary({
    required this.meta,
    required this.spine,
    required this.excludedSpineIndexes,
    required this.identifier,
    required this.coverBytes,
    required this.coverExtension,
  });

  /// 书籍元信息。
  final BookMeta meta;

  /// 线性阅读顺序。
  final List<SpineItem> spine;

  /// 不参与进度计算的章节。
  final Set<int> excludedSpineIndexes;

  /// OPF 原始唯一标识；结构兜底包为空。
  final String identifier;

  /// 已从原书取出的封面字节。
  final Uint8List? coverBytes;

  /// 封面文件扩展名。
  final String coverExtension;
}

/// 导入时的整本计算结果：哈希、CRC 校验报告、逐章字数与新书摘要。
class ImportAnalysis {
  const ImportAnalysis(
    this.revision,
    this.checked,
    this.charCounts, {
    this.summary,
  });

  /// 整本 SHA-256。
  final String revision;

  /// 带 CRC 校验的打开结果；document 恒为空，只用于判定与写报告。
  final EpubOpenResult checked;

  /// 逐章正文字符数；打开失败时为空。
  final List<int>? charCounts;

  /// 可用于直接写库的新书摘要；打开失败时为空。
  final ImportBookSummary? summary;

  /// 校验报告，避免调用方再次经过不含文档的打开结果取值。
  ImportReport get report => checked.report;
}

/// isolate 启动与字节复制有固定成本；小文件留在当前线程更快。
const int importAnalysisIsolateThreshold = 256 * 1024;

/// 在后台 isolate 完成整本哈希、CRC 校验与字数统计，导入大书不卡界面。
/// 输入字节会复制一份进 isolate；结果只带基础数据，不复制文档对象。
Future<ImportAnalysis> analyzeImport(Uint8List bytes) {
  if (bytes.length < importAnalysisIsolateThreshold) {
    return _analyze(bytes);
  }
  return Isolate.run(() => _analyze(bytes));
}

/// 先计算摘要并在主 isolate 查询是否已存在；命中时不再打开 ZIP。
///
/// 大文件使用单次 isolate 握手：工作 isolate 先回报摘要，主 isolate 查询
/// 数据库后决定继续解析或退出，避免“哈希 isolate + 解析 isolate”复制两份
/// 整书字节。
Future<ImportAnalysis?> analyzeImportUnlessKnown(
  Uint8List bytes, {
  required Future<bool> Function(String revision) shouldSkip,
}) async {
  if (bytes.length < importAnalysisIsolateThreshold) {
    final revision = sha256.convert(bytes).toString();
    if (await shouldSkip(revision)) return null;
    return _analyze(bytes, revision: revision);
  }

  final revisionPort = ReceivePort();
  final resultPort = ReceivePort();
  final isolate = await Isolate.spawn<_ImportWorkerMessage>(
    _importAnalysisWorker,
    (
      bytes: bytes,
      revisionPort: revisionPort.sendPort,
      resultPort: resultPort.sendPort,
    ),
  );
  try {
    final revisionMessage = await revisionPort.first as _ImportWorkerReply;
    if (revisionMessage.error != null) {
      throw StateError(revisionMessage.error!);
    }
    final revision = revisionMessage.revision!;
    final skip = await shouldSkip(revision);
    revisionMessage.commandPort!.send(!skip);
    if (skip) return null;

    final resultMessage = await resultPort.first as _ImportWorkerReply;
    if (resultMessage.error != null) {
      throw StateError(resultMessage.error!);
    }
    return resultMessage.analysis!;
  } finally {
    revisionPort.close();
    resultPort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

typedef _ImportWorkerMessage = ({
  Uint8List bytes,
  SendPort revisionPort,
  SendPort resultPort,
});

typedef _ImportWorkerReply = ({
  String? revision,
  ImportAnalysis? analysis,
  String? error,
  SendPort? commandPort,
});

Future<void> _importAnalysisWorker(_ImportWorkerMessage message) async {
  final commandPort = ReceivePort();
  late final String revision;
  try {
    revision = sha256.convert(message.bytes).toString();
  } catch (error, stack) {
    message.revisionPort.send((
      revision: null,
      analysis: null,
      error: '$error\n$stack',
      commandPort: null,
    ));
    commandPort.close();
    return;
  }
  message.revisionPort.send((
    revision: revision,
    analysis: null,
    error: null,
    commandPort: commandPort.sendPort,
  ));
  final shouldContinue = await commandPort.first;
  commandPort.close();
  if (shouldContinue != true) return;
  try {
    final analysis = await _analyze(message.bytes, revision: revision);
    message.resultPort.send((
      revision: null,
      analysis: analysis,
      error: null,
      commandPort: null,
    ));
  } catch (error, stack) {
    message.resultPort.send((
      revision: null,
      analysis: null,
      error: '$error\n$stack',
      commandPort: null,
    ));
  }
}

Future<ImportAnalysis> _analyze(Uint8List bytes, {String? revision}) async {
  revision ??= sha256.convert(bytes).toString();
  final parsed = await openEpub(bytes);
  final document = parsed.document;
  if (document == null) return ImportAnalysis(revision, parsed, null);
  final counts = await document.countChapterCharacters();
  final coverPath = document.coverResourcePath;
  try {
    return ImportAnalysis(
      revision,
      EpubOpenResult(report: parsed.report),
      counts,
      summary: ImportBookSummary(
        meta: document.meta,
        spine: List<SpineItem>.unmodifiable(document.spine),
        excludedSpineIndexes: Set<int>.unmodifiable(
          document.progressExcludedSpineIndexes,
        ),
        identifier: _originalIdentifier(document),
        coverBytes: document.readCoverBytes(),
        coverExtension: _coverExtension(coverPath),
      ),
    );
  } finally {
    // 字符扫描和 CRC 校验会缓存解压后的 ZIP 条目；摘要复制完成后立即释放，
    // 避免 isolate 返回前后同时持有整本解压内容。
    document.archive.close();
  }
}

String _originalIdentifier(EpubDocumentImpl document) {
  final source = document.archive.readString(document.opfPath);
  if (source == null) return '';
  try {
    return OpfParser.parse(source).meta.identifier;
  } catch (_) {
    return '';
  }
}

const Set<String> _coverExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
};

String _coverExtension(String? resourcePath) {
  if (resourcePath != null) {
    final dot = resourcePath.lastIndexOf('.');
    if (dot >= 0 && dot + 1 < resourcePath.length) {
      final extension = resourcePath.substring(dot + 1).toLowerCase();
      if (_coverExtensions.contains(extension)) {
        return extension == 'jpeg' ? 'jpg' : extension;
      }
    }
  }
  return 'jpg';
}

/// 用后台结果在主 isolate 取文档：CRC 已校验，这里跳过校验；
/// 报告沿用带 CRC 的版本，告警与原流程一致。
Future<EpubOpenResult> openAnalyzed(
  Uint8List bytes,
  ImportAnalysis analysis,
) async {
  if (analysis.charCounts == null) return analysis.checked;
  final fast = await openEpub(bytes, verifyCrc: false);
  return EpubOpenResult(
    document: fast.document,
    report: analysis.checked.report,
  );
}
