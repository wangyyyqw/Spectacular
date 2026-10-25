import 'package:xml/xml.dart';

import '../src/api/models.dart';
import 'epub_exception.dart';

/// manifest 中的一项。
class OpfManifestItem {
  /// 创建 manifest 项。
  const OpfManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties = const <String>[],
  });

  /// 唯一 ID。
  final String id;

  /// 相对 OPF 的路径。
  final String href;

  /// 媒体类型。
  final String mediaType;

  /// `properties` 属性（按空格拆分）。
  final List<String> properties;
}

/// 解析后的 OPF 包。
class OpfPackage {
  /// 创建包信息。
  const OpfPackage({
    required this.meta,
    required this.manifest,
    required this.spine,
    required this.version,
    required this.warnings,
    this.tocId,
    this.coverItemId,
  });

  /// 书籍元信息。
  final BookMeta meta;

  /// manifest 列表。
  final List<OpfManifestItem> manifest;

  /// spine 列表（href 为 OPF 相对路径）。
  final List<SpineItem> spine;

  /// OPF 版本（2.0 / 3.0）。
  final String version;

  /// 解析过程中的可恢复问题。
  final List<String> warnings;

  /// spine 的 toc 属性（NCX id），可为空。
  final String? tocId;

  /// `<meta name="cover" content="...">` 的内容（§37.3 封面第 2 级）：
  /// 多数 EPUB2 书写 manifest id，少数直接写 href。
  final String? coverItemId;

  /// 按 ID 查 manifest 项。
  OpfManifestItem? itemById(String id) {
    for (final item in manifest) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}

/// 解析 OPF 的 metadata / manifest / spine。
abstract final class OpfParser {
  /// 解析 OPF；失败抛出 [EpubException]。
  static OpfPackage parse(String xmlText) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(_stripBom(xmlText));
    } on FormatException catch (error) {
      throw EpubException('E_OPF_XML', 'OPF 解析失败：${error.message}');
    }

    final packageElement = _firstElement(document, 'package');
    if (packageElement == null) {
      throw const EpubException('E_OPF_PACKAGE', 'OPF 缺少 package 元素');
    }
    final version = packageElement.getAttribute('version') ?? '';

    final metadata = _firstElement(document, 'metadata');
    final uniqueId = packageElement.getAttribute('unique-identifier');
    final meta = _parseMetadata(metadata, uniqueId);

    final manifest = <OpfManifestItem>[];
    final manifestWarnings = <String>[];
    final manifestElement = _firstElement(document, 'manifest');
    if (manifestElement != null) {
      for (final element in manifestElement.childElements.where(
        (element) => element.name.local == 'item',
      )) {
        final id = element.getAttribute('id')?.trim() ?? '';
        final href = element.getAttribute('href')?.trim() ?? '';
        if (id.isEmpty || href.isEmpty) {
          continue;
        }
        final properties = (element.getAttribute('properties') ?? '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        var mediaType = element.getAttribute('media-type')?.trim() ?? '';
        if (mediaType.isEmpty) {
          // P7-12：media-type 缺失按扩展名推断（对照 Reeden
          // manifestMediaTypeInferred 诊断），推断失败保持空并告警。
          mediaType = inferMediaType(href);
          manifestWarnings.add(
            'E_MANIFEST_MEDIA_TYPE_INFERRED: manifest 项 $id（$href）'
            '缺少 media-type，按扩展名推断为'
            '${mediaType.isEmpty ? '未知（保持为空）' : mediaType}',
          );
        }
        manifest.add(
          OpfManifestItem(
            id: id,
            href: href,
            mediaType: mediaType,
            properties: properties,
          ),
        );
      }
    }

    final warnings = <String>[];
    final spine = <SpineItem>[];
    final spineElement = _firstElement(document, 'spine');
    if (spineElement != null) {
      for (final element in spineElement.childElements.where(
        (element) => element.name.local == 'itemref',
      )) {
        final idref = element.getAttribute('idref')?.trim() ?? '';
        if (idref.isEmpty) {
          continue;
        }
        final item = manifest.where((item) => item.id == idref).firstOrNull;
        if (item == null) {
          warnings.add('spine 引用了不存在的 manifest id：$idref');
          continue;
        }
        spine.add(
          SpineItem(
            index: spine.length,
            href: item.href,
            mediaType: item.mediaType,
            linear: (element.getAttribute('linear') ?? 'yes') != 'no',
          ),
        );
      }
    }

    return OpfPackage(
      meta: meta,
      manifest: manifest,
      spine: spine,
      version: version,
      warnings: <String>[...manifestWarnings, ...warnings],
      tocId: spineElement?.getAttribute('toc')?.trim(),
      coverItemId: _parseCoverItemId(metadata),
    );
  }

  /// 按扩展名推断 media-type（P7-12）；未识别返回空串。
  ///
  /// 覆盖 EPUB 常见四类（XHTML/CSS/NCX/OPF）与字体、图片；
  /// nav 属 XHTML（properties 含 nav），无需单独推断。
  static String inferMediaType(String href) {
    final dot = href.lastIndexOf('.');
    if (dot < 0 || dot + 1 >= href.length) {
      return '';
    }
    final extension = href.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'xhtml' || 'html' || 'htm' => 'application/xhtml+xml',
      'css' => 'text/css',
      'ncx' => 'application/x-dtbncx+xml',
      'opf' => 'application/oebps-package+xml',
      'js' => 'text/javascript',
      'otf' => 'application/vnd.ms-opentype',
      'ttf' => 'application/font-sfnt',
      'woff' => 'application/font-woff',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'svg' => 'image/svg+xml',
      'webp' => 'image/webp',
      _ => '',
    };
  }

  /// 解析 `<meta name="cover" content="...">`（§37.3 封面第 2 级）。
  static String? _parseCoverItemId(XmlElement? metadata) {
    if (metadata == null) {
      return null;
    }
    for (final element in metadata.childElements) {
      if (element.name.local != 'meta') {
        continue;
      }
      if ((element.getAttribute('name') ?? '').trim().toLowerCase() !=
          'cover') {
        continue;
      }
      final content = (element.getAttribute('content') ?? '').trim();
      if (content.isNotEmpty) {
        return content;
      }
    }
    return null;
  }

  static BookMeta _parseMetadata(XmlElement? metadata, String? uniqueId) {
    String textOf(String localName) {
      if (metadata == null) {
        return '';
      }
      final element = _firstElement(metadata, localName);
      return element?.innerText.trim() ?? '';
    }

    var identifier = '';
    if (metadata != null) {
      final identifiers = metadata.childElements
          .where((element) => element.name.local == 'identifier')
          .toList(growable: false);
      if (uniqueId != null && uniqueId.isNotEmpty) {
        for (final element in identifiers) {
          if (element.getAttribute('id') == uniqueId) {
            identifier = element.innerText.trim();
            break;
          }
        }
      }
      identifier = identifier.isNotEmpty
          ? identifier
          : (identifiers.isNotEmpty ? identifiers.first.innerText.trim() : '');
    }

    final creators = metadata == null
        ? const <String>[]
        : metadata.childElements
              .where((element) => element.name.local == 'creator')
              .map((element) => element.innerText.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);

    return BookMeta(
      title: textOf('title'),
      author: creators.join('、'),
      language: textOf('language'),
      identifier: identifier,
    );
  }

  static XmlElement? _firstElement(XmlNode node, String localName) {
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) {
        return element;
      }
    }
    return null;
  }

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;
}
