import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/selection/selection.dart';

Uint8List _epub(String bodyHtml, String css) {
  final archive = Archive();
  void addText(String name, String content) {
    final b = utf8.encode(content);
    archive.addFile(ArchiveFile(name, b.length, b));
  }
  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
  addText('META-INF/container.xml',
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  addText('OEBPS/content.opf',
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">u</dc:identifier><dc:title>t</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/></manifest><spine><itemref idref="c1"/></spine></package>');
  addText('OEBPS/c1.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="style.css" type="text/css" rel="stylesheet"/></head><body>$bodyHtml</body></html>');
  addText('OEBPS/style.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P8-09 ::before/::after content 注入块首尾', () async {
    final source = await EpubChapterSource.open(_epub(
      '<p class="q">引用文字</p>',
      'p.q::before { content: "「"; } p.q::after { content: "」"; }',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, '「引用文字」', reason: '伪元素生成内容拼接');
  });

  test('行内 q 按嵌套层级生成引号并同步排版文本', () async {
    final source = await EpubChapterSource.open(
      _epub(
        '<p class="quote">外层<q>内层<q>第三层</q>结束</q>继续</p>',
        '.quote { quotes: "「" "」" "『" "』"; }',
      ),
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, '外层「内层『第三层』结束」继续');
  });

  test('P8-09 ::first-letter 首字放大 run', () async {
    final source = await EpubChapterSource.open(_epub(
      '<p class="drop">下沉段落正文。</p>',
      'p.drop::first-letter { font-size: 3em; color: #B71C1C; }',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final run = block.layout.runs.firstWhere(
      (r) => r.end - r.start == 1,
      orElse: () => throw StateError('未产出首字 run'),
    );
    expect(block.layout.text.substring(run.start, run.end), '下');
    expect(run.style.fontSize, greaterThan(block.style!.fontSize * 2),
        reason: '3em 首字');
  });

  test('initial-letter 生成三行首字浮动盒并让正文绕排', () async {
    const paragraph =
        '沉段落正文继续排到第四行以后，用来确认首字只占前三行，后续文字会恢复整行宽度。'
        '这里再补充一段较长的文字，让正文在窄屏上至少能够排出五行，'
        '从而覆盖绕排结束后的完整行宽。';
    final source = await EpubChapterSource.open(
      _epub(
        '<p class="drop">下$paragraph</p>',
        'p.drop { initial-letter: 3; } '
            'p.drop::first-letter { color: #B71C1C; }',
      ),
    );
    final pages = await source.loadChapter(0);
    final page = pages.first;
    final dropCap = page.slices.first;
    expect(dropCap.overlay, isTrue, reason: '首字不占正文流高');
    expect(dropCap.block.layout.text, '下');
    expect(
      dropCap.block.layout.height,
      closeTo(dropCap.block.style!.lineHeight, 0.01),
    );
    expect(dropCap.block.style!.color, const Color(0xFFB71C1C));

    final body = pages
        .expand((page) => page.slices)
        .where((slice) => !slice.overlay);
    final text = body.map((slice) => slice.block.layout.text).join();
    expect(text, paragraph, reason: '正文只移除被浮动的首字符');
    final lines = body.expand((slice) => slice.block.layout.lines).toList();
    expect(
      lines.where((line) => line.offsetX > 0),
      hasLength(3),
      reason: '正文前三行在首字右侧绕排',
    );
    expect(lines[3].offsetX, 0, reason: '第四行恢复全宽');

    final boxes = pages.expand(TextHitTester.lineBoxes).toList();
    final all = ReaderSelection.spanning(
      start: TextHit(
        lineBox: boxes.first,
        charOffset: 0,
        textOffset: boxes.first.textOffset,
        atLineStart: true,
        atLineEnd: false,
      ),
      startPageIndex: 0,
      end: TextHit(
        lineBox: boxes.last,
        charOffset: boxes.last.text.length,
        textOffset: boxes.last.textOffset + boxes.last.text.length,
        atLineStart: false,
        atLineEnd: true,
      ),
      endPageIndex: pages.length - 1,
    );
    expect(
      SelectionOps.textAcrossPages(pages, all),
      '下$paragraph',
      reason: '首字、正文和跨页文本保持原文顺序',
    );

    final bodyFirst = TextHitTester.lineBoxes(page)
        .firstWhere((box) => !box.slice.overlay);
    final bodyCfi = SelectionOps.cfiOf(
      ReaderSelection(
        start: TextHit(
          lineBox: bodyFirst,
          charOffset: 0,
          textOffset: bodyFirst.textOffset,
          atLineStart: true,
          atLineEnd: false,
        ),
        end: TextHit(
          lineBox: bodyFirst,
          charOffset: 1,
          textOffset: bodyFirst.textOffset + 1,
          atLineStart: false,
          atLineEnd: false,
        ),
      ),
    )!;
    expect(cfiCharOffset(bodyCfi.start), 1, reason: '正文第一个字在原文中的偏移是 1');
    expect(cfiCharOffset(bodyCfi.end), 2);
  });

  test('initial-letter 首字为代理对时保持字符完整', () async {
    const paragraph = '首字是表情符号，后面的正文应当从它之后继续排版。';
    final source = await EpubChapterSource.open(
      _epub(
        '<p class="drop">😀$paragraph</p>',
        'p.drop { initial-letter: 3; }',
      ),
    );
    final pages = await source.loadChapter(0);
    final dropCap = pages.first.slices.firstWhere((slice) => slice.overlay);
    expect(dropCap.block.layout.text, '😀');
    final body = pages
        .expand((page) => page.slices)
        .where((slice) => !slice.overlay);
    expect(body.map((slice) => slice.block.layout.text).join(), paragraph);
  });

  test('attr() 取元素属性', () async {
    final source = await EpubChapterSource.open(
      _epub(
        '<p class="ref" data-mark="注">正文</p>',
        'p.ref::after { content: attr(data-mark); }',
      ),
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, '正文注');
  });
}
