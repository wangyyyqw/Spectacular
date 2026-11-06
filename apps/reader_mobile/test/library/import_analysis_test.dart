import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/import_analysis.dart';

import '../support/test_epub.dart';

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

  test('已知摘要时阈值内文件不再解析 ZIP', () async {
    final bytes = Uint8List(importAnalysisIsolateThreshold - 1);
    String? checkedRevision;
    final analysis = await analyzeImportUnlessKnown(
      bytes,
      shouldSkip: (revision) async {
        checkedRevision = revision;
        return true;
      },
    );

    expect(analysis, isNull);
    expect(checkedRevision, hasLength(64));
  });

  test('大文件可通过单次后台握手跳过后续解析', () async {
    final bytes = Uint8List(importAnalysisIsolateThreshold);
    String? checkedRevision;
    final analysis = await analyzeImportUnlessKnown(
      bytes,
      shouldSkip: (revision) async {
        checkedRevision = revision;
        return true;
      },
    );

    expect(analysis, isNull);
    expect(checkedRevision, hasLength(64));
  });

  test('大文件摘要未命中时同一后台 isolate 继续分析', () async {
    final bytes = Uint8List(importAnalysisIsolateThreshold);
    String? checkedRevision;
    final analysis = await analyzeImportUnlessKnown(
      bytes,
      shouldSkip: (revision) async {
        checkedRevision = revision;
        return false;
      },
    );

    expect(analysis, isNotNull);
    expect(checkedRevision, analysis!.revision);
    expect(analysis.checked.ok, isFalse);
  });

  test('成功分析携带新书写库所需的轻量摘要', () async {
    final analysis = await analyzeImport(
      buildTestEpub(
        title: '摘要测试书',
        author: '测试作者',
        identifier: 'urn:uuid:summary-book',
        cover: true,
      ),
    );

    final summary = analysis.summary;
    expect(summary, isNotNull);
    expect(summary!.meta.title, '摘要测试书');
    expect(summary.meta.author, '测试作者');
    expect(summary.identifier, 'urn:uuid:summary-book');
    expect(summary.spine, hasLength(1));
    expect(summary.excludedSpineIndexes, isEmpty);
    expect(analysis.charCounts, isNotEmpty);
    expect(summary.coverBytes, isNotEmpty);
    expect(summary.coverExtension, 'jpg');
    expect(analysis.report.ok, isTrue);
  });
}
