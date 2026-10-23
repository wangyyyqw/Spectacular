import 'dart:convert';

import 'package:xml/xml.dart';

import 'archive_reader.dart';
import 'epub_exception.dart';

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

    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(bytes));
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
}
