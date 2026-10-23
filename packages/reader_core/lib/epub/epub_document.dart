import 'dart:typed_data';

import '../src/api/models.dart';
import '../src/api/interfaces.dart';
import 'archive_reader.dart';
import 'container.dart';
import 'epub_exception.dart';
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

    final container = EpubContainer.parse(archive);
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

  @override
  Future<SpineDocument> readSpine(int spineIndex) {
    throw UnimplementedError('P1-14 起实现文档树解析');
  }
}
