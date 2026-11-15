import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  test('文件分析流式哈希并返回同一摘要', () async {
    final directory = await Directory.systemTemp.createTemp('import-file-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final bytes = buildTestEpub(
      title: '文件摘要书',
      identifier: 'urn:uuid:file-analysis',
      cover: true,
    );
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(bytes);
    String? checkedRevision;

    final analysis = await analyzeImportFileUnlessKnown(
      file.path,
      shouldSkip: (revision) async {
        checkedRevision = revision;
        return false;
      },
    );

    expect(analysis, isNotNull);
    expect(checkedRevision, analysis!.revision);
    expect(analysis.summary?.meta.title, '文件摘要书');
    expect(analysis.summary?.coverBytes, isNotEmpty);
    expect(analysis.report.ok, isTrue);
  });

  test('后台旧版快照返回与迁移字节一致的哈希', () async {
    final directory = await Directory.systemTemp.createTemp(
      'revision-snapshot-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = Uint8List.fromList(
      List.generate(
        importAnalysisIsolateThreshold + 17,
        (index) => index % 251,
      ),
    );
    final file = File('${directory.path}/old.epub');
    await file.writeAsBytes(bytes);

    final snapshot = await readRevisionFileSnapshot(file.path);

    expect(snapshot.bytes, orderedEquals(bytes));
    expect(snapshot.revision, sha256.convert(snapshot.bytes).toString());
  });
}
