import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/script_fallback.dart';

/// 假字形表：'CJK' 覆盖中文，'Latin' 覆盖可打印 ASCII。
bool _fakeHasGlyph(String family, int codeUnit) {
  final isCjk = codeUnit >= 0x4E00 && codeUnit <= 0x9FFF;
  final isAscii = codeUnit >= 0x20 && codeUnit <= 0x7E;
  switch (family) {
    case 'CJK':
      return isCjk;
    case 'Latin':
      return isAscii;
    default:
      return false;
  }
}

void main() {
  test('中英混排切成 3 段，起止下标与族正确', () {
    final runs = buildScriptFontRuns('中文abc中文', const <String>[
      'CJK',
      'Latin',
    ], hasGlyph: _fakeHasGlyph);
    expect(runs, hasLength(3));
    expect(runs.map((r) => '${r.start}-${r.end}:${r.family}'), <String>[
      '0-2:CJK',
      '2-5:Latin',
      '5-7:CJK',
    ]);
  });

  test('纯 ASCII 只有一段', () {
    final runs = buildScriptFontRuns('abc', const <String>[
      'CJK',
      'Latin',
    ], hasGlyph: _fakeHasGlyph);
    expect(runs, hasLength(1));
    expect(runs.single.start, 0);
    expect(runs.single.end, 3);
    expect(runs.single.family, 'Latin');
  });

  test('无覆盖的字符被跳过，相邻段保持独立', () {
    // '\n'（0x0A）不在假字形表内，两侧中文不会被合并成一段。
    final runs = buildScriptFontRuns('中\n文', const <String>[
      'CJK',
      'Latin',
    ], hasGlyph: _fakeHasGlyph);
    expect(runs.map((r) => '${r.start}-${r.end}:${r.family}'), <String>[
      '0-1:CJK',
      '2-3:CJK',
    ]);
  });

  test('全部字符无覆盖时返回空列表', () {
    final runs = buildScriptFontRuns('\n\t', const <String>[
      'CJK',
      'Latin',
    ], hasGlyph: _fakeHasGlyph);
    expect(runs, isEmpty);
  });

  test('空文本或空 families 返回空列表', () {
    expect(
      buildScriptFontRuns('', const <String>[
        'CJK',
        'Latin',
      ], hasGlyph: _fakeHasGlyph),
      isEmpty,
    );
    expect(
      buildScriptFontRuns('abc', const <String>[], hasGlyph: _fakeHasGlyph),
      isEmpty,
    );
  });

  test('单族覆盖全部时只有一段', () {
    final runs = buildScriptFontRuns('中文abc', const <String>[
      'Any',
    ], hasGlyph: (String family, int codeUnit) => true);
    expect(runs, hasLength(1));
    expect(runs.single.start, 0);
    expect(runs.single.end, 5);
    expect(runs.single.family, 'Any');
  });

  test('顺序优先：第一个命中的族胜出', () {
    // 两个族都覆盖所有字符时，列表首项取胜。
    final firstWins = buildScriptFontRuns('abc中文', const <String>[
      'Latin',
      'CJK',
    ], hasGlyph: (String family, int codeUnit) => true);
    expect(firstWins, hasLength(1));
    expect(firstWins.single.family, 'Latin');

    // 前项无字形时后项胜出：a 归 Latin，中 归 CJK。
    final fallthrough = buildScriptFontRuns('a中', const <String>[
      'Latin',
      'CJK',
    ], hasGlyph: _fakeHasGlyph);
    expect(fallthrough.map((r) => '${r.start}-${r.end}:${r.family}'), <String>[
      '0-1:Latin',
      '1-2:CJK',
    ]);
  });
}
