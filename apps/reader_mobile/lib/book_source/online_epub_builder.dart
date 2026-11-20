import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 在线书源正文的一章。
class OnlineEpubChapter {
  const OnlineEpubChapter({
    required this.title,
    required this.html,
    this.sourceUrl = '',
    this.volume = '',
  });

  final String title;
  final String html;
  final String sourceUrl;
  final String volume;
}

/// 已下载并准备写入 EPUB 的图片。
class OnlineEpubImage {
  const OnlineEpubImage({
    required this.path,
    required this.bytes,
    required this.mediaType,
  });

  /// 相对于 `OEBPS` 的路径，例如 `images/cover.jpg`。
  final String path;
  final Uint8List bytes;
  final String mediaType;
}

/// 在线书籍元信息与正文。
class OnlineEpubInput {
  const OnlineEpubInput({
    required this.title,
    required this.author,
    required this.chapters,
    this.intro = '',
    this.sourceName = '',
    this.bookUrl = '',
    this.cover,
    this.images = const <OnlineEpubImage>[],
  });

  final String title;
  final String author;
  final String intro;
  final String sourceName;
  final String bookUrl;
  final List<OnlineEpubChapter> chapters;
  final OnlineEpubImage? cover;
  final List<OnlineEpubImage> images;
}

/// 将在线书源结果打包成当前阅读引擎可导入的 EPUB。
class OnlineEpubBuilder {
  const OnlineEpubBuilder();

  Uint8List build(OnlineEpubInput input) {
    if (input.chapters.isEmpty) {
      throw const FormatException('没有可写入的章节');
    }
    final bookId = sha256
        .convert(
          utf8.encode('${input.sourceName}|${input.bookUrl}|${input.title}'),
        )
        .toString();
    final identifier = 'urn:uuid:${_uuidFromHash(bookId)}';
    final archive = Archive();

    void add(String path, List<int> bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    void addText(String path, String text) =>
        add(path, Uint8List.fromList(utf8.encode(text)));

    addText('mimetype', 'application/epub+zip');
    addText('META-INF/container.xml', _containerXml);
    addText('OEBPS/style.css', chapterStylesheet);

    final manifest = <String>[
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
      '<item id="style" href="style.css" media-type="text/css"/>',
      '<item id="online-index" href="online_chapters.json" media-type="application/json"/>',
    ];
    final spine = <String>[];
    final navItems = <String>[];
    final ncxItems = <String>[];

    for (var index = 0; index < input.chapters.length; index++) {
      final chapter = input.chapters[index];
      final id = 'chapter_${(index + 1).toString().padLeft(4, '0')}';
      final href = 'text/$id.xhtml';
      addText('OEBPS/$href', buildChapterDocument(chapter));
      manifest.add(
        '<item id="$id" href="$href" media-type="application/xhtml+xml"/>',
      );
      spine.add('<itemref idref="$id"/>');
      navItems.add('<li><a href="$href">${_escapeXml(chapter.title)}</a></li>');
      ncxItems.add(
        '<navPoint id="nav-$id" playOrder="${index + 1}">'
        '<navLabel><text>${_escapeXml(chapter.title)}</text></navLabel>'
        '<content src="$href"/>'
        '</navPoint>',
      );
    }

    String? coverHref;
    final cover = input.cover;
    if (cover != null && cover.bytes.isNotEmpty) {
      add('OEBPS/${cover.path}', cover.bytes);
      manifest.add(
        '<item id="cover-image" href="${cover.path}" '
        'media-type="${cover.mediaType}" properties="cover-image"/>',
      );
      addText(
        'OEBPS/cover.xhtml',
        _chapterDocument(
          title: input.title,
          body:
              '<div class="cover"><img src="${cover.path}" '
              'alt="${_escapeXml(input.title)}"/></div>',
          stylesheet: 'style.css',
        ),
      );
      manifest.add(
        '<item id="cover-page" href="cover.xhtml" '
        'media-type="application/xhtml+xml"/>',
      );
      spine.insert(0, '<itemref idref="cover-page" properties="cover-image"/>');
      coverHref = cover.path;
    }

    final seenImages = <String>{};
    for (final image in input.images) {
      if (image.bytes.isEmpty || !seenImages.add(image.path)) continue;
      add('OEBPS/${image.path}', image.bytes);
      final id = 'image_${seenImages.length.toString().padLeft(4, '0')}';
      manifest.add(
        '<item id="$id" href="${image.path}" media-type="${image.mediaType}"/>',
      );
    }

    addText('OEBPS/nav.xhtml', _navDocument(input.title, navItems.join()));
    addText(
      'OEBPS/toc.ncx',
      _ncxDocument(
        title: input.title,
        identifier: identifier,
        items: ncxItems.join(),
      ),
    );
    addText(
      'OEBPS/content.opf',
      _opfDocument(
        title: input.title,
        author: input.author,
        intro: input.intro,
        sourceName: input.sourceName,
        identifier: identifier,
        manifest: manifest.join(),
        spine: spine.join(),
        coverHref: coverHref,
      ),
    );
    addText(
      'OEBPS/online_chapters.json',
      jsonEncode({
        'version': 1,
        'chapters': [
          for (var index = 0; index < input.chapters.length; index++)
            {
              'href':
                  'text/chapter_${(index + 1).toString().padLeft(4, '0')}.xhtml',
              'title': input.chapters[index].title,
              'url': input.chapters[index].sourceUrl,
              'volume': input.chapters[index].volume,
            },
        ],
      }),
    );
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  /// 在线阅读和离线 EPUB 共用正文清洗、标题和正文样式。
  String buildChapterDocument(OnlineEpubChapter chapter) => _chapterDocument(
    title: chapter.title,
    body: _chapterBody(chapter),
    stylesheet: '../style.css',
  );

  String _chapterBody(OnlineEpubChapter chapter) {
    final fragment = html_parser.parseFragment(chapter.html);
    _sanitizeFragment(fragment);
    final body = _serializeNodes(fragment.nodes);
    final headingText = fragment.querySelector('h1,h2,h3')?.text.trim() ?? '';
    final heading = headingText == chapter.title.trim()
        ? ''
        : '<h1 class="chapter-title">${_escapeXml(chapter.title)}</h1>';
    return '$heading$body';
  }

  void _sanitizeFragment(DocumentFragment fragment) {
    final remove = <Element>[];
    for (final element in fragment.querySelectorAll(
      'script,style,iframe,object,embed,form,input,button,noscript,link,meta',
    )) {
      remove.add(element);
    }
    for (final element in remove) {
      element.remove();
    }
    for (final element in fragment.querySelectorAll('*')) {
      final unsafe = <Object>[
        for (final entry in element.attributes.entries)
          if ('${entry.key}'.toLowerCase().startsWith('on') ||
              '${entry.key}'.toLowerCase() == 'srcdoc')
            entry.key,
      ];
      for (final key in unsafe) {
        element.attributes.remove(key);
      }
      if (element.localName == 'img') {
        final src = element.attributes['src']?.trim() ?? '';
        if (src.isEmpty || src.startsWith('data:')) {
          element.remove();
        }
      }
    }
  }

  String _serializeNodes(List<Node> nodes) {
    var html = nodes
        .map((node) => node is Element ? node.outerHtml : node.text)
        .join();
    html = html.replaceAllMapped(
      RegExp(
        r'<(br|hr|img|input|area|base|col|embed|link|meta|param|source|track|wbr)([^<>]*?)\s*/?>',
        caseSensitive: false,
      ),
      (match) {
        final attributes = (match.group(2) ?? '').replaceFirst(
          RegExp(r'\s*/+\s*$'),
          '',
        );
        return '<${match.group(1)}$attributes/>';
      },
    );
    return html;
  }

  String _chapterDocument({
    required String title,
    required String body,
    required String stylesheet,
  }) {
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">\n'
        '<head><meta charset="utf-8"/>'
        '<title>${_escapeXml(title)}</title>'
        '<link rel="stylesheet" type="text/css" href="$stylesheet"/></head>\n'
        '<body>$body</body>\n'
        '</html>';
  }

  String _navDocument(String title, String items) {
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">\n'
        '<head><meta charset="utf-8"/><title>${_escapeXml(title)}</title></head>\n'
        '<body><nav epub:type="toc" id="toc"><h1>目录</h1><ol>$items</ol></nav></body>\n'
        '</html>';
  }

  String _ncxDocument({
    required String title,
    required String identifier,
    required String items,
  }) {
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
        'version="2005-1" xml:lang="zh-CN">'
        '<head><meta name="dtb:uid" content="${_escapeXml(identifier)}"/></head>'
        '<docTitle><text>${_escapeXml(title)}</text></docTitle>'
        '<navMap>$items</navMap>'
        '</ncx>';
  }

  String _opfDocument({
    required String title,
    required String author,
    required String intro,
    required String sourceName,
    required String identifier,
    required String manifest,
    required String spine,
    required String? coverHref,
  }) {
    final modified = DateTime.now().toUtc().toIso8601String().split('.').first;
    final description = _plainText(intro);
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="book-id">\n'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="book-id">${_escapeXml(identifier)}</dc:identifier>'
        '<dc:title>${_escapeXml(title)}</dc:title>'
        '<dc:creator>${_escapeXml(author)}</dc:creator>'
        '<dc:language>zh-CN</dc:language>'
        '${description.isEmpty ? '' : '<dc:description>${_escapeXml(description)}</dc:description>'}'
        '${sourceName.isEmpty ? '' : '<dc:publisher>${_escapeXml(sourceName)}</dc:publisher>'}'
        '<meta property="dcterms:modified">$modified</meta>'
        '${coverHref == null ? '' : '<meta name="cover" content="cover-image"/>'}'
        '</metadata>\n'
        '<manifest>$manifest</manifest>\n'
        '<spine toc="ncx">$spine</spine>\n'
        '<guide>${coverHref == null ? '' : '<reference type="cover" title="封面" href="cover.xhtml"/>'}</guide>\n'
        '</package>';
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _escapeXml(String value) => const HtmlEscape().convert(value);

  String _uuidFromHash(String hash) {
    final value = hash.padRight(32, '0').substring(0, 32).split('');
    value[12] = '4';
    value[16] = '8';
    final text = value.join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20, 32)}';
  }

  static const String _containerXml =
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles>\n'
      '</container>';

  static const String chapterStylesheet =
      'html { font-size: 100%; }\n'
      'body { margin: 0; line-height: 1.75; word-wrap: break-word; }\n'
      'p { margin: 0 0 .8em; text-indent: 2em; }\n'
      'h1, h2, h3 { text-indent: 0; font-weight: bold; }\n'
      '.chapter-title { margin: 0 0 1.2em; text-align: center; }\n'
      'img { max-width: 100%; height: auto; }\n'
      '.cover { margin: 0; padding: 0; text-align: center; }\n'
      '.cover img { max-height: 100%; }\n';
}
