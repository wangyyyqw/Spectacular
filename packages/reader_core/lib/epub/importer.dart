import 'archive_reader.dart';
import 'opf.dart';
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
      title: '未命名书籍',
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

