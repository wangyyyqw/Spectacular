import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/text/font_metrics.dart';

const _regularPath = '../../test_fonts/SourceHanSerifSC-Regular.otf';
const _boldPath = '../../test_fonts/SourceHanSerifSC-Bold.otf';

Future<Uint8List> _fileBytes(String path) => File(path).readAsBytes();

List<CssFontFace> _parse(String css) => CssParser.parse(css).fontFaces;

void main() {
  group('BookFontLoader 多字重注册（方案 A）', () {
    test('同一 family 的 regular/bold 注册后按 fontWeight 正确选中', () async {
      final loader = BookFontLoader(bookId: 't1');
      final faces = _parse('''
@font-face { font-family: "songti"; src: url("$_regularPath"); font-weight: normal; }
@font-face { font-family: "songti"; src: url("$_boldPath"); font-weight: bold; }
''');
      final result = await loader.load(
        faces,
        resolveBytes: (url) => _fileBytes(url),
      );
      expect(result.warnings, isEmpty);
      final engine = loader.engineFamily('songti');
      expect(engine, 'bi_t1_songti');
      expect(loader.facesOf('songti').keys.toSet(), {'w400i0', 'w700i0'});
      expect(
        FontMetricsRegistry.xHeightRatio(engine),
        closeTo(0.514, 0.0001),
      );

      final regular = await _render(engine!, 400);
      final bold = await _render(engine, 700);
      expect(_diffBytes(regular, bold), greaterThan(0),
          reason: 'S5 口径：bold face 生效应产生像素差异');
    });

    test('书间族名隔离：不同 bookId 同族名互不影响', () async {
      final a = BookFontLoader(bookId: 'a');
      final b = BookFontLoader(bookId: 'b');
      final faces = _parse(
        '@font-face { font-family: F; src: url("$_regularPath"); }',
      );
      await a.load(faces, resolveBytes: _fileBytes);
      await b.load(faces, resolveBytes: _fileBytes);
      expect(a.engineFamily('F'), 'bi_a_F');
      expect(b.engineFamily('F'), 'bi_b_F');
      expect(a.engineFamily('F'), isNot(b.engineFamily('F')));
    });

    test('资源缺失：该族不可用并告警，其他族不受影响', () async {
      final loader = BookFontLoader(bookId: 't2');
      final faces = _parse('''
@font-face { font-family: Missing; src: url("nope.otf"); }
@font-face { font-family: Good; src: url("$_regularPath"); }
''');
      final result = await loader.load(faces, resolveBytes: _fileBytes);
      expect(loader.engineFamily('Missing'), isNull);
      expect(loader.engineFamily('Good'), isNotNull);
      expect(result.warnings.any((w) => w.contains('Missing')), isTrue);
      expect(result.engineFamilies.keys, ['Good']);
    });

    test('坏字节：不阻断加载流程，返回结果供降级路径使用', () async {
      final loader = BookFontLoader(bookId: 't3');
      final faces = _parse(
        '@font-face { font-family: Broken; src: url("bad.otf"); }',
      );
      // 测试环境引擎对字形数据惰性解析，坏字节可能在 load 或首次渲染
      // 才暴露；本断言锁定「任何阶段失败都不向上抛出」的契约（P3-06
      // 在真机核销提示路径）。
      final result = await loader.load(
        faces,
        resolveBytes: (url) async => Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(result.engineFamilies, isA<Map<String, String>>());
    });

    test('local-only face 暂不可加载，告警且族不可用', () async {
      final loader = BookFontLoader(bookId: 't4');
      final faces = _parse(
        '@font-face { font-family: OnlyLocal; src: local("Song"); }',
      );
      final result = await loader.load(faces, resolveBytes: _fileBytes);
      expect(loader.engineFamily('OnlyLocal'), isNull);
      expect(result.warnings.any((w) => w.contains('local')), isTrue);
    });

    test('woff2 跳过后继续尝试下一 url 来源', () async {
      final loader = BookFontLoader(bookId: 't5');
      final faces = _parse('''
@font-face { font-family: Fallback; src: url("x.woff2") format("woff2"), url("$_regularPath") format("opentype"); }
''');
      final result = await loader.load(faces, resolveBytes: _fileBytes);
      expect(loader.engineFamily('Fallback'), isNotNull);
      expect(
        result.warnings.any(
          (w) => w.contains('格式不支持') && w.contains('woff2'),
        ),
        isTrue,
      );
    });

    test('注册缓存：同键集二次加载不重复读字节', () async {
      final loader = BookFontLoader(bookId: 't6');
      final faces = _parse(
        '@font-face { font-family: C; src: url("$_regularPath"); }',
      );
      var calls = 0;
      Future<Uint8List?> counting(String url) async {
        calls += 1;
        return _fileBytes(url);
      }

      await loader.load(faces, resolveBytes: counting);
      final afterFirst = calls;
      expect(afterFirst, 1);
      await loader.load(faces, resolveBytes: counting);
      expect(calls, afterFirst, reason: '缓存键命中后不应再读取字形数据');
      expect(loader.engineFamily('C'), isNotNull);
    });

    test('同键去重在 registry 层完成，loader 收到即去重后的 faces', () async {
      // registry：同 family+字重+斜体 后声明覆盖先声明（P3-01）。
      final registry = CssFontFaceRegistry();
      registry.registerAll(_parse(
        '@font-face { font-family: D; src: url("$_regularPath"); font-weight: normal; }',
      ));
      registry.registerAll(_parse(
        '@font-face { font-family: D; src: url("$_boldPath"); font-weight: 400; }',
      ));
      expect(registry.faces, hasLength(1));

      final loader = BookFontLoader(bookId: 't7');
      var calls = 0;
      final result = await loader.load(
        registry.faces,
        resolveBytes: (url) async {
          calls += 1;
          return _fileBytes(url);
        },
      );
      expect(calls, 1);
      expect(loader.facesOf('D').keys, ['w400i0']);
      expect(result.engineFamilies['D'], 'bi_t7_D');
    });
  });

  group('字体加载失败降级（P3-06，§68.6）', () {
    test('字体不可用时页面仍可读：走回退链渲染出墨', () async {
      final loader = BookFontLoader(bookId: 'd1');
      final faces = _parse(
        '@font-face { font-family: Gone; src: url("missing.otf"); }',
      );
      final result = await loader.load(faces, resolveBytes: _fileBytes);
      expect(loader.engineFamily('Gone'), isNull);
      expect(
        result.warnings.any((w) => w.startsWith('E_FONT_LOAD_FAILED')),
        isTrue,
      );
      // 族不可用 → 消费方沿用原族名 → 引擎按回退链兜底，页面可读。
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Gone',
      });
      final painter = TextPainter()
        ..textDirection = TextDirection.ltr
        ..text = TextSpan(text: '坏字体回退后仍可读', style: _textStyleOf(style))
        ..layout();
      expect(painter.width, greaterThan(0));
    });

    test('提示只出现一次：同原因二次加载不重复告警，日志保留全量', () async {
      final loader = BookFontLoader(bookId: 'd2');
      final faces = _parse('''
@font-face { font-family: Bad; src: url("x.woff2") format("woff2"), url("missing.ttf"); }
''');
      final first = await loader.load(faces, resolveBytes: _fileBytes);
      final firstWarnings = first.warnings
          .where((w) => w.startsWith('E_'))
          .toList();
      expect(
        firstWarnings.any((w) => w.startsWith('E_FONT_UNSUPPORTED')),
        isTrue,
      );
      expect(
        firstWarnings.any((w) => w.startsWith('E_FONT_LOAD_FAILED')),
        isTrue,
      );

      final second = await loader.load(faces, resolveBytes: _fileBytes);
      expect(
        second.warnings.where((w) => w.startsWith('E_')),
        isEmpty,
        reason: '同一 (族,原因) 只提示一次',
      );
      expect(loader.degradationLog.length, firstWarnings.length * 2,
          reason: 'degradationLog 保留全量记录');
    });
  });
}

/// 与生产同路径的 TextStyle 构造（经别名映射与回退链）。
TextStyle _textStyleOf(ComputedStyle style) => TextLayoutEngine.textStyleFor(style);

Future<ByteData> _render(String fontFamily, int weight) async {
  final size = const Size(240, 160);
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': fontFamily,
    if (weight != 400) 'font-weight': '$weight',
  });
  final page = Paginator(pageHeight: size.height)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: TextLayoutEngine.layout(
              text: '粗体测试 ABC 123',
              style: style,
              maxWidth: 180,
            ),
            style: style,
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(canvas, page, pageSize: size);
  final image = await recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _diffBytes(ByteData a, ByteData b) {
  assert(a.lengthInBytes == b.lengthInBytes);
  var diff = 0;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) != b.getUint8(i)) {
      diff++;
    }
  }
  return diff;
}
