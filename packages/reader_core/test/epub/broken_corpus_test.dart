import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../support/broken_samples.dart';

/// P3-28 容错回归：10 本破损样本逐一打开，断言分级符合 §55.4 预期。
void main() {
  test('10 本破损样本分级回归', () async {
    final results = <String, String>{};
    for (final entry in brokenSamples.entries) {
      final result = await openEpub(entry.value);
      final expected = brokenExpectations[entry.key]!;
      final actual = result.report.readabilityLevel;
      results[entry.key] = actual == 4
          ? 'L4(${result.report.errorCode})'
          : 'L$actual';
      expect(
        expected.contains(actual),
        isTrue,
        reason: '${entry.key} 期望 L$expected 实际 L$actual'
            '（warnings=${result.report.warnings}）',
      );
      if (actual != 4) {
        expect(result.ok, isTrue, reason: entry.key);
      }
    }
    // 回归清单打印（供 M2-容错回归.md 归档）。
    // ignore: avoid_print
    print(
      'BROKEN_REGRESSION '
      '${results.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
  });

  test('样本名与期望表一致（防漏配）', () {
    expect(brokenSamples.keys.toSet(), brokenExpectations.keys.toSet());
    expect(brokenSamples.length, 10);
  });
}
