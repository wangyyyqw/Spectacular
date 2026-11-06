import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/import_analysis.dart';

void main() {
  test('阈值内使用当前线程分析，结果包含哈希和 CRC 报告', () async {
    final bytes = Uint8List(importAnalysisIsolateThreshold - 1);
    final analysis = await analyzeImport(bytes);

    expect(analysis.revision, hasLength(64));
    expect(analysis.checked.ok, isFalse);
    expect(analysis.charCounts, isNull);
  });

  test('达到阈值后后台分析可传回报告', () async {
    final bytes = Uint8List(importAnalysisIsolateThreshold);
    final analysis = await analyzeImport(bytes);

    expect(analysis.revision, hasLength(64));
    expect(analysis.checked.ok, isFalse);
    expect(analysis.charCounts, isNull);
  });
}
