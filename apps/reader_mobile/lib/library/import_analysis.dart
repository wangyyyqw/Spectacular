import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_core/epub/epub_document.dart';

/// 导入时的整本计算结果：哈希、CRC 校验报告与逐章字数。
class ImportAnalysis {
  const ImportAnalysis(this.revision, this.checked, this.charCounts);

  /// 整本 SHA-256。
  final String revision;

  /// 带 CRC 校验的打开结果；document 恒为空，只用于判定与写报告。
  final EpubOpenResult checked;

  /// 逐章正文字符数；打开失败时为空。
  final List<int>? charCounts;
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

Future<ImportAnalysis> _analyze(Uint8List bytes) async {
  final revision = sha256.convert(bytes).toString();
  final parsed = await openEpub(bytes);
  final document = parsed.document;
  if (document == null) return ImportAnalysis(revision, parsed, null);
  final counts = await document.countChapterCharacters();
  return ImportAnalysis(
    revision,
    EpubOpenResult(report: parsed.report),
    counts,
  );
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
