import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/text/font_punctuation_metrics.dart';
import 'package:reader_mobile/reader/bundled_font_punctuation.dart';

/// P9-05：内置阅微精简思源宋体可加载且覆盖正文常用字与部分生僻字。
///
/// 真实 App 通过 pubspec `fonts:` 注册 `builtin_song`；这里显式用
/// FontLoader 加载同一份资产，验证文件可解析、CJK 全角宽度正确、
/// 生僻字（谮/愚）有字形而不是豆腐块。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置宋体登记常规与粗体标点轮廓度量', () async {
    await registerBundledSongPunctuation();
    for (final weight in [400, 700]) {
      expect(
        FontPunctuationRegistry.lookup(
          FontFamilyAliases.song,
          '，'.codeUnitAt(0),
          weight: weight,
          italic: false,
        ),
        isNotNull,
      );
    }
  });

  test('内置精简思源宋体可加载并渲染生僻字', () async {
    final loader = FontLoader('builtin_song_test')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Bold.otf'));
    await loader.load();

    final painter = TextPainter(
      text: const TextSpan(
        text: '谮愚中粗',
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

  test('别名表把宋体/serif 映射到内置族', () {
    expect(FontFamilyAliases.resolve('宋体'), FontFamilyAliases.song);
    expect(FontFamilyAliases.resolve('serif'), FontFamilyAliases.song);
    expect(FontFamilyAliases.resolve('思源宋体'), FontFamilyAliases.song);
  });
}
