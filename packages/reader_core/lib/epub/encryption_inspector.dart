import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'epub_document.dart';
import 'font_mapping_inspector.dart';
import 'importer.dart';
import 'resource_index.dart';

/// “未发现”仅说明未命中已支持的检测规则，不承诺不存在私有加密方式。
enum EpubEncryptionStatus {
  notDetected,
  fontObfuscated,
  suspiciousFontMapping,
  encrypted,
  inconclusive,
}

class EpubEncryptionReport {
  const EpubEncryptionReport(this.status, this.details);

  final EpubEncryptionStatus status;
  final List<String> details;

  String get label => switch (status) {
    EpubEncryptionStatus.notDetected => '未发现加密',
    EpubEncryptionStatus.fontObfuscated => '字体混淆，可正常阅读',
    EpubEncryptionStatus.suspiciousFontMapping => '疑似字体映射混淆',
    EpubEncryptionStatus.encrypted => '已检测到加密',
    EpubEncryptionStatus.inconclusive => '无法完整判断',
  };
}

/// 用户请求时在后台检查，复用正式开书与字体解混淆入口。
/// 不修改 EPUB，不扫描正文，不改变阅读设置和持久化数据。
abstract final class EpubEncryptionInspector {
  static Future<EpubEncryptionReport> inspectFile(String path) =>
      Isolate.run(() async => inspectOpened(await openEpubFile(File(path))));

  static Future<EpubEncryptionReport> inspectBytes(Uint8List bytes) =>
      Isolate.run(
        () async => inspectOpened(await openEpub(bytes, verifyCrc: false)),
      );

  /// 检查已打开的文档，完成后释放归档资源。
  static Future<EpubEncryptionReport> inspectOpened(
    EpubOpenResult opened,
  ) async {
    final document = opened.document;
    if (document == null) {
      final code = opened.report.errorCode;
      final encrypted = code == 'E_EPUB_ENCRYPTED' || code == 'E_ZIP_ENCRYPTED';
      return EpubEncryptionReport(
        encrypted
            ? EpubEncryptionStatus.encrypted
            : EpubEncryptionStatus.inconclusive,
        [
          encrypted
              ? opened.report.message ?? '检测到加密'
              : '书籍无法解析，不能据此判断是否加密；请确认文件完整后重试。',
        ],
      );
    }
    try {
      return await _inspectFonts(document);
    } finally {
      document.archive.close();
    }
  }

  static Future<EpubEncryptionReport> _inspectFonts(
    EpubDocumentImpl doc,
  ) async {
    final details = <String>[];
    final codes = EpubReadability.codesIn(doc.report.warnings);
    var incomplete =
        doc.fontEncryption.parseFailed ||
        codes.contains('E_FONT_OBFUSCATION_FAILED') ||
        codes.contains('E_ZIP_ENTRY_TRUNCATED') ||
        codes.contains('E_ZIP_RESOURCE_LIMIT');
    if (incomplete) details.add('部分声明或资源无法读取，检测范围不完整。');
    final fonts = _fontPaths(doc);
    var suspicious = false;
    for (final path in fonts) {
      final inspection = await _inspectFont(doc, path);
      if (!inspection.readable) {
        incomplete = true;
        details.add('$path：字体格式不受检测支持、缺失或损坏。');
      } else if (inspection.reason != null) {
        suspicious = true;
        details.add('$path：${inspection.reason}。');
      }
    }
    return _fontReport(
      details,
      suspicious: suspicious,
      incomplete: incomplete,
      obfuscatedCount: doc.fontEncryption.entries.length,
      fontCount: fonts.length,
    );
  }

  static EpubEncryptionReport _fontReport(
    List<String> details, {
    required bool suspicious,
    required bool incomplete,
    required int obfuscatedCount,
    required int fontCount,
  }) {
    if (obfuscatedCount > 0) {
      details.insert(0, '检测到 $obfuscatedCount 个 IDPF／Adobe 字体混淆声明，阅读时自动解混淆。');
    }
    if (suspicious) details.add('字体映射检测是启发式判断，可能误报；建议保留书内字体，复制、搜索和朗读可能受影响。');
    details.add('检查了加密声明、DRM 标记和 $fontCount 个字体资源；未发现加密不代表排除了所有私有保护方式。');
    return EpubEncryptionReport(
      suspicious
          ? EpubEncryptionStatus.suspiciousFontMapping
          : incomplete
          ? EpubEncryptionStatus.inconclusive
          : obfuscatedCount > 0
          ? EpubEncryptionStatus.fontObfuscated
          : EpubEncryptionStatus.notDetected,
      List.unmodifiable(details),
    );
  }

  static Set<String> _fontPaths(EpubDocumentImpl doc) {
    final base = p.posix.dirname(doc.opfPath);
    return {
      ...doc.fontEncryption.entries.keys,
      for (final item in doc.package.manifest)
        if (ResourceIndex.classifyMediaType(item.mediaType) == 'font' ||
            item.mediaType.startsWith('font/'))
          doc.resources.resolve(item.href, baseDir: base) ??
              p.posix.normalize(p.posix.join(base, item.href)),
      for (final path in doc.archive.names)
        if (const {
          '.ttf',
          '.otf',
          '.ttc',
          '.woff',
          '.woff2',
        }.contains(p.posix.extension(path).toLowerCase()))
          path,
    };
  }

  static Future<FontMappingInspection> _inspectFont(
    EpubDocumentImpl doc,
    String path,
  ) async {
    final href = Uri(
      path: p.posix.relative(path, from: p.posix.dirname(doc.opfPath)),
    ).toString();
    try {
      final bytes = await doc.readFontBytes(href);
      return bytes == null
          ? const FontMappingInspection(readable: false)
          : FontMappingInspector.inspect(bytes);
    } on FormatException {
      return const FontMappingInspection(readable: false);
    }
  }
}
