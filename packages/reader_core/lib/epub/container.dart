import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'archive_reader.dart';
import 'epub_exception.dart';
import 'xml_encoding.dart';

/// container.xml 中的 rootfile 信息。
class ContainerInfo {
  /// 创建容器信息。
  const ContainerInfo({required this.rootfilePath, this.mediaType});

  /// OPF 在 ZIP 中的路径。
  final String rootfilePath;

  /// rootfile 声明的媒体类型。
  final String? mediaType;
}

/// 解析 `META-INF/container.xml`。
abstract final class EpubContainer {
  static const String containerPath = 'META-INF/container.xml';

  /// 解析容器；失败抛出 [EpubException]。
  static ContainerInfo parse(EpubArchive archive) {
    final bytes = archive.readBytes(containerPath);
    if (bytes == null) {
      throw const EpubException(
        'E_CONTAINER_MISSING',
        '缺少 META-INF/container.xml',
      );
    }
    return parseBytes(bytes);
  }

  /// 解析已异步读取的容器字节，供文件打开路径在后台 isolate 执行。
  static ContainerInfo parseBytes(Uint8List bytes) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(decodeXmlBytes(bytes));
    } on FormatException catch (error) {
      throw EpubException(
        'E_CONTAINER_XML',
        'container.xml 解析失败：${error.message}',
      );
    }

    final rootfiles = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .toList(growable: false);
    if (rootfiles.isEmpty) {
      throw const EpubException(
        'E_CONTAINER_ROOTFILE',
        'container.xml 未声明 rootfile',
      );
    }

    final first = rootfiles.first;
    final fullPath = first.getAttribute('full-path')?.trim() ?? '';
    if (fullPath.isEmpty) {
      throw const EpubException(
        'E_CONTAINER_ROOTFILE',
        'rootfile 缺少 full-path',
      );
    }

    return ContainerInfo(
      rootfilePath: _normalize(fullPath),
      mediaType: first.getAttribute('media-type'),
    );
  }

  static String _normalize(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return result;
  }

  /// container.xml 失败时的回退扫描候选（P7-12；对照 Reeden 500 号
  /// §1.3 的 "Fallback: found OEBPS/content.opf"）。
  static const List<String> _fallbackCandidates = <String>[
    'OEBPS/content.opf',
    'OEBPS/package.opf',
    'content.opf',
  ];

  /// 解析容器；container.xml 缺失/损坏/无 rootfile 时按候选路径扫描
  /// OPF 兜底，末位兜底扫描全库首个 `.opf`（跳过 META-INF）。
  ///
  /// 返回容器信息与降级诊断（正常路径诊断为 null）；全部失败抛出原
  /// [EpubException]（拒绝路径不变）。
  static (ContainerInfo, String?) parseWithFallback(EpubArchive archive) {
    try {
      return (parse(archive), null);
    } on EpubException catch (error) {
      for (final candidate in _fallbackCandidates) {
        if (archive.readBytes(candidate) != null) {
          return (
            ContainerInfo(rootfilePath: candidate),
            'E_CONTAINER_FALLBACK: container.xml 不可用（${error.code}），'
                '回退扫描命中 $candidate',
          );
        }
      }
      for (final name in archive.names) {
        final lower = name.toLowerCase();
        if (lower.endsWith('.opf') && !lower.startsWith('meta-inf/')) {
          return (
            ContainerInfo(rootfilePath: name),
            'E_CONTAINER_FALLBACK: container.xml 不可用（${error.code}），'
                '全库扫描命中 $name',
          );
        }
      }
      rethrow;
    }
  }
}
