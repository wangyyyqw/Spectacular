import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/text/font_metrics.dart';

const _regularPath = '../../test_fonts/SourceHanSerifSC-Regular.otf';
const _boldPath = '../../test_fonts/SourceHanSerifSC-Bold.otf';

Future<Uint8List> _fileBytes(String path) => File(path).readAsBytes();

List<CssFontFace> _parse(String css) => CssParser.parse(css).fontFaces;

void main() {
  group('BookFontLoader 独立 face 与规范匹配', () {
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
      expect(engine, startsWith('bi_'));
      expect(
        loader.facesOf('songti').values.map((face) => face.weight).toSet(),
        {400, 700},
      );
      expect(FontMetricsRegistry.xHeightRatio(engine), closeTo(0.514, 0.0001));

      final regular = await _render(engine!, 400);
      final bold = await _render(engine, 700);
      expect(
        _diffBytes(regular, bold),
        greaterThan(0),
        reason: 'S5 口径：bold face 生效应产生像素差异',
      );
    });

    test('书间族名隔离：不同 bookId 同族名互不影响', () async {
      final a = BookFontLoader(bookId: 'a');
      final b = BookFontLoader(bookId: 'b');
      final faces = _parse(
        '@font-face { font-family: F; src: url("$_regularPath"); }',
      );
      await a.load(faces, resolveBytes: _fileBytes);
      await b.load(faces, resolveBytes: _fileBytes);
      expect(a.engineFamily('F'), isNotNull);
      expect(b.engineFamily('F'), isNotNull);
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

    test('未知 local-only face 告警且族不可用', () async {
      final loader = BookFontLoader(bookId: 't4');
      final faces = _parse(
        '@font-face { font-family: OnlyLocal; src: local("UnknownLocalFace"); }',
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
        result.warnings.any((w) => w.contains('格式不支持') && w.contains('woff2')),
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

    test('内容寻址稳定隔离同书标识下的不同字形', () async {
      final faces = _parse(
        '@font-face { font-family: Content; src: url("font.otf"); }',
      );
      Future<String> register(String path) async {
        final loader = BookFontLoader(bookId: 'same', contentAddressed: true);
        addTearDown(loader.clear);
        await loader.load(faces, resolveBytes: (_) => _fileBytes(path));
        return loader.engineFamily('Content')!;
      }

      final regular = await register(_regularPath);
      expect(await register(_regularPath), regular);
      expect(await register(_boldPath), isNot(regular));
    });

    test('内容寻址字体跨 loader 复用进程级引擎注册', () async {
      final faces = _parse(
        '@font-face { font-family: ReuseProcess; src: url("font.otf"); }',
      );
      final before = BookFontLoader.engineLoadCountForTest;
      final first = BookFontLoader(
        bookId: 'reuse-process',
        contentAddressed: true,
      );
      await first.load(faces, resolveBytes: (_) => _fileBytes(_regularPath));
      final engine = first.engineFamily('ReuseProcess');
      first.clear();

      final second = BookFontLoader(
        bookId: 'reuse-process',
        contentAddressed: true,
      );
      addTearDown(second.clear);
      await second.load(faces, resolveBytes: (_) => _fileBytes(_regularPath));
      expect(second.engineFamily('ReuseProcess'), engine);
      expect(
        BookFontLoader.engineLoadCountForTest - before,
        1,
        reason: '同字形族在进程内只向 Flutter 字体引擎注册一次',
      );
    });

    test('并发内容寻址加载只注册一次引擎字体', () async {
      final faces = _parse(
        '@font-face { font-family: ReuseConcurrent; src: url("font.otf"); }',
      );
      final before = BookFontLoader.engineLoadCountForTest;
      final first = BookFontLoader(
        bookId: 'reuse-concurrent',
        contentAddressed: true,
      );
      final second = BookFontLoader(
        bookId: 'reuse-concurrent',
        contentAddressed: true,
      );
      addTearDown(first.clear);
      addTearDown(second.clear);
      await Future.wait([
        first.load(faces, resolveBytes: (_) => _fileBytes(_regularPath)),
        second.load(faces, resolveBytes: (_) => _fileBytes(_regularPath)),
      ]);
      expect(first.engineFamily('ReuseConcurrent'), isNotNull);
      expect(
        BookFontLoader.engineLoadCountForTest - before,
        1,
        reason: '并发打开同一本书不能重复占用字体引擎内存',
      );
    });

    test('大字体分块摘要与完整SHA-256相同', () async {
      final bytes = await _fileBytes(_regularPath);
      expect(bytes.length, greaterThan(64 * 1024));
      final loader = BookFontLoader(bookId: 'chunked', contentAddressed: true);
      addTearDown(loader.clear);
      await loader.load(
        _parse('@font-face { font-family: Chunked; src: url("font.otf"); }'),
        resolveBytes: (_) async => bytes,
      );
      final face = _parse(
        '@font-face { font-family: Chunked; src: url("font.otf"); }',
      ).single;
      final signature = jsonEncode([
        'chunked',
        face.dedupKey,
        sha256.convert(bytes).toString(),
      ]);
      final digest = sha256.convert(utf8.encode(signature));
      expect(loader.registeredFace(face)!.selection.alias, 'bi_face_$digest');
    });

    test('大字体摘要期间可处理事件并在关闭后停止注册', () async {
      final bytes = await _fileBytes(_regularPath);
      final before = BookFontLoader.engineLoadCountForTest;
      final loader = BookFontLoader(
        bookId: 'hash_cancel',
        contentAddressed: true,
      );
      addTearDown(loader.clear);
      final result = await loader.load(
        _parse('@font-face { font-family: HashCancel; src: url("font.otf"); }'),
        resolveBytes: (_) async {
          Timer.run(loader.clear);
          return bytes;
        },
      );
      expect(result.engineFamilies, isEmpty);
      expect(loader.engineFamily('HashCancel'), isNull);
      expect(loader.facesOf('HashCancel'), isEmpty);
      expect(
        BookFontLoader.engineLoadCountForTest,
        before,
        reason: '事件循环中的关闭必须早于引擎注册',
      );
    });

    test('内容寻址增量与并发注册保留所有字重且不重复读取', () async {
      final loader = BookFontLoader(
        bookId: 'incremental',
        contentAddressed: true,
      );
      addTearDown(loader.clear);
      final regular = _parse(
        '@font-face { font-family: Incremental; src: url("$_regularPath"); }',
      );
      final bold = _parse(
        '@font-face { font-family: Incremental; src: url("$_boldPath"); '
        'font-weight: bold; }',
      );
      var reads = 0;
      Future<Uint8List?> resolve(String url) async {
        reads++;
        return _fileBytes(url);
      }

      await loader.load(regular, resolveBytes: resolve);
      final firstName = loader.engineFamily('Incremental')!;
      await Future.wait([
        loader.load(bold, resolveBytes: resolve),
        loader.load(regular, resolveBytes: resolve),
      ]);
      final combined = loader.engineFamily('Incremental')!;
      expect(combined, isNot(firstName));
      expect(
        loader.facesOf('Incremental').values.map((face) => face.weight).toSet(),
        {400, 700},
      );
      expect(reads, 2);
      final regularPixels = await _render(combined, 400);
      expect(
        _diffBytes(regularPixels, await _render(combined, 700)),
        greaterThan(0),
      );
      expect(
        _diffBytes(regularPixels, await _render(firstName, 400)),
        0,
        reason: '新增字重不能丢失已经加载的 regular face',
      );

      final concurrent = BookFontLoader(
        bookId: 'parallel',
        contentAddressed: true,
      );
      addTearDown(concurrent.clear);
      await Future.wait([
        concurrent.load(regular, resolveBytes: resolve),
        concurrent.load(bold, resolveBytes: resolve),
      ]);
      expect(
        concurrent
            .facesOf('Incremental')
            .values
            .map((face) => face.weight)
            .toSet(),
        {400, 700},
      );
    });

    test('clear取消在途注册，异步完成后不恢复字体字节缓存', () async {
      final loader = BookFontLoader(bookId: 'closed', contentAddressed: true);
      final bytes = Completer<Uint8List?>();
      final started = Completer<void>();
      final pending = loader.load(
        _parse('@font-face { font-family: Closed; src: url("font.otf"); }'),
        resolveBytes: (_) {
          started.complete();
          return bytes.future;
        },
      );
      await started.future;
      loader.clear();
      bytes.complete(await _fileBytes(_regularPath));
      expect((await pending).engineFamilies, isEmpty);
      expect(loader.engineFamily('Closed'), isNull);
      expect(loader.facesOf('Closed'), isEmpty);
    });

    test('同属性不同来源共存，重叠字符选最后声明的 face', () async {
      // 不同来源保留；相同属性的重叠字符按后声明优先选择。
      final registry = CssFontFaceRegistry();
      registry.registerAll(
        _parse(
          '@font-face { font-family: D; src: url("$_regularPath"); font-weight: normal; }',
        ),
      );
      registry.registerAll(
        _parse(
          '@font-face { font-family: D; src: url("$_boldPath"); font-weight: 400; }',
        ),
      );
      expect(registry.faces, hasLength(2));

      final loader = BookFontLoader(bookId: 't7');
      var calls = 0;
      final result = await loader.load(
        registry.faces,
        resolveBytes: (url) async {
          calls += 1;
          return _fileBytes(url);
        },
      );
      expect(calls, 2);
      expect(loader.facesOf('D'), hasLength(2));
      final family = result.engineFamilies['D']!;
      expect(
        ComputedStyle({'font-family': family}).fontFamily,
        loader.registeredFace(registry.faces.last)!.selection.nativeFamily,
      );
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
      expect(
        loader.degradationLog.length,
        firstWarnings.length * 2,
        reason: 'degradationLog 保留全量记录',
      );
    });
  });
}

/// 与生产同路径的 TextStyle 构造（经别名映射与回退链）。
TextStyle _textStyleOf(ComputedStyle style) =>
    TextLayoutEngine.textStyleFor(style);

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
