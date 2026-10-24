import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/line_breaker.dart';

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

  group('FontFamilyAliases 中文别名映射（P3-03）', () {
    test('§68.3 别名表全等命中', () {
      expect(FontFamilyAliases.resolve('宋体'), FontFamilyAliases.song);
      expect(FontFamilyAliases.resolve('楷体'), FontFamilyAliases.kai);
      expect(FontFamilyAliases.resolve('黑体'), FontFamilyAliases.hei);
      expect(FontFamilyAliases.resolve('serif'), FontFamilyAliases.song);
      expect(FontFamilyAliases.resolve('sans-serif'), FontFamilyAliases.hei);
      expect(FontFamilyAliases.resolve('simsun'), FontFamilyAliases.song);
    });

    test('小写与去空格匹配', () {
      expect(FontFamilyAliases.resolve('SIMSUN'), FontFamilyAliases.song);
      expect(
        FontFamilyAliases.resolve('Microsoft YaHei'),
        FontFamilyAliases.hei,
      );
      expect(
        FontFamilyAliases.resolve('Noto Serif CJK SC'),
        FontFamilyAliases.song,
      );
    });

    test('不做包含匹配：宋体黑不命中', () {
      expect(FontFamilyAliases.resolve('宋体黑'), isNull);
      expect(FontFamilyAliases.resolve('宋体黑体'), isNull);
      expect(FontFamilyAliases.resolve('MySerif'), isNull);
    });

    test('未命中原样保留（显式回退）', () {
      expect(FontFamilyAliases.resolve('三极花朝体'), isNull);
      expect(FontFamilyAliases.mapFamilies(['三极花朝体', '宋体']),
          ['三极花朝体', FontFamilyAliases.song]);
    });

    test('textStyleFor 集成：主族与 fallback 都映射', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': '宋体, 黑体, SourceHan',
      });
      final textStyle = TextLayoutEngine.textStyleFor(style);
      expect(textStyle.fontFamily, FontFamilyAliases.song);
      expect(textStyle.fontFamilyFallback,
          [FontFamilyAliases.hei, 'SourceHan']);
    });

    test('书内注册引擎族（bi_ 前缀）不受别名影响', () {
      expect(FontFamilyAliases.resolve('bi_1_songti'), isNull);
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'bi_1_songti',
      });
      expect(TextLayoutEngine.textStyleFor(style).fontFamily, 'bi_1_songti');
    });

    test('10 组常见字体名全部能映射或显式回退', () {
      const samples = <String>[
        '宋体', '黑体', '楷体', '仿宋', '微软雅黑', '苹方',
        'Source Han Serif CN', 'Noto Sans CJK SC', 'serif', 'sans-serif',
      ];
      final mapped = <String, String?>{
        for (final name in samples) name: FontFamilyAliases.resolve(name),
      };
      // 每一项要么映射到内置规范名，要么明确返回 null（保留原名回退），
      // 不存在歧义结果。
      for (final entry in mapped.entries) {
        expect(
          entry.value == null ||
              entry.value == FontFamilyAliases.song ||
              entry.value == FontFamilyAliases.kai ||
              entry.value == FontFamilyAliases.hei,
          isTrue,
          reason: '${entry.key} → ${entry.value}',
        );
      }
      expect(mapped['宋体'], FontFamilyAliases.song);
      expect(mapped['Source Han Serif CN'], FontFamilyAliases.song);
      // 仿宋不在表内：显式回退（保留原名），后续版本按需补。
      expect(mapped['仿宋'], isNull);
    });

    test('映射后渲染可用：族名交引擎回退仍出墨，无异常', () async {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': '宋体',
      });
      final textStyle = TextLayoutEngine.textStyleFor(style);
      expect(textStyle.fontFamily, FontFamilyAliases.song);
      // 内置字族未注册时引擎回退系统默认；测试环境渲染应正常产出
      // 文本像素（不崩溃、不留白）——豆腐块判定在 P3-30 真机核销。
      final painter = TextPainter()
        ..textDirection = TextDirection.ltr
        ..text = TextSpan(text: '宋体回退测试', style: textStyle)
        ..layout();
      expect(painter.width, greaterThan(0));
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
