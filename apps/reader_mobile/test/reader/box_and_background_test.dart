import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

/// P9 回归：书籍的容器面板（背景/边框/内边距）与整页背景图。
///
/// 历史缺陷：阅读器排版覆盖重建 ComputedStyle，把非继承属性全部归零，
/// 精排书的卡片与整页背景图都画不出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('容器面板保留背景色/边框/内边距，整页背景解析成书内路径', () async {
    final source = await EpubChapterSource.open(
      _buildPanelEpub(),
      contentWidth: 320,
      contentHeight: 560,
      verifyCrc: false,
    );
    await source.applyOverrides(ReaderSettingsDefaults.overrides);
    final pages = await source.loadChapter(0);
    final page = pages.first;

    expect(
      page.background?.imageUrl,
      'OEBPS/Images/bg.png',
      reason: 'body 的 background-image 要解析成书内绝对路径',
    );

    final panel = page.slices
        .map((slice) => slice.block)
        .firstWhere((block) => block.layout.text.contains('面板正文'));
    final style = panel.style!;
    final container = panel.containers.single.container.style;
    expect(container.backgroundColor.a, closeTo(0.8, 0.001));
    expect(container.borders.left.width, 3);
    expect(container.borders.top.width, 1);
    expect(container.padding.top, 10);
    expect(style.margin.left, 17, reason: '祖先左边框与内边距只计算一次');
    expect(panel.leftInset, 0, reason: '正文没有独立边框');
    expect(panel.topInset, closeTo(21, 0.001),
        reason: '容器上外边距10 + 上边框1 + 上内边距10');
    expect(style.color, const Color(0xFFCBD5E1), reason: '书籍文字颜色照书');

    final plain = page.slices
        .map((slice) => slice.block)
        .firstWhere((block) => block.layout.text.contains('普通段落'));
    expect(plain.style!.backgroundColor.a, 0, reason: '面板背景不能漏到普通段落');
  });
}

/// 最小 EPUB：body 背景图 + 一个带边框/内边距/背景色的 div 面板。
Uint8List _buildPanelEpub() {
  const css =
      'body { background-image: url(../Images/bg.png); '
      'background-size: cover; background-repeat: no-repeat; }\n'
      '.panel { background-color: rgba(10, 20, 30, 0.8); '
      'border-left: 3px solid #e2b867; border-top: 1px solid #283652; '
      'padding: 10px 14px; margin: 10px 0; }\n'
      '.panel p { color: #cbd5e1; }\n';
  const chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<title>面板书</title>'
      '<link rel="stylesheet" type="text/css" href="../Styles/styles.css"/>'
      '</head><body>'
      '<p>普通段落</p>'
      '<div class="panel"><p>面板正文</p></div>'
      '</body></html>';
  const opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">urn:uuid:panel-book</dc:identifier>'
      '<dc:title>面板书</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c1" href="Text/c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="Styles/styles.css" media-type="text/css"/>'
      '<item id="bg" href="Images/bg.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c1"/></spine></package>';
  const container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(container),
    'OEBPS/content.opf': utf8.encode(opf),
    'OEBPS/Text/c1.xhtml': utf8.encode(chapter),
    'OEBPS/Styles/styles.css': utf8.encode(css),
    // 1×1 透明 PNG（只验证 URL 解析，不参与解码）。
    'OEBPS/Images/bg.png': <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ],
  };
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
