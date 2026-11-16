import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/font_face_selection.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/text/script_fallback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List regular;
  late Uint8List bold;
  setUpAll(() async {
    regular = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    bold = await File('../../test_fonts/SourceHanSerifSC-Bold.otf')
        .readAsBytes();
  });

  Future<BookFontLoader> load(String id, String css, List<String> reads) async {
    final loader = BookFontLoader(bookId: id, contentAddressed: true);
    addTearDown(loader.clear);
    await loader.load(
      CssParser.parse(css).fontFaces,
      resolveBytes: (url) async {
        reads.add(url);
        return url.contains('bold') ? bold : regular;
      },
    );
    return loader;
  }

  test('注册表保留同族同字重的不同字符范围和来源', () {
    final registry = CssFontFaceRegistry()
      ..registerAll(
        CssParser.parse('''
@font-face {font-family: Composite; src: url("latin.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("cjk.otf"); unicode-range: U+4E00-9FFF;}
@font-face {font-family: Composite; src: url("other.otf"); unicode-range: U+0-FF;}
''').fontFaces,
      );

    expect(registry.faces, hasLength(3));
    expect(registry.faces.map((face) => face.sources.single.ref), [
      'latin.otf',
      'cjk.otf',
      'other.otf',
    ]);
  });

  test('同族同字重的两个字符分片都读取并注册', () async {
    final reads = <String>[];
    final loader = await load('subset-load', _subsets, reads);

    expect(reads, ['latin.otf', 'cjk-bold.otf']);
    expect(loader.facesOf('Composite'), hasLength(2));
  });

  test('不同 face 保留独立别名，同一字库仅占一份原生注册', () async {
    final before = BookFontLoader.engineLoadCountForTest;
    final loader = await load('subset-same-data', '''
@font-face {font-family: Composite; src: url("same.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("same.otf"); unicode-range: U+4E00-9FFF;}
''', []);
    final faces = loader.facesOf('Composite').values.toList();
    expect(faces, hasLength(2));
    expect(faces.first.selection.alias, isNot(faces.last.selection.alias));
    expect(BookFontLoader.engineLoadCountForTest - before, 1);
    final layout = TextLayoutEngine.layout(
      text: 'A中',
      style: ComputedStyle({'font-family': loader.engineFamily('Composite')!}),
      maxWidth: 240,
    );
    expect(
      layout.runs.map((run) => run.style.fontFamilies.single).toSet(),
      hasLength(2),
    );
    expect(
      layout.runs.map((run) => run.style.fontFamily).toSet(),
      hasLength(1),
    );
  });

  test('正式测量按字符分片生成不同族的连续文本 runs', () async {
    final loader = await load('subset-layout', _subsets, []);
    final style = ComputedStyle({
      'font-family': loader.engineFamily('Composite')!,
      'font-size': '20px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'AB中文',
      style: style,
      maxWidth: 240,
    );

    expect(layout.runs, hasLength(2));
    expect(layout.runs.map((run) => (run.start, run.end)), [(0, 2), (2, 4)]);
    expect(
      layout.runs.first.style.fontFamily,
      isNot(layout.runs.last.style.fontFamily),
    );
    expect(layout.text, 'AB中文');
  });

  test('先匹配字重再检查字符覆盖，不能借用另一字重的分片', () async {
    final loader = await load('subset-weight-fallback', '''
@font-face {font-family: Composite; src: url("latin.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("cjk-bold.otf"); font-weight: 700; unicode-range: U+4E00-9FFF;}
@font-face {font-family: Fallback; src: url("fallback.otf");}
''', []);
    final fallback = ComputedStyle({
      'font-family': loader.engineFamily('Fallback')!,
    }).fontFamily;
    final style = ComputedStyle({
      'font-family':
          '"${loader.engineFamily('Composite')}", '
          '"${loader.engineFamily('Fallback')}"',
      'font-size': '20px',
      'font-weight': '400',
    });
    final layout = TextLayoutEngine.layout(
      text: 'A中',
      style: style,
      maxWidth: 240,
    );

    expect(layout.runs, hasLength(2));
    expect(layout.runs.last.style.fontFamily, fallback);
  });

  test('补充平面字符以完整码点选族，runs 保持 UTF-16 坐标', () {
    final runs = buildScriptFontRuns(
      'A𠀀B',
      const ['latin', 'supplementary'],
      hasGlyph: (family, codePoint) =>
          family == 'latin' ? codePoint < 0x100 : codePoint == 0x20000,
    );

    expect(runs.map((run) => (run.start, run.end, run.family)), [
      (0, 1, 'latin'),
      (1, 3, 'supplementary'),
      (3, 4, 'latin'),
    ]);
  });

  test('测量优先完整字簇，组合附加符不会被强制拆到另一字体', () {
    final layout = TextLayoutEngine.layout(
      text: 'A\u0301B',
      style: ComputedStyle({
        'font-family': 'cluster_latin, cluster_mark, cluster_whole',
      }),
      maxWidth: 240,
      hasGlyph: (family, codePoint) => switch (family) {
        'cluster_latin' => codePoint == 0x41 || codePoint == 0x42,
        'cluster_mark' => codePoint == 0x301,
        'cluster_whole' => codePoint == 0x41 || codePoint == 0x301,
        _ => false,
      },
    );
    expect(
      layout.runs.map((run) => (run.start, run.end, run.style.fontFamily)),
      [(0, 2, 'cluster_whole'), (2, 3, 'cluster_latin')],
    );
  });

  test('原始范围包含零开头、通配符和列表，非法描述符整体忽略', () {
    final faces = CssParser.parse('''
@font-face {font-family: Ranges; src: url("f.otf"); unicode-range: U+0-FF, U+4E??, U+20000;}
''').fontFaces;
    expect(faces.single.unicodeRange, 'U+0-FF, U+4E??, U+20000');
    final range = CssUnicodeRange.parse(faces.single.unicodeRange);
    for (final point in [0, 0xff, 0x4e00, 0x4eff, 0x20000]) {
      expect(range.covers(point), isTrue, reason: '$point');
    }
    for (final point in [0x100, 0x4f00, 0x20001]) {
      expect(range.covers(point), isFalse, reason: '$point');
    }
    for (final raw in [
      'U+FF-0',
      'U+4?0?',
      'U+110000',
      'U+0-110000',
      'U+??????',
      'U+1?????',
      'U+0-FF, bad',
    ]) {
      expect(CssUnicodeRange.tryParse(raw), isNull, reason: raw);
      expect(CssUnicodeRange.parse(raw).covers(0x4e2d), isTrue, reason: raw);
    }
    expect(
      CssUnicodeRange.parse('U+0-FF').fingerprint,
      CssUnicodeRange.parse('u+0000-00ff').fingerprint,
    );
    final duplicate = CssParser.parse('''
@font-face {font-family: Ranges; src: url("f.otf"); unicode-range: U+0-FF; unicode-range: bad;}
''').fontFaces.single;
    expect(duplicate.unicodeRange, 'U+0-FF', reason: '非法后声明不能覆盖已有有效范围');
  });

  test('同属性重叠范围优先后声明，绘制 span 沿用测量 face', () async {
    final loader = await load('subset-overlap', '''
@font-face {font-family: Composite; src: url("latin.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("later-bold.otf"); unicode-range: U+41;}
''', []);
    final faces = loader.facesOf('Composite').values.toList();
    final style = ComputedStyle({
      'font-family': loader.engineFamily('Composite')!,
    });
    final layout = TextLayoutEngine.layout(
      text: 'AB',
      style: style,
      maxWidth: 240,
    );
    expect(
      layout.runs.map((run) => (run.start, run.end, run.style.fontFamily)),
      [
        (0, 1, faces.last.selection.nativeFamily),
        (1, 2, faces.first.selection.nativeFamily),
      ],
    );
    final span = buildLineSpan(
      layout: layout,
      line: layout.lines.single,
      baseStyle: TextLayoutEngine.textStyleFor(style),
    );
    final drawn = <String>[];
    span.visitChildren((child) {
      if (child.style?.fontFamily case final family?) drawn.add(family);
      return true;
    });
    expect(
      drawn,
      containsAllInOrder([
        faces.last.selection.nativeFamily,
        faces.first.selection.nativeFamily,
      ]),
    );
  });

  test('样式先匹配，normal 缺失时先用 oblique，继承族仍可重新选粗体', () async {
    final loader = await load('subset-style', '''
@font-face {font-family: Composite; src: url("oblique.otf"); font-style: oblique;}
@font-face {font-family: Composite; src: url("italic-bold.otf"); font-style: italic;}
@font-face {font-family: Composite; src: url("heavy-bold.otf"); font-style: oblique; font-weight: 700;}
''', []);
    final faces = loader.facesOf('Composite').values.toList();
    final parent = ComputedStyle({
      'font-family': loader.engineFamily('Composite')!,
    });
    final italic = ComputedStyle({'font-style': 'italic'}, parent: parent);
    final heavy = ComputedStyle({'font-weight': '700'}, parent: parent);
    expect(parent.fontFamily, faces[0].selection.nativeFamily);
    expect(italic.fontFamily, faces[1].selection.nativeFamily);
    expect(heavy.fontFamily, faces[2].selection.nativeFamily);
    expect(heavy.fontFamilies, parent.fontFamilies);
    final layout = TextLayoutEngine.layout(
      text: 'AB',
      style: parent,
      maxWidth: 240,
      runs: [StyledRun(start: 1, end: 2, style: heavy)],
    );
    expect(layout.runs.map((run) => run.style.fontFamily), [
      faces[0].selection.nativeFamily,
      faces[2].selection.nativeFamily,
    ]);
    expect(italic.layoutFingerprint, isNot(heavy.layoutFingerprint));
  });

  test('400 优先 500 再轻字重，600 优先更重再更轻', () async {
    final loader = await load('subset-weight-order', '''
@font-face {font-family: Composite; src: url("light.otf"); font-weight: 300;}
@font-face {font-family: Composite; src: url("medium.otf"); font-weight: 500;}
@font-face {font-family: Composite; src: url("heavy-bold.otf"); font-weight: 700;}
''', []);
    final faces = loader.facesOf('Composite').values.toList();
    final parent = ComputedStyle({
      'font-family': loader.engineFamily('Composite')!,
    });
    expect(parent.fontFamily, faces[1].selection.nativeFamily);
    expect(
      ComputedStyle({'font-weight': '600'}, parent: parent).fontFamily,
      faces[2].selection.nativeFamily,
    );
    expect(
      ComputedStyle({'font-weight': '200'}, parent: parent).fontFamily,
      faces[0].selection.nativeFamily,
    );
  });

  test('local 分片限制只作用于声明，不改内置族的全局覆盖', () async {
    final loader = await load('subset-local', '''
@font-face {font-family: Composite; src: local("宋体"); unicode-range: U+0-FF;}
@font-face {font-family: Fallback; src: url("fallback.otf");}
''', []);
    final fallback = ComputedStyle({
      'font-family': loader.engineFamily('Fallback')!,
    }).fontFamily;
    final style = ComputedStyle({
      'font-family':
          '"${loader.engineFamily('Composite')}", "${loader.engineFamily('Fallback')}"',
    });
    final layout = TextLayoutEngine.layout(
      text: 'A中',
      style: style,
      maxWidth: 240,
    );
    expect(layout.runs.map((run) => run.style.fontFamily), [
      FontFamilyAliases.song,
      fallback,
    ]);
    final unrestricted = TextLayoutEngine.layout(
      text: '中',
      style: ComputedStyle({'font-family': FontFamilyAliases.song}),
      maxWidth: 240,
      hasGlyph: (_, _) => true,
    );
    expect(unrestricted.runs.single.style.fontFamily, FontFamilyAliases.song);
  });
}

const _subsets = '''
@font-face {font-family: Composite; src: url("latin.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("cjk-bold.otf"); unicode-range: U+4E00-9FFF;}
''';
