import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// float/clear 浮动排版接入 flat 管线的回归。
Uint8List _buildEpub(String bodyHtml, {String? css}) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  final cssItem = css == null
      ? ''
      : '<item id="css" href="style.css" media-type="text/css"/>';
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:float-flat-0001</dc:identifier>
    <dc:title>FloatFlat</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>$cssItem</manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');
  final link = css == null
      ? ''
      : '<link href="style.css" type="text/css" rel="stylesheet"/>';
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>$link</head>'
        '<body>$bodyHtml</body></html>',
  );
  // 8×8 PNG（1x1 透明）——尺寸解析可用。
  final png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
    0,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0,
    0,
    0,
    8,
    0,
    0,
    0,
    8,
    8,
    6,
    0,
    0,
    0,
    0,
    0,
    0,
    0x0D,
    0x0D,
    0x0D,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0,
    1,
    0,
    0,
    5,
    0,
    1,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0,
    0,
    0,
    0,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
  archive.addFile(ArchiveFile('OEBPS/img.png', png.length, png));
  if (css != null) {
    addText('OEBPS/style.css', css);
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('float:left 图片：绕排窄幅段 + 占位耗尽回全宽', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(
        '<p><img src="img.png" style="float:left" width="40%" height="60px"/></p>'
        '<p>这是一段足够长的正文，用来在浮动图旁边换行绕排，'
        '并且在浮动占位耗尽之后恢复全宽排版继续填充更多文字内容。</p>',
      ),
    );
    final pages = await source.loadChapter(0);
    expect(pages, isNotEmpty);
    final slices = pages.first.slices;
    // 浮动覆盖切片存在且不占流高。
    final overlay = slices.where((s) => s.overlay).toList();
    expect(overlay, hasLength(1), reason: '浮动图以覆盖切片渲染');
    // 页首浮动的竖直位置跟首个在流块塌陷到 body 顶部的段距一致
    //（UA p 的 margin-top 1em = 16px）。
    expect(overlay.single.absoluteTop, 16.0);
    // 绕排改为「单块多行 + 逐行 offsetX」（不再切段）：浮动旁的行带左
    // 偏移，浮动占位耗尽后的行回到 0。
    final paragraph = slices.firstWhere((s) => !s.overlay).block.layout;
    expect(
      paragraph.lines.where((line) => line.offsetX > 0),
      isNotEmpty,
      reason: '浮动旁存在右缩的行',
    );
    expect(
      paragraph.lines.where((line) => line.offsetX == 0),
      isNotEmpty,
      reason: '浮动下方恢复全宽行',
    );
  });

  test('align=right 旧属性同样命中右浮', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(
        '<p><img src="img.png" align="right" width="30%"/></p>'
        '<p>右浮绕排验证文字，足够长以产生多行绕排效果并最终恢复全宽。</p>',
      ),
    );
    final slices = (await source.loadChapter(0)).first.slices;
    final overlay = slices.where((s) => s.overlay).single;
    expect(overlay.leftInset, greaterThan(0), reason: '右浮覆盖切片靠右');
  });

  test('作者 CSS float 规则经 class 命中', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(
        '<p><img src="img.png" class="side"/></p>'
        '<p>类规则浮动绕排验证文字，占位耗尽后恢复全宽排版。</p>',
        css: 'img.side { float: left; }',
      ),
    );
    final slices = (await source.loadChapter(0)).first.slices;
    expect(
      slices.where((s) => s.overlay),
      hasLength(1),
      reason: '作者 CSS float 命中',
    );
  });

  test('clear:both：后续块从浮动底边之下开始', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(
        '<p><img src="img.png" style="float:left" height="200px"/></p>'
        '<p style="clear:both">清除段落在浮动下方开始。</p>',
      ),
    );
    final slices = (await source.loadChapter(0)).first.slices;
    final overlay = slices.where((s) => s.overlay).single;
    final cleared = slices
        .where((s) => !s.overlay && s.block.layout.text.contains('清除'))
        .first;
    // 清除段的页内 y ≥ 浮动底边（geometry 语义由绝对 y 推得：
    // 覆盖切片 absoluteTop + height）。
    final floatBottom = overlay.absoluteTop! + overlay.height;
    var flowY = 0.0;
    double? clearedY;
    for (final s in slices.where((s) => !s.overlay)) {
      if (identical(s, cleared)) {
        clearedY = flowY + s.leadingExtent;
        break;
      }
      flowY += s.height;
    }
    expect(clearedY, isNotNull);
    expect(
      clearedY!,
      greaterThanOrEqualTo(floatBottom - 0.5),
      reason: 'clear 推到浮动底边之下',
    );
  });

  test('P8-06 inline-block 小图并排：按左浮近似绕排', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(
        '<p><img src="img.png" class="avatar" width="80px"/></p>'
        '<p>头像旁边的名字与简介文字，应当在图片右侧绕排换行。</p>',
        css: 'img.avatar { display: inline-block; }',
      ),
    );
    final slices = (await source.loadChapter(0)).first.slices;
    expect(
      slices.where((s) => s.overlay),
      hasLength(1),
      reason: 'inline-block 小图走浮动覆盖切片',
    );
    final paragraph = slices.firstWhere((s) => !s.overlay).block.layout;
    expect(
      paragraph.lines.where((line) => line.offsetX > 0),
      isNotEmpty,
      reason: '后续文字绕排右缩',
    );
  });

  test('无浮动章节仍走 Paginator 原路径', () async {
    final source = await EpubChapterSource.open(
      _buildEpub('<p>普通章节正文，无任何浮动元素，分页路径不受影响。</p>'),
    );
    final pages = await source.loadChapter(0);
    expect(pages.first.slices.where((s) => s.overlay), isEmpty);
  });
}
