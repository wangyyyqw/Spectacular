import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/hyphenation.dart';

void main() {
  test('英文断词词表给出与 TeX 规则一致的音节边界', () {
    expect(EnUsHyphenator.breakOffsets('hyphenation'), <int>[2, 6]);
    expect(EnUsHyphenator.breakOffsets('demonstration'), <int>[5, 9]);
    expect(EnUsHyphenator.breakOffsets('extraordinarily'), <int>[
      2,
      5,
      7,
      9,
      12,
    ]);
    expect(EnUsHyphenator.breakOffsets('column'), <int>[3]);
  });

  test('短词、数字与含非拉丁字符的词不自动断词', () {
    expect(EnUsHyphenator.breakOffsets('with'), isEmpty);
    expect(EnUsHyphenator.breakOffsets('A1B2'), isEmpty);
    expect(EnUsHyphenator.breakOffsets('中文word'), isEmpty);
  });
}
