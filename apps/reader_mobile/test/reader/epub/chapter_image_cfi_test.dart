import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/extension.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';

const _imagePath = 'OEBPS/Images/p.png';
const _sourcePath = '../Images/p.png';
const _svgStart =
    '<svg id="svg" xmlns="http://www.w3.org/2000/svg" '
    'xmlns:xlink="http://www.w3.org/1999/xlink">';

Future<EpubChapterSource> _open(
  String body, {
  String css = '',
  bool fixed = false,
  String flags = '',
  double contentHeight = 500,
}) async {
  final source = await openCssChapter(
    body: body,
    css: 'body,p { margin:0; } $css',
    itemrefAttributes: flags.isEmpty ? '' : ' properties="$flags"',
    contentHeight: contentHeight,
    binaryFiles: {
      _imagePath: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
      ),
      if (fixed)
        DuokanExtensionParser.path: utf8.encode(
          '<duokan-extension version="1.0"><display-options>'
          '<layout>fixed-page</layout>'
          '</display-options></duokan-extension>',
        ),
    },
  );
  addTearDown(source.close);
  return source;
}

Iterable<PageBlock> _imageBlocks(List<PageContent> pages) sync* {
  final seen = <PageBlock>{};
  for (final page in pages) {
    for (final slice in page.slices) {
      yield* _payloadImages(slice.block, seen);
    }
  }
}

Iterable<PageBlock> _payloadImages(PageBlock block, Set<PageBlock> seen) sync* {
  if (!seen.add(block)) return;
  if (block.layout.text.isEmpty && block.style?.backgroundImage == _imagePath) {
    yield block;
  }
  for (final line in block.layout.lines) {
    for (final box in line.inlineBoxes) {
      final payload = box.spec.payload;
      if (payload is PageBlock) yield* _payloadImages(payload, seen);
    }
  }
}

Future<List<PageContent>> _expectImages(
  EpubChapterSource source,
  List<String> ids,
) async {
  final parsed = source.document.parseDocument(0);
  final expected = [
    for (final id in ids) parsed.elementById(id)!.cfi.serialize(),
  ];
  for (final id in ids) {
    expect(parsed.elementById(id)!.tag, isIn(['img', 'image', 'object']));
  }
  final pages = await source.loadChapter(0);
  final images = _imageBlocks(pages).toList();
  expect(images.map((block) => block.startCfi), expected);
  expect(images.map((block) => block.startCfi).toSet(), hasLength(ids.length));
  return pages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('混合图文的标题、容器和图片共用正文坐标且保留原始 CFI', () async {
    final source = await _open(
      '<h2 id="title">标题</h2><p>前文</p>'
      '<div id="outer"><img id="picture" src="$_sourcePath" '
      'width="80" height="100"/></div><p>后文</p>'
      '<p>甲<span id="inside">乙<img id="inline" src="$_sourcePath" '
      'width="20" height="20"/>丙</span>丁</p>'
      '<p id="hidden" style="display:none">隐藏正文</p>',
    );
    await source.loadChapter(0);
    final chapter = await source.loadAnchorChapter(0);
    final book = AnchorBook(revision: '元素进度', chapters: [chapter]);
    final parsed = source.document.parseDocument(0);
    expect(chapter.text, '标题前文后文甲乙\uFFFC丙丁');
    for (final entry in {
      'title': 0,
      'outer': 4,
      'picture': 4,
      'inside': 7,
      'inline': 8,
    }.entries) {
      final cfi = parsed.elementById(entry.key)!.cfi.serialize();
      expect(chapter.offsetFor(cfi), entry.value, reason: entry.key);
      expect(
        source.readingPercentForCfi(cfi),
        closeTo(entry.value / chapter.text.length, 1e-9),
      );
      final anchor = book.capture(cfi)!;
      expect(anchor.start.cfi, cfi, reason: '元素位置不能替换成邻近文字');
      expect(anchor.start.charOffset, entry.value);
      expect(
        book.capture(cfiWithCharOffset(cfi, 0))?.start.charOffset,
        entry.value,
      );
      expect(book.capture(cfiWithCharOffset(cfi, 1)), isNull);
    }
    final hidden = parsed.elementById('hidden')!.cfi.serialize();
    expect(source.readingPercentForCfi(hidden), isNull);
    expect(book.capture('epubcfi(/6/2!/4/9998)'), isNull);
  });

  test('混合正文中重复 data 的 object 经真实聚合和遍历保留可见叶 CFI', () async {
    final source = await _open(
      '<p>正文之前。</p>'
      '<div><object id="a" data="$_sourcePath" width="80" height="40"/></div>'
      '<p>正文之间。</p>'
      '<section><object id="b" data="$_sourcePath" width="60" height="30"/></section>',
      css: 'object { display:inline; }',
    );
    await _expectImages(source, ['a', 'b']);
  });

  test('混合正文中的浮动 object 按自身叶 CFI 提取图片', () async {
    final source = await _open(
      '<p>正文<object id="a" data="$_sourcePath" width="80" height="40" '
      'style="float:left"/>图片后的正文。</p>'
      '<p>正文<object id="b" data="$_sourcePath" width="60" height="30" '
      'style="float:right"/>第二张后的正文。</p>',
      css: 'object { display:inline; }',
    );
    await _expectImages(source, ['a', 'b']);
  });

  test('同段正文中的重复 object 内联载荷按原始元素身份绑定', () async {
    final source = await _open(
      '<p>前<object id="a" data="$_sourcePath" width="80" height="40"/>'
      '中<object id="b" data="$_sourcePath" width="60" height="30"/>后。</p>',
      css: 'object { display:inline; }',
    );
    await _expectImages(source, ['a', 'b']);
  });

  test('未引用图片的 object 保留原有回退正文', () async {
    final source = await _open(
      '<p>前<object>回退正文</object>后。</p>',
      css: 'object { display:inline; }',
    );
    final pages = await source.loadChapter(0);
    expect(
      pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join(),
      '前回退正文后。',
    );
    expect(_imageBlocks(pages), isEmpty);
  });

  for (final attributes in ['', ' data=""', ' data="   "']) {
    test('纯图章中无有效 data 的 object 使用回退 img 叶坐标：$attributes', () async {
      final source = await _open(
        '<object id="parent"$attributes><img id="visible" '
        'src="$_sourcePath" width="80" height="100"/></object>',
        css: 'object { display:inline; }',
        fixed: true,
        flags: 'duokan-page-fitwindow',
      );
      final pages = await _expectImages(source, ['visible']);
      expect(pages, hasLength(1));
      final parsed = source.document.parseDocument(0);
      final leaf = parsed.elementById('visible')!.cfi.serialize();
      final parent = parsed.elementById('parent')!.cfi.serialize();
      expect(source.cfiForReadingPercent(0.5), leaf);
      expect(source.readingPercentForCfi(leaf), 0);
      expect(source.readingPercentForCfi(parent), isNull);
    });
  }

  test('纯图章多个 object 的重复 src 回退图片可按 CFI 和比例跳转', () async {
    final source = await _open(
      [
        for (var i = 0; i < 3; i++)
          '<div><object${i == 1 ? ' data="   "' : ''}>'
              '<img id="leaf-$i" src="$_sourcePath" width="80" height="100"/>'
              '</object></div>',
      ].join(),
      css: 'object { display:inline; }',
      contentHeight: 120,
    );
    final pages = await _expectImages(source, ['leaf-0', 'leaf-1', 'leaf-2']);
    expect(pages, hasLength(3));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'object-fallback-images',
    );
    addTearDown(session.dispose);
    await session.open();
    final parsed = source.document.parseDocument(0);
    for (var i = 2; i >= 0; i--) {
      final leaf = parsed.elementById('leaf-$i')!.cfi.serialize();
      expect(source.readingPercentForCfi(leaf), i / 2);
      expect(source.cfiForReadingPercent(i / 2), leaf);
      await session.jumpToCfi(leaf);
      expect(session.progress?.pageIndex, i);
      expect(_imageBlocks([session.page!]).single.startCfi, leaf);
    }
    for (var i = 0; i < 3; i++) {
      await session.seekToReadingPercent(i / 2);
      expect(session.progress?.pageIndex, i);
      expect(
        _imageBlocks([session.page!]).single.startCfi,
        parsed.elementById('leaf-$i')!.cfi.serialize(),
      );
    }
  });

  test('UA 默认隐藏的 object 不占可见图片页', () async {
    final source = await _open(
      '<p>可见正文。</p><object data="$_sourcePath" width="80" height="40"/>',
    );
    final pages = await source.loadChapter(0);
    expect(_imageBlocks(pages), isEmpty);
    expect(
      pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join(),
      '可见正文。',
    );
  });

  test('固定页中的可见 object 与重复 src img 不误走单图快路', () async {
    final source = await _open(
      '<div><object id="a" data="$_sourcePath" width="80" height="100"/></div>'
      '<div><img id="b" src="$_sourcePath" width="60" height="100"/></div>',
      css: 'object { display:inline; }',
      fixed: true,
      flags: 'duokan-page-fitwindow',
      contentHeight: 120,
    );
    final pages = await _expectImages(source, ['a', 'b']);
    expect(pages, hasLength(2));
  });

  test('固定页中的单 object 只绘制图片并保留真实叶 CFI', () async {
    final source = await _open(
      '<div><object id="visible" data="$_sourcePath" width="80" height="100">'
      '备用文字<img src="$_sourcePath"/></object></div>',
      css: 'object { display:inline; }',
      fixed: true,
      flags: 'duokan-page-fitwindow',
    );
    final pages = await _expectImages(source, ['visible']);
    expect(pages.single.slices.single.block.layout.height, 500);
  });

  for (final reference in ['xlink:href', 'href']) {
    test('同一 SVG 多 image 重复 $reference 的内联载荷使用各自真实 CFI', () async {
      final source = await _open(
        '<p>正文。</p><div>$_svgStart'
        '<image id="a" $reference="$_sourcePath" width="80" height="40"/>'
        '<image id="b" $reference="$_sourcePath" width="60" height="30"/>'
        '</svg></div>',
      );
      await _expectImages(source, ['a', 'b']);
    });
  }

  test('正文后的单 SVG image href 经折叠后保留真实叶 CFI', () async {
    final source = await _open(
      '<p>正文。</p><div>$_svgStart'
      '<image id="visible" href="$_sourcePath" width="80" height="40"/>'
      '</svg></div>',
    );
    await _expectImages(source, ['visible']);
  });

  test('同一 SVG 多张浮动 image 重复 src 按真实叶绑定', () async {
    final source = await _open(
      '<p>正文。</p>$_svgStart'
      '<image id="a" xlink:href="$_sourcePath" width="80" height="40"/>'
      '<image id="b" xlink:href="$_sourcePath" width="60" height="30"/>'
      '</svg>',
      css: 'image { float:left; }',
    );
    await _expectImages(source, ['a', 'b']);
  });

  for (final flags in ['duokan-page-fullscreen', 'duokan-page-fitwindow']) {
    test('满屏快路在隐藏+可见重复 src 中选择可见 img：$flags', () async {
      final source = await _open(
        '<div class="hidden"><img id="hidden" src="$_sourcePath"/></div>'
        '<div id="outer"><img id="visible" src="$_sourcePath" '
        'width="100" height="200"/></div>',
        css: '.hidden { display:none; }',
        fixed: true,
        flags: flags,
      );
      final pages = await _expectImages(source, ['visible']);
      expect(pages, hasLength(1));
      expect(pages.single.slices, hasLength(1));
    });
  }

  test('单 SVG 隐藏+可见重复 src 的满屏快路选择可见 image 叶', () async {
    final source = await _open(
      '$_svgStart'
      '<image id="hidden" xlink:href="$_sourcePath" style="display:none"/>'
      '<image id="visible" xlink:href="$_sourcePath" width="100" height="200"/>'
      '</svg>',
      fixed: true,
      flags: 'duokan-page-fitwindow',
    );
    await _expectImages(source, ['visible']);
  });

  test('满屏唯一 img 保留原本真实的非空 CFI', () async {
    final source = await _open(
      '<div><img id="visible" src="$_sourcePath" width="100" height="200"/></div>',
      fixed: true,
    );
    await _expectImages(source, ['visible']);
  });

  for (final count in [2, 3]) {
    test('$count 张图片通过真实叶 CFI 及零偏移跳到对应页面', () async {
      final source = await _open(
        [
          for (var i = 0; i < count; i++)
            '<div id="parent-$i"><img id="leaf-$i" src="$_sourcePath" '
                'width="80" height="100"/></div>',
        ].join(),
        contentHeight: 120,
      );
      final ids = [for (var i = 0; i < count; i++) 'leaf-$i'];
      final pages = await _expectImages(source, ids);
      expect(pages, hasLength(count));
      final session = ReaderSession(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: 'image-leaf-$count',
      );
      addTearDown(session.dispose);
      await session.open();
      final parsed = source.document.parseDocument(0);
      for (final withOffset in [false, true]) {
        for (var i = count - 1; i >= 0; i--) {
          final parent = parsed.elementById('parent-$i')!.cfi.serialize();
          expect(source.readingPercentForCfi(parent), isNull);
          final leaf = parsed.elementById('leaf-$i')!.cfi.serialize();
          final target = withOffset ? cfiWithCharOffset(leaf, 0) : leaf;
          await session.jumpToCfi(target);
          expect(session.progress?.pageIndex, i, reason: target);
          expect(
            _imageBlocks([session.page!]).single.startCfi,
            parsed.elementById('leaf-$i')!.cfi.serialize(),
            reason: target,
          );
        }
      }
    });
  }
}
