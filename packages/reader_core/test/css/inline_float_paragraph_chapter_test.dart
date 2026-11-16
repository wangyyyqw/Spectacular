import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _width = 366.6666666666667;
const _height = 773.1694444444443;
const _labels = ['字段一', '字段二', '字段三', '字段四', '字段五'];
const _values = ['完整书名', '完整作者姓名', '译者姓名', '出版社名称', '制作人员'];
const _rowCss = '''
body { margin:0; padding:2em .5em; font-family:Ahem; }
.sheet { width:92%; max-width:420px; margin:0 auto;
  padding:2em 1.5em; box-sizing:border-box; }
.record { display:block; overflow:hidden; margin:0 0 .8em;
  padding:.6em 0; font-size:.85em; line-height:1.6;
  text-align:left; text-indent:0; }
.label { float:left; }
.value { float:right; text-align:right; }
''';

String get _rows => [
  for (var i = 0; i < _labels.length; i++)
    '<p class="record"><span class="label">${_labels[i]}</span>'
        '<span class="value">${_values[i]}</span></p>',
].join();

Uint8List _epub(String css, String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">inline-float-paragraph</dc:identifier>'
      '<dc:title>行内浮动段落回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {margin:0; padding:0; font-family:Ahem;} '
      'p {margin:0; padding:0; text-indent:0;} '
      '$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _open(
  String css,
  String body, {
  double width = _width,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, body),
    options: ReaderOpenOptions(contentWidth: width, contentHeight: _height),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: width,
    height: _height,
    topInset: 56.07500000000001,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  return source;
}

PageLineBox _line(PageContent page, String text) =>
    TextHitTester.lineBoxes(page).singleWhere((line) => line.text == text);

void _expectRows(PageContent page) {
  for (var i = 0; i < _labels.length; i++) {
    final label = _line(page, _labels[i]).rect;
    final value = _line(page, _values[i]).rect;
    expect(value.top, closeTo(label.top, .001), reason: '同一信息行左右对齐');
    expect(label.right, lessThanOrEqualTo(value.left));
    expect(value.right, lessThanOrEqualTo(_width));
    if (i > 0) {
      final previous = _line(page, _labels[i - 1]).rect;
      expect(
        label.top - previous.top,
        closeTo(59.16, .001),
        reason: '行高28.56、作者内边距各8.16和缩放后底距14.28共同占高',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final align in ['right', 'center']) {
    test('自动宽右浮动按最终盒宽重新计算 $align 对齐', () async {
      final source = await _open(
        '.value {float:right; text-align:$align;}',
        '<p><span class="value">完整书名</span></p>',
      );
      final page = (await source.loadChapter(0)).single;
      final line = _line(page, '完整书名');
      expect(line.rect.right, closeTo(_width, .001));
      expect(line.slice.lines.single.offsetX, closeTo(0, .001));
    });
  }

  test('显式宽度的右浮动保留盒内右对齐', () async {
    final source = await _open(
      '.value {float:right; width:160px; text-align:right;}',
      '<p><span class="value">完整书名</span></p>',
    );
    final page = (await source.loadChapter(0)).single;
    final line = _line(page, '完整书名');
    expect(line.slice.block.layout.maxWidth, 160);
    expect(line.slice.lines.single.offsetX, closeTo(76, .001));
    expect(line.rect.right, closeTo(_width, .001));
  });

  test('纯浮动信息行保留独立容器、内边距和完整文字', () async {
    final source = await _open(_rowCss, '<div class="sheet">$_rows</div>');
    _expectRows((await source.loadChapter(0)).single);
  });

  test('信息行底距与相邻说明顶距按外部兄弟边距折叠', () async {
    final source = await _open(
      '$_rowCss .footer {font-size:.75em; line-height:1.8; '
          'margin:2em 0 0; text-align:center;}',
      '<div class="sheet">$_rows<p class="footer">相邻说明</p></div>',
    );
    final page = (await source.loadChapter(0)).single;
    final gap =
        _line(page, '相邻说明').rect.top - _line(page, _labels.last).rect.bottom;
    expect(gap, closeTo(39.66, .001), reason: '8.16px 下内边距加折叠后的31.5px外边距');
  });

  test('同章分栏内容不丢失信息行的独立浮动容器', () async {
    final source = await _open(
      _rowCss,
      '<div class="sheet">$_rows</div>'
      '<div style="column-count:2"><p>相邻正文内容。</p></div>',
    );
    _expectRows((await source.loadChapter(0)).single);
  });

  test('浮动文字重排前后保留正式原文位置', () async {
    final source = await _open(_rowCss, '<div class="sheet">$_rows</div>');
    final anchor = await source.loadAnchorChapter(0);
    final positions = <String, String>{};
    for (final size in [21.0, 20.0]) {
      await source.applyOverrides(
        ReaderOverrides(fontSize: size, lineHeight: 1.6, paragraphSpacing: 10),
      );
      final page = (await source.loadChapter(0)).single;
      for (final text in [..._labels, ..._values]) {
        final block = page.slices
            .singleWhere((slice) => slice.block.layout.text == text)
            .block;
        final cfi = block.cfiAt(0);
        expect(cfi, isNotNull, reason: '浮动文字有真实来源位置');
        expect(anchor.offsetFor(cfi!), anchor.text.indexOf(text));
        expect(block.offsetForCfi(cfi), 0);
        expect(cfi, positions.putIfAbsent(text, () => cfi));
      }
    }
  });

  test('overflow:visible 的纯浮动段落继续共享外部浮动范围', () async {
    final source = await _open(
      '$_rowCss .record {overflow:visible;}',
      '<div class="sheet">$_rows</div>',
    );
    final page = (await source.loadChapter(0)).single;
    expect(
      _line(page, _labels[0]).rect.top,
      closeTo(_line(page, _labels[1]).rect.top, .001),
    );
  });

  test('窄包含块中的浮动换行被段落高度包含，后续行不重叠', () async {
    final source = await _open(
      _rowCss,
      '<div class="sheet">$_rows</div>',
      width: 250,
    );
    final page = (await source.loadChapter(0)).single;
    final lines = TextHitTester.lineBoxes(page);
    for (var i = 0; i < _labels.length; i++) {
      final label = lines.singleWhere((line) => line.text == _labels[i]);
      final values = lines.where(
        (line) => line.slice.block.layout.text == _values[i],
      );
      expect(values.map((line) => line.text).join(), _values[i]);
      if (i + 1 < _labels.length) {
        final next = lines.singleWhere((line) => line.text == _labels[i + 1]);
        expect(next.rect.top, greaterThanOrEqualTo(values.last.rect.bottom));
        expect(next.rect.top, greaterThanOrEqualTo(label.rect.bottom));
      }
    }
  });
}
