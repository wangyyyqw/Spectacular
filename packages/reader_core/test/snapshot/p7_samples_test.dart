import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, ByteData;
import 'package:flutter_test/flutter_test.dart';

import '../support/corpus.dart';
import 'p7_samples.dart';
import 'snapshot_harness.dart';

/// P7-31：生成样本的行为断言——每本至少分出一页；脚注样本的上标行
/// 与相邻行行高一致（P7-09 借行距的样本级验证）。
const _spec = SnapshotSpec(
  pageWidth: 320,
  pageHeight: 600,
  devicePixelRatio: 2,
  fontSize: 16,
  lineHeight: 1.5,
  margin: 12,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    await (FontLoader(_spec.fontFamily)
          ..addFont(
            Future<ByteData>.value(
              ByteData.sublistView(file.readAsBytesSync()),
            ),
          ))
        .load();
  });

  test('五类生成样本全部可分页（页数 > 0）', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      // ignore: avoid_print
      print('SKIP 字体依赖本地目录（仅校验样本可构建）');
      expect(buildP7SampleEpubs(), hasLength(5));
      return;
    }
    for (final entry in buildP7SampleEpubs().entries) {
      final pages = await paginateSnapshot(entry.value, _spec);
      expect(pages, isNotEmpty, reason: '${entry.key} 应至少分出一页');
    }
  });

  test('脚注样本：上标不撑高行盒（相邻行行高一致，P7-09 样本级）', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      // ignore: avoid_print
      print('SKIP 字体依赖本地目录');
      return;
    }
    final pages = await paginateSnapshot(
      buildP7SampleEpubs()['gen:sup-footnote']!,
      _spec,
    );
    final heights = <double>[];
    for (final page in pages) {
      for (final slice in page.slices) {
        for (var i = slice.startLine; i < slice.endLine; i++) {
          heights.add(slice.block.layout.lines[i].height);
        }
      }
    }
    expect(heights.length, greaterThan(4));
    // 无行内大字号：全部行同高（借行距生效的上标不产生行高跳变）。
    final distinct = heights.map((h) => h.roundToDouble()).toSet();
    expect(distinct, hasLength(1), reason: '行高集合应只有一档：$heights');
  });
}
