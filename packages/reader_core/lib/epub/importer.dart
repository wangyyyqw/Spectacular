import 'archive_reader.dart';
import 'opf.dart';
import 'package:path/path.dart' as p;
import '../src/api/models.dart' show BookMeta, SpineItem;
import 'resource_index.dart';

/// 可读性分级（P3-26，技术方案 §55；判定输入直接消费 P7-05 码表
/// 警告串，不另起判定体系——Reeden 500 号 §1.2 分级哲学同构）。
///
/// - L0 完整：全部可解析；
/// - L1 可修复：引用经索引/嗅探兜底全部可解（导入提示「已自动修复」）；
/// - L2 部分：spine 项缺失、目录退化、资源缺失——能读正文，目录或
///   样式降级；
/// - L3 仅正文：容器/OPF 回退拼装、spine 大量失效——能读，结构异常；
/// - L4 拒绝：无法打开。
abstract final class EpubReadability {
  static const int l0 = 0;
  static const int l1 = 1;
  static const int l2 = 2;
  static const int l3 = 3;
  static const int l4 = 4;

  /// 从警告串提取诊断码（`E_XXX:` 前缀）。
  static Set<String> codesIn(Iterable<String> warnings) => <String>{
        for (final warning in warnings)
          if (RegExp(r'^(E_[A-Z_]+):').firstMatch(warning) != null)
            RegExp(r'^(E_[A-Z_]+):').firstMatch(warning)!.group(1)!,
      };

  /// 分级。
  ///
  /// [spineCount] 为 spine 总项数（L3 的「大量失效」按过半判）；
  /// [missingSpineItems] spine 指向不存在的文件数；[missingResources]
  /// manifest 图片/字体探测后仍找不到的数；[repairedRefs] 经嗅探/索引
  /// 兜底找回的数；[tocFallbackUsed] 目录退化为 spine 顺序。
  static int grade({
    required bool ok,
    required Iterable<String> warnings,
    required int spineCount,
    required int missingSpineItems,
    required int missingResources,
    required int repairedRefs,
    required bool tocFallbackUsed,
  }) {
    if (!ok) {
      return l4;
    }
    final codes = codesIn(warnings);
    // L3：容器/OPF 结构回退拼装，或 spine 大面积失效。
    if (codes.contains('E_CONTAINER_FALLBACK') ||
        codes.contains('E_SPINE_FALLBACK') ||
        (spineCount > 0 && missingSpineItems * 2 > spineCount)) {
      return l3;
    }
    // L2：局部结构损伤——spine 项缺失、资源缺失、目录退化。
    if (missingSpineItems > 0 ||
        missingResources > 0 ||
        tocFallbackUsed ||
        codes.contains('E_FONT_OBFUSCATION_FAILED')) {
      return l2;
    }
    // L1：只有引用级修复（嗅探/索引兜底）。
    if (repairedRefs > 0 || codes.contains('E_RESOURCE_MISSING')) {
      return l1;
    }
    return l0;
  }
}

/// 无 OPF 时的 L3 兜底：按文件名排序把 XHTML 拼成 spine（§55.1）。
///
/// 中文书库里「一堆按序命名的 XHTML」并不罕见，比直接拒绝有价值。
/// 生成的包只有最小 manifest/spine，元信息全部占位。
OpfPackage? buildFallbackPackage(EpubArchive archive) {
  final pages = <String>[
    for (final name in archive.names)
      if (_isChapterName(name)) name,
  ]..sort();
  if (pages.isEmpty) {
    return null;
  }
  final manifest = <OpfManifestItem>[
    for (var i = 0; i < pages.length; i++)
      OpfManifestItem(
        id: 'page$i',
        href: _relativeToRoot(pages[i]),
        mediaType: 'application/xhtml+xml',
      ),
  ];
  return OpfPackage(
    meta: BookMeta(
      // 标题留空：调用方（书库导入）按 文件名→未命名书籍 兜底，避免
      // 占位标题抢占 fallbackTitle（P3-30 真机验收发现）。
      title: '',
      author: '',
      language: '',
      identifier: 'fallback:',
    ),
    manifest: manifest,
    spine: <SpineItem>[
      for (var i = 0; i < pages.length; i++)
        SpineItem(index: i, href: _relativeToRoot(pages[i]), mediaType: 'application/xhtml+xml'),
    ],
    version: '3.0',
    warnings: const <String>[],
  );
}

bool _isChapterName(String name) {
  final lower = name.toLowerCase();
  if (name.startsWith('META-INF/') || lower.startsWith('meta-inf/')) {
    return false;
  }
  return lower.endsWith('.xhtml') || lower.endsWith('.html') ||
      lower.endsWith('.htm');
}

/// spine 为空时的 L3 恢复（对照 Ferrous `epub_fallback_parser.dart`）：
/// 先按 manifest 的章节顺序恢复阅读顺序；manifest 也不可用时，再按文件名
/// 扫描整库 XHTML。两级都失败返回 null，调用方保持 E_SPINE_EMPTY 拒绝。
///
/// [opfPath] 用于把 href 换算成 OPF 目录相对路径，与原管线保持一致。
OpfPackage? recoverSpine({
  required EpubArchive archive,
  required OpfPackage package,
  required String opfPath,
}) {
  final opfDir = _dirOf(opfPath);
  final resources = ResourceIndex.build(
    archive: archive,
    manifest: package.manifest,
    opfPath: opfPath,
  );
  final fromManifest = <SpineItem>[];
  final seen = <String>{};
  for (final item in package.manifest) {
    // 目录文档（properties 含 nav）不算正文，避免恢复出多余章节。
    if (!_isChapterName(item.href) || item.properties.contains('nav')) {
      continue;
    }
    final resolved = resources.resolve(item.href, baseDir: opfDir);
    if (resolved == null || !seen.add(resolved)) {
      continue;
    }
    fromManifest.add(
      SpineItem(
        index: fromManifest.length,
        href: item.href,
        mediaType: item.mediaType,
      ),
    );
  }
  if (fromManifest.isEmpty) {
    return _scannedSpinePackage(archive: archive, package: package, opfDir: opfDir);
  }
  return OpfPackage(
    meta: package.meta,
    manifest: package.manifest,
    spine: fromManifest,
    version: package.version,
    warnings: package.warnings,
    tocId: package.tocId,
    coverItemId: package.coverItemId,
  );
}

/// 二级兜底：manifest 里没有可读章节时，按文件名扫描整库 XHTML。
OpfPackage? _scannedSpinePackage({
  required EpubArchive archive,
  required OpfPackage package,
  required String opfDir,
}) {
  final names = <String>[
    for (final name in archive.names)
      if (_isChapterName(name)) name,
  ]..sort();
  if (names.isEmpty) {
    return null;
  }
  final hrefs = <String>[
    for (final name in names)
      opfDir.isEmpty ? _relativeToRoot(name) : p.posix.relative(name, from: opfDir),
  ];
  // 保留原 manifest 中仍可解析的条目（NCX/nav/CSS/封面 id 供目录与样式使用）。
  final resources = ResourceIndex.build(
    archive: archive,
    manifest: package.manifest,
    opfPath: opfDir.isEmpty ? 'package.opf' : '$opfDir/package.opf',
  );
  final manifest = <OpfManifestItem>[
    for (final item in package.manifest)
      if (resources.resolve(item.href, baseDir: opfDir) != null) item,
    for (var index = 0; index < hrefs.length; index++)
      OpfManifestItem(
        id: 'recovered$index',
        href: hrefs[index],
        mediaType: 'application/xhtml+xml',
      ),
  ];
  return OpfPackage(
    meta: package.meta,
    manifest: manifest,
    spine: <SpineItem>[
      for (var index = 0; index < hrefs.length; index++)
        SpineItem(
          index: index,
          href: hrefs[index],
          mediaType: 'application/xhtml+xml',
        ),
    ],
    version: package.version,
    warnings: package.warnings,
    tocId: package.tocId,
    coverItemId: package.coverItemId,
  );
}

/// 路径所在目录（无目录时返回空串）。
String _dirOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '' : path.substring(0, slash);
}

/// spine href 相对 OPF 目录（L3 包的 OPF 视作在根）。
String _relativeToRoot(String zipPath) =>
    zipPath.startsWith('/') ? zipPath.substring(1) : zipPath;

/// 导入期资源探测（P3-26）：spine 项缺失与 manifest 图片/字体可解性。
class ImportProbeResult {
  const ImportProbeResult({
    required this.missingSpineItems,
    required this.missingResources,
    required this.repairedRefs,
  });

  /// spine 指向不存在文件的项数。
  final int missingSpineItems;

  /// 探测后仍找不到的 manifest 资源数。
  final int missingResources;

  /// 经索引/嗅探兜底找回的引用数（L1 的「已自动修复」提示来源）。
  final int repairedRefs;
}

/// 对打开后的文档做导入期探测；不改写原书。
ImportProbeResult probeImport({
  required EpubArchive archive,
  required OpfPackage package,
  required ResourceIndex resources,
  required String opfDir,
}) {
  var missingSpine = 0;
  var missingResources = 0;
  var repaired = 0;
  for (final item in package.spine) {
    if (resources.resolve(item.href, baseDir: opfDir) == null) {
      missingSpine += 1;
    }
  }
  for (final item in package.manifest) {
    final kind = ResourceIndex.classifyMediaType(item.mediaType);
    if (kind == null) {
      continue;
    }
    final before = resources.fallbackHits;
    final resolved = resources.resolve(item.href, baseDir: opfDir);
    if (resolved != null) {
      if (resources.fallbackHits > before) {
        repaired += 1; // 小写/文件名等兜底命中 = 引用级修复（L1）。
      }
      continue;
    }
    final sniffed = resources.sniffResolve(
      archive,
      item.href,
      baseDir: opfDir,
      mediaType: item.mediaType,
    );
    if (sniffed != null) {
      repaired += 1;
    } else {
      missingResources += 1;
    }
  }
  return ImportProbeResult(
    missingSpineItems: missingSpine,
    missingResources: missingResources,
    repairedRefs: repaired,
  );
}


/// 拒绝文案（P3-27，§55.3）：L4 拒绝时给可读原因与下一步建议。
///
/// 由 P7-05 码表驱动——只做码→文案映射，不散落手写文案（§82.4）；
/// 不暴露堆栈与技术术语。
class RejectionMessage {
  const RejectionMessage({required this.title, required this.suggestion});

  /// 一句话原因。
  final String title;

  /// 下一步建议。
  final String suggestion;
}

abstract final class EpubRejectionMessages {
  /// 按错误码映射文案；未知码回退通用文案（不泄漏内部信息）。
  static RejectionMessage forCode(String? code, String? detail) {
    switch (code) {
      case 'E_DUPLICATE':
        return const RejectionMessage(
          title: '这本书已在书架中',
          suggestion: '请直接从书架打开阅读',
        );
      case 'E_IDENTITY_CONFLICT':
        return const RejectionMessage(
          title: '书籍标识与旧记录冲突，原数据已保留',
          suggestion: '请恢复旧记录的原 EPUB 文件后重试',
        );
      case 'E_ARCHIVE':
        return const RejectionMessage(
          title: '这不是 EPUB 文件（无法解压）',
          suggestion: '请确认文件完整后重新下载或导入',
        );
      case 'E_OCF':
      case 'E_CONTAINER_MISSING':
        return const RejectionMessage(
          title: '缺少必要的书籍描述文件，可能不是标准 EPUB',
          suggestion: '尝试用其他来源重新获取这本书',
        );
      case 'E_OPF_MISSING':
        return const RejectionMessage(
          title: '书籍结构损坏：找不到书籍信息文件',
          suggestion: '这本书的内部文件缺失，请重新下载',
        );
      case 'E_SPINE_EMPTY':
        return const RejectionMessage(
          title: '书籍没有阅读顺序，无法分页',
          suggestion: '这本书的章节列表为空，请换一个版本试试',
        );
      case 'E_FAIRPLAY_ENCRYPTION':
        return const RejectionMessage(
          title: '本书受版权保护（DRM），无法打开',
          suggestion: '请在购买该书的平台阅读',
        );
      case 'E_INTERNAL':
      default:
        return const RejectionMessage(
          title: '书内容无法解析，可能是加密或格式异常',
          suggestion: '请确认这本书未加密，或换一个来源',
        );
    }
  }
}
