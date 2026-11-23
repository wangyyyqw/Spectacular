import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/text/font_metrics.dart';

/// 中文精简思源宋体保留汉字、真实字重和 OpenType 标点特性。
///
/// 真实 App 通过 pubspec `fonts:` 注册 `builtin_song`；这里显式用
/// FontLoader 加载同一份资产，并直接检查 cmap，避免系统回退掩盖缺字。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两种精简字重保留简繁、生僻字和常用符号', () async {
    for (final (name, weight) in [('Regular', 400), ('Bold', 700)]) {
      final data = await rootBundle.load('assets/fonts/MoyuSerif-$name.otf');
      expect(data.getUint32(0), 0x4F54544F, reason: '保留 OpenType/CFF 排版能力');
      expect(_table(data, 'maxp').getUint16(4), 42647);
      expect(_table(data, 'OS/2').getUint16(4), weight);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final coverage = FontCoverage.parse(bytes);
      expect(coverage, isNotNull);
      expect(coverage!.missingCodePoints('简繁體谮愚龘𠮷𠀋，。！？￥€①ΩЖあいうアイウ'), isEmpty);
      expect(coverage.covers('한'.runes.single), isFalse);
      expect(_variationSequenceCount(_table(data, 'cmap')), 25);
      expect(FontMetrics.parse(bytes)!.xHeightRatio, 0.514);
    }
  });

  setUpAll(() async {
    final loader = FontLoader('builtin_song_test')
      ..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/MoyuSerif-Bold.otf'));
    await loader.load();
  });

  test('精简宋体可渲染生僻字与常规、粗体', () {
    final painter = TextPainter(
      text: const TextSpan(
        text: '谮愚𠮷𠀋',
        style: TextStyle(fontFamily: 'builtin_song_test', fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);

    expect(painter.width, greaterThan(0));
    // 四个全角字：宽度约 4 × 20 = 80（不同字面略有差异）。
    expect(painter.width, closeTo(80, 8));

    final bold = TextPainter(
      text: const TextSpan(
        text: '粗体',
        style: TextStyle(
          fontFamily: 'builtin_song_test',
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(bold.dispose);
    expect(bold.width, closeTo(40, 4));
  });

  test('两种字重使用原生 halt 回收标点留白', () {
    for (final weight in [FontWeight.w400, FontWeight.w700]) {
      final style = TextStyle(
        fontFamily: 'builtin_song_test',
        fontSize: 20,
        fontWeight: weight,
      );
      final normal = TextPainter(
        text: TextSpan(text: '，。！？（）', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final half = TextPainter(
        text: TextSpan(
          text: '，。！？（）',
          style: style.copyWith(
            fontFeatures: const [FontFeature.enable('halt')],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(normal.dispose);
      addTearDown(half.dispose);
      expect(normal.width, closeTo(120, .01));
      expect(half.width, closeTo(60, .01));
    }
  });

  test('别名表把宋体/serif 映射到内置族', () {
    expect(FontFamilyAliases.resolve('宋体'), FontFamilyAliases.song);
    expect(FontFamilyAliases.resolve('serif'), FontFamilyAliases.song);
    expect(FontFamilyAliases.resolve('思源宋体'), FontFamilyAliases.song);
  });
}

ByteData _table(ByteData font, String name) {
  final tag = name.codeUnits.fold(0, (value, unit) => (value << 8) | unit);
  for (var index = 0; index < font.getUint16(4); index++) {
    final entry = 12 + index * 16;
    if (font.getUint32(entry) == tag) {
      final offset = font.getUint32(entry + 8);
      return ByteData.sublistView(
        font,
        offset,
        offset + font.getUint32(entry + 12),
      );
    }
  }
  throw StateError('字体缺少 $name 表');
}

int _variationSequenceCount(ByteData cmap) {
  for (var index = 0; index < cmap.getUint16(2); index++) {
    final offset = cmap.getUint32(8 + index * 8);
    if (cmap.getUint16(offset) != 14) continue;
    var count = 0;
    for (var item = 0; item < cmap.getUint32(offset + 6); item++) {
      final record = offset + 10 + item * 11;
      final defaults = cmap.getUint32(record + 3);
      final variants = cmap.getUint32(record + 7);
      if (defaults != 0) {
        final start = offset + defaults;
        for (var range = 0; range < cmap.getUint32(start); range++) {
          count += 1 + cmap.getUint8(start + 7 + range * 4);
        }
      }
      if (variants != 0) count += cmap.getUint32(offset + variants);
    }
    return count;
  }
  return 0;
}
