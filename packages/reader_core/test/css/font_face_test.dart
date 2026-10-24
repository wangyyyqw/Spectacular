import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';

void main() {
  group('CssFontFaceExtractor', () {
    test('多来源 src 按声明顺序解析（cloverfield 真实样本）', () {
      const css = '''
@font-face {
    font-family: "songti";
    src:
        url("../Fonts/SourceHanSerifCN.otf"),
        url("../Fonts/HYXuanSong45S.ttf"),
        local("Source Han Serif CN Medium"),
        local("HYXuanSong 45S");
}
''';
      final sheet = CssParser.parse(css);
      expect(sheet.fontFaces, hasLength(1));
      final face = sheet.fontFaces.single;
      expect(face.family, 'songti');
      expect(face.sources, hasLength(4));
      expect(face.sources[0].isLocal, isFalse);
      expect(face.sources[0].ref, '../Fonts/SourceHanSerifCN.otf');
      expect(face.sources[1].ref, '../Fonts/HYXuanSong45S.ttf');
      expect(face.sources[2].isLocal, isTrue);
      expect(face.sources[2].ref, 'Source Han Serif CN Medium');
      expect(face.sources[3].ref, 'HYXuanSong 45S');
      // csslib 的 FontFaceDirective 已静默处理，不产生噪音告警。
      expect(sheet.warnings, isEmpty);
    });

    test('中文 family 与 local 兜底（shiji-yuewei 真实样本）', () {
      const css = '''
@font-face {
	font-family:"三极花朝体";
	src:
	local("三极花朝体"),
	url("../Fonts/三极花朝体.ttf")
}

@font-face {
	font-family:"手写体";
	src:
	local("手写体"),
	url("../Fonts/手写体.ttf")
}
''';
      final sheet = CssParser.parse(css);
      expect(sheet.fontFaces.map((f) => f.family),
          ['三极花朝体', '手写体']);
      expect(sheet.fontFaces.first.sources.first.isLocal, isTrue);
    });

    test('weight/style 描述符归一化', () {
      const css = '''
@font-face {
  font-family: A;
  src: url("a-bold.ttf");
  font-weight: bold;
  font-style: italic;
}
@font-face {
  font-family: B;
  src: url("b.ttf");
  font-weight: 400;
  font-style: normal;
}
''';
      final faces = CssParser.parse(css).fontFaces;
      expect(faces[0].normalizedWeight, 700);
      expect(faces[0].normalizedStyle, 'italic');
      expect(faces[1].normalizedWeight, 400);
      expect(faces[1].normalizedStyle, 'normal');
    });

    test('format 提示与不支持格式', () {
      const css = '''
@font-face { font-family: A; src: url("a.woff2") format("woff2"); }
@font-face { font-family: B; src: url("b.ttf") format('truetype'); }
@font-face { font-family: C; src: local("Foo"); }
''';
      final faces = CssParser.parse(css).fontFaces;
      expect(faces[0].sources.single.isUnsupportedFormat, isTrue);
      expect(faces[1].sources.single.format, 'truetype');
      expect(faces[1].sources.single.isUnsupportedFormat, isFalse);
      expect(faces[2].sources.single.isLocal, isTrue);
    });

    test('注释与字符串里的 @font-face 不误命中', () {
      const css = '''
/* @font-face { font-family: Ghost; src: url("ghost.ttf"); } */
p::before { content: "@font-face"; }
@font-face { font-family: Real; src: url("real.ttf"); }
''';
      final sheet = CssParser.parse(css);
      expect(sheet.fontFaces.map((f) => f.family), ['Real']);
    });

    test('缺 font-family 的块跳过并告警；未闭合块丢弃', () {
      const css = '''
@font-face { src: url("a.ttf"); }
@font-face { font-family: Broken; src: url("b.ttf");
''';
      final sheet = CssParser.parse(css);
      expect(sheet.fontFaces, isEmpty);
      expect(
        sheet.warnings.any((w) => w.contains('缺少 font-family')),
        isTrue,
      );
      expect(sheet.warnings.any((w) => w.contains('未闭合')), isTrue);
    });

    test('@media 与普通规则解析不受影响', () {
      const css = '''
p { margin: 0; }
@media (min-width: 100px) { p { color: red; } }
@font-face { font-family: F; src: url("f.ttf"); }
''';
      final sheet = CssParser.parse(css);
      expect(sheet.rules, hasLength(2));
      expect(sheet.fontFaces.single.family, 'F');
    });
  });

  group('CssFontFaceRegistry 去重与注册任务', () {
    test('同一 family 重复声明按顺序覆盖', () {
      const first = '''
@font-face { font-family: Song; src: url("old.ttf"); }
''';
      const second = '''
@font-face { font-family: Song; src: url("new.ttf"); }
''';
      final registry = CssFontFaceRegistry()
        ..registerAll(CssParser.parse(first).fontFaces)
        ..registerAll(CssParser.parse(second).fontFaces);
      expect(registry.faces, hasLength(1));
      expect(registry.faces.single.sources.single.ref, 'new.ttf');
    });

    test('不同字重的同族 face 共存（P3-02 多字重依赖）', () {
      const css = '''
@font-face { font-family: Song; src: url("s-regular.ttf"); font-weight: normal; }
@font-face { font-family: Song; src: url("s-bold.ttf"); font-weight: bold; }
@font-face { font-family: Song; src: url("s-italic.ttf"); font-style: italic; }
''';
      final registry = CssFontFaceRegistry()
        ..registerAll(CssParser.parse(css).fontFaces);
      expect(registry.faces, hasLength(3));
      final weights = registry.faces.map((f) => f.normalizedWeight).toList();
      expect(weights, containsAll(<int?>[400, 700, null]));
      expect(registry.faces[2].normalizedStyle, 'italic');
    });

    test('无 src 的 face 拒绝登记并告警', () {
      const css = '@font-face { font-family: Empty; }';
      final registry = CssFontFaceRegistry()
        ..registerAll(CssParser.parse(css).fontFaces);
      expect(registry.faces, isEmpty);
      expect(registry.warnings, isNotEmpty);
    });

    test('注册任务按 resolveUrl 解析相对地址，local 原样保留', () {
      const css = '''
@font-face {
  font-family: "songti";
  src: url("../Fonts/SourceHanSerifCN.otf"), local("Source Han Serif CN Medium");
}
''';
      final registry = CssFontFaceRegistry()
        ..registerAll(CssParser.parse(css).fontFaces);
      final tasks = registry.registrationTasks(
        resolveUrl: (url) => _resolve('OEBPS/styles/main.css', url),
      );
      expect(tasks, hasLength(1));
      final sources = tasks.single.sources;
      expect(sources[0].ref, 'OEBPS/Fonts/SourceHanSerifCN.otf');
      expect(sources[0].isLocal, isFalse);
      expect(sources[1].isLocal, isTrue);
      expect(sources[1].ref, 'Source Han Serif CN Medium');
    });

    test('resolveUrl 为 null 时地址原样透传', () {
      const css = '@font-face { font-family: F; src: url("../x.ttf"); }';
      final registry = CssFontFaceRegistry()
        ..registerAll(CssParser.parse(css).fontFaces);
      expect(registry.registrationTasks().single.sources.single.ref,
          '../x.ttf');
    });
  });
}

/// 与 P3-02/P3-25 将共用的 EPUB 相对地址归一（minimal POSIX join）。
String _resolve(String base, String ref) {
  final baseParts = base.split('/')..removeLast();
  for (final segment in ref.split('/')) {
    if (segment == '.') {
      continue;
    } else if (segment == '..') {
      if (baseParts.isNotEmpty) {
        baseParts.removeLast();
      }
    } else {
      baseParts.add(segment);
    }
  }
  return baseParts.join('/');
}
