import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  22.311111111111124,
  8.53333333333336,
  24.08888888888893,
);
const _introCss = '''
body { margin:0; font-family:Ahem; }
h2 { font-size:.8em; line-height:160%; margin:-1em 1em 2em 0;
  text-align:right; color:#ddedfd; }
h2 b { font-size:1.1em; padding:15px;
  border-top:1px solid #ddedfd; border-bottom:1px solid #ddedfd; }
div { font-size:1em; padding:.5em; margin:3em .5em 1em;
  border:1.2px solid #207f4c; background:#fffef8; }
.name { font-size:1em; margin:-1.6em 0 1.3em -1em; }
.name b { font-size:.9em; color:white; background:#1a3b32;
  padding:5px 18px; border:1.4px solid #d1b48c; }
.body { font-size:.6em; line-height:170%; margin:.5em;
  text-align:center; color:#248067; }
''';

Future<PageContent> _page(String body, {String css = _introCss}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="book.opf"/>'
        '</rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">container-sibling-margin</dc:identifier>'
        '<dc:title>容器兄弟边距回归</dc:title></metadata><manifest>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>$css</style>'
        '</head><body>$body</body></html>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 806.9333333333333,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 17, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _pageInsets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _firstGreenBorder(ByteData pixels) {
  for (var y = 60; y < 200; y++) {
    final offset = (y * 384 + 190) * 4;
    final red = pixels.getUint8(offset);
    final green = pixels.getUint8(offset + 1);
    final blue = pixels.getUint8(offset + 2);
    if (green - red > 15 && green - blue > 10) {
      return y;
    }
  }
  fail('未找到卡片上边框');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('标题底距与带框卡片顶距折叠，姓名负上距留在卡片内部', () async {
    final page = await _page(
      '<h2><br/><b>简介</b></h2><div>'
      '<p class="name"><b>宁缺</b></p>'
      '<p class="body">一段可歌可泣可笑可爱的草根崛起史。<br/>'
      '一个物质要求宁滥勿缺的开朗少年行。<br/>'
      '书院后山里永恒回荡着他疑惑的声音：<br/>'
      '宁可永劫受沉沦，不从诸圣求解脱？<br/>…… ……</p></div>',
    );
    final title = page.slices.first.block.layout;
    // h2 底距 27.2 与容器顶距 48 取大，不相加。
    final expectedTop = _pageInsets.top - 13.6 + title.height + 48;
    final cardTop = _firstGreenBorder(await _render(page));
    expect(cardTop, closeTo(expectedTop, 1));
    final name = page.slices[1];
    final nameLineTop =
        _pageInsets.top + page.slices.first.height + name.leadingExtent;
    // 内部负上距 -27.2 加上容器 padding+border=9.2，仍为 -18。
    expect(nameLineTop - cardTop, closeTo(-18, 1));
  });
}
