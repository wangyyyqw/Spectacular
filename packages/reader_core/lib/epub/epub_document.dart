import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../css/computed_style.dart';
import '../position/cfi.dart';
import '../src/api/models.dart';
import '../src/api/interfaces.dart';
import 'archive_reader.dart';
import 'container.dart';
import 'epub_exception.dart';
import 'footnote.dart';
import '../parser/cfi_binder.dart';
import '../parser/cfi_resolver.dart';
import '../parser/block_builder.dart';
import '../parser/document_parser.dart';
import '../parser/text_aggregator.dart';
import 'opf.dart';
import 'toc.dart';
import 'resource_index.dart';

/// 打开结果：成功时带文档，失败时只带报告。
class EpubOpenResult {
  const EpubOpenResult({this.document, required this.report});

  /// 成功时的文档。
  final EpubDocumentImpl? document;

  /// 导入报告（成功时 ok=true）。
  final ImportReport report;

  /// 是否打开成功。
  bool get ok => document != null;
}

/// 打开 EPUB；任何失败都转成 [ImportReport]，不抛未捕获异常。
Future<EpubOpenResult> openEpub(Uint8List bytes) async {
  final warnings = <String>[];
  try {
    final archive = EpubArchive.fromBytes(bytes);
    final ocf = archive.validateOcf();
    if (!ocf.ok) {
      return EpubOpenResult(
        report: ImportReport(
          ok: false,
          errorCode: 'E_OCF',
          message: ocf.errors.join('；'),
          warnings: ocf.warnings,
        ),
      );
    }
    warnings.addAll(ocf.warnings);
    // ZIP 恢复档诊断（P7-15）并入报告。
    warnings.addAll(archive.diagnostics);

    // P7-12：container.xml 缺失/损坏时按候选路径扫描 OPF 兜底（诊断
    // 进 warnings，不静默）；全部候选失败保留原拒绝路径。
    final containerParsed = EpubContainer.parseWithFallback(archive);
    final container = containerParsed.$1;
    final containerDiagnostic = containerParsed.$2;
    if (containerDiagnostic != null) {
      warnings.add(containerDiagnostic);
    }
    final opfString = archive.readString(container.rootfilePath);
    if (opfString == null) {
      return EpubOpenResult(
        report: ImportReport(
          ok: false,
          errorCode: 'E_OPF_MISSING',
          message: 'OPF 不存在：${container.rootfilePath}',
          warnings: warnings,
        ),
      );
    }
    final package = OpfParser.parse(opfString);
    warnings.addAll(package.warnings);

    if (package.spine.isEmpty) {
      return EpubOpenResult(
        report: ImportReport(
          ok: false,
          errorCode: 'E_SPINE_EMPTY',
          message: 'spine 为空，无法阅读',
          warnings: warnings,
        ),
      );
    }

    final resources = ResourceIndex.build(
      archive: archive,
      manifest: package.manifest,
      opfPath: container.rootfilePath,
    );
    final tocResult = TocFallback.build(
      archive: archive,
      package: package,
      opfPath: container.rootfilePath,
    );
    warnings.addAll(tocResult.warnings);
    final document = EpubDocumentImpl(
      archive: archive,
      package: package,
      resources: resources,
      opfPath: container.rootfilePath,
      toc: tocResult.entries,
      tocSource: tocResult.source,
      report: ImportReport(
        ok: true,
        warnings: List<String>.unmodifiable(warnings),
        readabilityLevel: warnings.isEmpty ? 0 : 1,
      ),
    );
    return EpubOpenResult(document: document, report: document.report);
  } on EpubException catch (error) {
    return EpubOpenResult(
      report: ImportReport(
        ok: false,
        errorCode: error.code,
        message: error.message,
        warnings: warnings,
      ),
    );
  } catch (error) {
    return EpubOpenResult(
      report: ImportReport(
        ok: false,
        errorCode: 'E_INTERNAL',
        message: '打开失败：$error',
        warnings: warnings,
      ),
    );
  }
}

/// [openEpub] 的类入口，便于后续替换为 `EpubDocument.open`。
abstract final class EpubDocumentFactory {
  /// 打开 EPUB。
  static Future<EpubOpenResult> open(Uint8List bytes) => openEpub(bytes);
}

/// [EpubDocument] 的默认实现。
class EpubDocumentImpl implements EpubDocument {
  /// 创建文档。
  EpubDocumentImpl({
    required this.archive,
    required this.package,
    required this.resources,
    required this.opfPath,
    required List<TocEntry> toc,
    required this.tocSource,
    required this.report,
  }) : toc = List<TocEntry>.unmodifiable(toc);

  /// ZIP 容器。
  final EpubArchive archive;

  /// 解析后的 OPF。
  final OpfPackage package;

  /// 资源索引。
  final ResourceIndex resources;

  /// OPF 路径。
  final String opfPath;

  @override
  final ImportReport report;

  @override
  BookMeta get meta => package.meta;

  @override
  List<SpineItem> get spine => List<SpineItem>.unmodifiable(package.spine);

  @override
  final List<TocEntry> toc;

  /// 目录来源：nav / ncx / spine。
  final String tocSource;

  /// 把指定 spine 聚合为可测量文本块树。
  ///
  /// [whiteSpace] 决定空白与换行如何保留（默认 `normal`）。
  BlockDocument aggregateText(
    int spineIndex, {
    CssWhiteSpace whiteSpace = CssWhiteSpace.normal,
  }) =>
      TextAggregator.aggregate(parseBlocks(spineIndex), whiteSpace: whiteSpace);

  /// 把指定 spine 按 display 构建为块树。
  BlockDocument parseBlocks(int spineIndex) =>
      BlockBuilder.build(parseDocument(spineIndex));

  /// 把指定 spine 解析为节点树。
  ParsedDocument parseDocument(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return DocumentParser.parse(xhtml: xhtml, spineIndex: spineIndex);
  }

  /// 解析指定 spine 的文本节点并绑定 CFI。
  BoundDocument bindCfi(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return CfiBinder.bind(xhtml: xhtml, spineIndex: spineIndex);
  }

  /// 在当前章节中容错解析 CFI；失败返回 warning 而不抛异常。
  CfiResolution resolveCfi(int spineIndex, EpubCfi target) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      return const CfiResolution(warnings: <String>['章节文件不存在']);
    }
    return CfiResolver.resolve(
      xhtml: xhtml,
      target: target,
      expectedSpineIndex: spineIndex,
    );
  }

  /// 解析指定 spine 的注释锚点（单章，不解析跨文档目标）。
  FootnoteDocument parseFootnotes(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return FootnoteParser.parse(
      spineIndex: spineIndex,
      path: resolved,
      xhtml: xhtml,
    );
  }

  @override
  Future<SpineDocument> readSpine(int spineIndex) {
    throw UnimplementedError('P1-14 起实现文档树解析');
  }
}
