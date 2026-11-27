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

  /// 相对于 `OEBPS` 的路径，例如 `Images/cover.jpg`。
  final String path;
  final Uint8List bytes;
  final String mediaType;

  static const directory = 'Images';

  static OnlineEpubImage? fromBytes(Uint8List bytes, String name) {
    bool starts(List<int> signature, [int offset = 0]) =>
        bytes.length >= offset + signature.length &&
        signature.indexed.every((part) => bytes[offset + part.$1] == part.$2);
    final extension = switch (bytes) {
      _ when starts([0xff, 0xd8, 0xff]) => 'jpg',
      _ when starts([137, 80, 78, 71, 13, 10, 26, 10]) => 'png',
      _ when starts(ascii.encode('GIF87a')) || starts(ascii.encode('GIF89a')) =>
        'gif',
      _ when starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8) =>
        'webp',
      _ => null,
    };
    return extension == null
        ? null
        : OnlineEpubImage(
            path: '$directory/$name.$extension',
            bytes: bytes,
            mediaType: extension == 'jpg' ? 'image/jpeg' : 'image/$extension',
          );
  }
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
    this.sourceId = '',
    this.onDemand = false,
  });

  final String title;
  final String author;
  final String intro;
  final String sourceName;
  final String bookUrl;
  final List<OnlineEpubChapter> chapters;
  final OnlineEpubImage? cover;
  final List<OnlineEpubImage> images;
  final String sourceId;
  final bool onDemand;
}

/// 将在线书源结果打包成当前阅读引擎可导入的 EPUB。
class OnlineEpubBuilder {
  const OnlineEpubBuilder();

  static const stylesheetPath = 'Styles/style.css';

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

    archive.addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        ascii.encode('application/epub+zip'),
      ),
    );
    addText('META-INF/container.xml', _containerXml);
    addText('OEBPS/$stylesheetPath', chapterStylesheet);

    final manifest = <String>[
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
      '<item id="style" href="$stylesheetPath" media-type="text/css"/>',
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
      addText('OEBPS/cover.xhtml', buildCoverDocument(input.title, cover.path));
      manifest.add(
        '<item id="cover-page" href="cover.xhtml" '
        'media-type="application/xhtml+xml"/>',
      );
      spine.insert(0, '<itemref idref="cover-page"/>');
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
    if (input.sourceId.isNotEmpty) {
      addText(
        'OEBPS/reamicro-online-chapters.json',
        jsonEncode({
          'version': 1,
          'sourceId': input.sourceId,
          'detailUrl': input.bookUrl,
          'bookName': input.title,
          'mode': input.onDemand ? 'ON_DEMAND' : 'FULL',
          'chapters': [
            for (final (index, chapter) in input.chapters.indexed)
              {
                'href':
                    'OEBPS/text/chapter_${(index + 1).toString().padLeft(4, '0')}.xhtml',
                'url': chapter.sourceUrl,
                'title': chapter.title,
                'volumeTitle': chapter.volume,
                'state': input.onDemand ? 'PENDING' : 'READY',
              },
          ],
        }),
      );
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  /// 在线阅读和离线 EPUB 共用正文清洗、标题和正文样式。
  String buildChapterDocument(OnlineEpubChapter chapter) => _chapterDocument(
    title: chapter.title,
    body: _chapterBody(chapter),
    stylesheet: '../$stylesheetPath',
  );

  String buildCoverDocument(
    String title,
    String image, {
    String? stylesheet = stylesheetPath,
  }) => _chapterDocument(
    title: title,
    body:
        '<div class="cover"><img src="${_escapeXml(image)}" '
        'alt="${_escapeXml(title)}"/></div>',
    stylesheet: stylesheet,
  );

  String _chapterBody(OnlineEpubChapter chapter) {
    var html = chapter.html;
    // 纯文本追加行内段评后仍按换行分段，不能因出现 img/a 就丢掉段落。
    if (!RegExp(
          r'<(?:p|div|h[1-6]|section|article|table|ul|ol|blockquote|pre|br)\b',
          caseSensitive: false,
        ).hasMatch(html) &&
        RegExp(
          r'<(?:a|img|span|em|strong)\b',
          caseSensitive: false,
        ).hasMatch(html)) {
      html = html
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => '<p>${line.trim()}</p>')
          .join();
    }
    final fragment = html_parser.parseFragment(html);
    final isPlainText = fragment.children.isEmpty;
    _sanitizeFragment(fragment);
    _removeLeadingTitle(fragment, chapter.title);
    // 接口可能自带同名 h1；开头的目录标题也走统一格式，保留锚点与属性。
    Element? leadingHeading;
    for (final node in fragment.nodes) {
      if (node is Text && node.text.trim().isEmpty) continue;
      if (node is Element && _titleText(node).trim().isEmpty) continue;
      if (node is Element &&
          const {'h1', 'h2', 'h3'}.contains(node.localName) &&
          _normalizedTitle(_titleText(node)) ==
              _normalizedTitle(chapter.title)) {
        leadingHeading = node;
      }
      break;
    }
    if (leadingHeading != null) {
      leadingHeading.classes.add('chapter-title');
      leadingHeading.innerHtml = _chapterHeadingContent(chapter.title);
    }
    final images = fragment.querySelectorAll('img');
    var artwork = '';
    // 带图正文中的卷标是独立的章首图片；保留同章正文，仅让图片独占一页。
    if (chapter.volume.isNotEmpty &&
        images.isNotEmpty &&
        (fragment.text ?? '').trim().isNotEmpty) {
      final first = fragment.children.firstOrNull;
      final leadingImage = first?.localName == 'img'
          ? first
          : first?.children.length == 1 && (first?.text.trim().isEmpty ?? false)
          ? first?.querySelector('img')
          : null;
      if (leadingImage != null) {
        final page = Element.tag('div');
        final src = leadingImage.attributes['src']!;
        double? imageDimension(String name) => double.tryParse(
          (leadingImage.attributes['img-$name'] ??
                  leadingImage.attributes[name] ??
                  '')
              .replaceFirst(RegExp(r'px$'), ''),
        );
        final width = imageDimension('width');
        final height = imageDimension('height');
        // 源声明的竖向卷标等比铺满；横图完整居中，不按屏幕比例拉伸。
        final fit = width != null && height != null && height > width
            ? 'cover'
            : 'contain';
        if (leadingImage.id.isNotEmpty) page.id = leadingImage.id;
        page.attributes['style'] =
            'height:100vh;margin:0;padding:0;duokan-bleed:all;'
            'background-image:url("${src.replaceAll('"', '%22')}");'
            'background-size:$fit;background-position:center;'
            'background-repeat:no-repeat;'
            'page-break-before:always;page-break-after:always;';
        artwork = _serializeNodes([page]);
        leadingImage.remove();
        if (first != leadingImage) first?.remove();
      }
    }
    if (images.length == 1) {
      // 在线单图章只保留图片，不插入会阻断正式引擎整页判定的标题。
      // 同名开头标题属于接口重复信息，其他正文和多图仍走原排版。
      final content = fragment.clone(true);
      if (leadingHeading != null) {
        content.querySelector('.chapter-title')?.remove();
      }
      if (artwork.isEmpty && (content.text ?? '').trim().isEmpty) {
        final image = images.single.clone(true);
        image.attributes.remove('width');
        image.attributes.remove('height');
        image.attributes.remove('style');
        return _serializeNodes([image]);
      }
    }
    final body = isPlainText
        ? _serializeParagraphs(fragment.text ?? '')
        : _serializeNodes(fragment.nodes);
    final heading = leadingHeading == null
        ? _chapterHeading(chapter.title)
        : '';
    final content = '$artwork$heading$body';
    // 书源偶尔将目录卷名同时作为正文返回。去掉重复开头后仍需保留
    // 可打开的章首标题，避免正式引擎收到空 XHTML。
    return content.trim().isEmpty && chapter.title.trim().isNotEmpty
        ? _chapterHeading(chapter.title)
        : content;
  }

  /// 参考阅微：章节编号和名称分别一行，保留目录中的完整标题。
  String _chapterHeading(String title) {
    return '<h1 class="chapter-title">${_chapterHeadingContent(title)}</h1>';
  }

  String _chapterHeadingContent(String title) {
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(
      r'^(第\s*[0-9０-９一二三四五六七八九十百千万〇零两]+\s*[章节卷回集部篇]|chapter\s*\d+|番外|后日谈|后记|序章|楔子|终章)\s*[:：/／、，,。.!！?？\-—_；;]*\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(clean);
    final content = match == null
        ? _escapeXml(clean)
        : '<span class="chapter-number">${_escapeXml(match.group(1)!.trim())}</span><br/>'
              '${_escapeXml(match.group(2)!.trim())}';
    return content;
  }

  /// 只去掉正文开头与目录标题完全相同的一行，保留正文后面的同名引用。
  void _removeLeadingTitle(DocumentFragment fragment, String title) {
    final expected = _normalizedTitle(title);
    if (expected.isEmpty) return;
    for (final node in List<Node>.of(fragment.nodes)) {
      if (node is Text) {
        final text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        if (text.trim().isEmpty) continue;
        final lines = text.split('\n');
        final first = lines.indexWhere((line) => line.trim().isNotEmpty);
        if (first >= 0 && _normalizedTitle(lines[first]) == expected) {
          node.text = lines.skip(first + 1).join('\n');
        }
      } else if (node is Element) {
        // 章首卷标及空容器不是正文标题，继续检查第一段文字。
        if (_titleText(node).trim().isEmpty) continue;
        if (const {'h1', 'h2', 'h3'}.contains(node.localName)) return;
        if (const {'p', 'div'}.contains(node.localName) &&
            node.querySelector('img,br,p,div') == null &&
            _normalizedTitle(_titleText(node)) == expected) {
          node.remove();
        }
      }
      return;
    }
  }

  String _titleText(Element node) {
    final copy = node.clone(true);
    for (final action in copy.querySelectorAll(
      'a[data-reader-action="true"]',
    )) {
      action.remove();
    }
    return copy.text;
  }

  String _normalizedTitle(String value) {
    final clean = value.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');
    return clean.replaceFirstMapped(
      RegExp(r'^第([0-9０-９一二三四五六七八九十百千万〇零两]+)([章节卷回集部篇])'),
      (match) {
        final raw = match.group(1)!;
        const digits = '零一二三四五六七八九';
        const units = {'十': 10, '百': 100, '千': 1000, '万': 10000};
        var total = 0;
        var section = 0;
        var number = 0;
        for (final rune in raw.runes) {
          final char = String.fromCharCode(rune);
          final digit = digits.indexOf(
            char == '〇'
                ? '零'
                : char == '两'
                ? '二'
                : char,
          );
          if (digit >= 0) {
            number = number * 10 + digit;
          } else if (units[char] case final unit?) {
            if (unit == 10000) {
              total += (section + number) * unit;
              section = 0;
            } else {
              section += (number == 0 ? 1 : number) * unit;
            }
            number = 0;
          } else {
            final ascii = rune >= 0xFF10 && rune <= 0xFF19
                ? rune - 0xFF10
                : rune - 0x30;
            number = number * 10 + ascii;
          }
        }
        return '第${total + section + number}${match.group(2)}';
      },
    );
  }

  String _serializeParagraphs(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => '<p>${_escapeXml(line)}</p>')
      .join();

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
        .map(
          (node) => switch (node) {
            Element() => node.outerHtml,
            Text() => _escapeXml(node.text),
            _ => '',
          },
        )
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
    required String? stylesheet,
  }) {
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">\n'
        '<head><meta charset="utf-8"/>'
        '<title>${_escapeXml(title)}</title>'
        '${stylesheet == null ? '' : '<link rel="stylesheet" type="text/css" href="${_escapeXml(stylesheet)}"/>'}</head>\n'
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
    final description = intro
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(?:p|div)>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
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

  String _escapeXml(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

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
      '.chapter-title { font-size: calc(1.5em - 4px); margin: 0 0 1.2em; text-align: center; }\n'
      '.chapter-number { font-size: calc(1em - 2px); }\n'
      'img { max-width: 100%; height: auto; }\n'
      '.cover { margin: 0; padding: 0; text-align: center; }\n'
      '.cover img { max-height: 100%; }\n';
}
