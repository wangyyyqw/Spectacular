import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../support/corpus.dart';
import 'p7_samples.dart';
import 'snapshot_harness.dart';

/// P2-33 样式回归：5 本样本整书渲染，与提交入库的基线逐页对照。
const _spec = SnapshotSpec(
  pageWidth: 320,
  pageHeight: 600,
  devicePixelRatio: 2,
  fontSize: 16,
  lineHeight: 1.5,
  margin: 12,
);

const _samples = <String>[
  'basic.epub',
  'styles.epub',
  'table.epub',
  'toc-ncx.epub',
  'cjk-vertical.epub',
];

const _baselinePath = 'test/snapshot/baseline/style_regression.json';
const _reportPath = '../../方案/验收记录/M1-样式回归.md';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _spec.fontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

class _BookDiff {
  _BookDiff({
    required this.file,
    required this.pages,
    required this.baselinePages,
    required this.bookHash,
    required this.baselineHash,
  });

  final String file;
  final int pages;
  final int? baselinePages;
  final String bookHash;
  final String? baselineHash;
  final List<String> pageDiffs = <String>[];

  bool get hasBaseline => baselineHash != null;
  bool get matches => hasBaseline && bookHash == baselineHash;

  String get status {
    if (!hasBaseline) {
      return '新增基线';
    }
    return matches ? '一致' : '差异';
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('5 本样本整书页序列与基线一致', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      // ignore: avoid_print
      print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
      return;
    }
    await _loadFont();

    final baselineFile = File(_baselinePath);
    final baseline = baselineFile.existsSync()
        ? jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    final baselineBooks =
        (baseline['books'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final diffs = <_BookDiff>[];
    final snapshots = <String, Map<String, Object?>>{};
    Future<void> snapshotOne(String name, Uint8List bytes) async {
      final snapshot = await snapshotBook(bytes, _spec);
      snapshots[name] = <String, Object?>{
        'spec': snapshot.spec,
        'specId': snapshot.specId,
        'bookHash': snapshot.bookHash,
        'pages': snapshot.pages.map((p) => p.toJson()).toList(growable: false),
      };

      final base = baselineBooks[name] as Map<String, dynamic>?;
      final diff = _BookDiff(
        file: name,
        pages: snapshot.pages.length,
        baselinePages: (base?['pages'] as List?)?.length,
        bookHash: snapshot.bookHash,
        baselineHash: base?['bookHash'] as String?,
      );
      if (base != null) {
        final basePages = (base['pages'] as List).cast<Map<String, dynamic>>();
        final count = snapshot.pages.length < basePages.length
            ? snapshot.pages.length
            : basePages.length;
        for (var i = 0; i < count; i++) {
          final page = snapshot.pages[i];
          final basePage = basePages[i];
          if (page.layoutHash != basePage['layoutHash']) {
            diff.pageDiffs.add(
              '第 $i 页：`${page.summary}`；'
              '像素差 ${page.inkPixels - (basePage['inkPixels'] as int)}',
            );
          }
        }
        if (snapshot.pages.length != basePages.length) {
          diff.pageDiffs.add(
            '页数变化：当前 ${snapshot.pages.length} / 基线 ${basePages.length}',
          );
        }
      }
      diffs.add(diff);
    }

    for (final file in _samples) {
      final sample = File('${corpus.path}/$file');
      if (!sample.existsSync()) {
        // ignore: avoid_print
        print('SKIP 缺少样本 $file');
        continue;
      }
      await snapshotOne(file, sample.readAsBytesSync());
    }
    // P7-31 生成样本（合成内容，无本地依赖，永远参与回归）。
    final generated = buildP7SampleEpubs();
    for (final entry in generated.entries) {
      await snapshotOne(entry.key, entry.value);
    }

    // 更新基线：STYLE_REGRESSION_UPDATE=1。
    if (Platform.environment['STYLE_REGRESSION_UPDATE'] == '1') {
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'spec': _spec.toJson(),
          'specId': _spec.id,
          'books': snapshots,
        }),
      );
      // ignore: avoid_print
      print('已写入样式回归基线 ${baselineFile.path}');
    }

    // 生成验收文档：STYLE_REGRESSION_REPORT=1。
    if (Platform.environment['STYLE_REGRESSION_REPORT'] == '1') {
      File(_reportPath).writeAsStringSync(_renderReport(diffs));
      // ignore: avoid_print
      print('已生成样式回归报告 $_reportPath');
    }

    final failures = diffs.where((d) => d.hasBaseline && !d.matches).toList();
    if (failures.isNotEmpty) {
      final details = failures
          .map(
            (d) =>
                '${d.file}: 首个差异 '
                '${d.pageDiffs.isEmpty ? '（无逐页差异，检查配置指纹）' : d.pageDiffs.first}',
          )
          .join('\n');
      fail('样式回归失败：\n$details');
    }
    for (final diff in diffs) {
      expect(diff.pages, greaterThan(0), reason: '${diff.file} 应至少分出一页');
    }
  });
}

String _renderReport(List<_BookDiff> diffs) {
  final buffer = StringBuffer()
    ..writeln('# M1 样式回归（P2-33）')
    ..writeln()
    ..writeln(
      '> 生成命令：`STYLE_REGRESSION_REPORT=1 flutter test '
      'test/snapshot/style_regression_test.dart`',
    )
    ..writeln('> 基线：`test/snapshot/baseline/style_regression.json`')
    ..writeln()
    ..writeln(
      '固定配置：${_spec.pageWidth.toInt()}×'
      '${_spec.pageHeight.toInt()} 逻辑像素、DPR '
      '${_spec.devicePixelRatio.toInt()}、'
      '`${_spec.fontFamily}` ${_spec.fontSize.toInt()}px / 行高 '
      '${_spec.lineHeight} / 页边距 ${_spec.margin.toInt()}。',
    )
    ..writeln()
    ..writeln('| 样本 | 页数 | 页序列哈希（前 12） | 状态 |')
    ..writeln('|---|---:|---|---|');
  for (final diff in diffs) {
    buffer.writeln(
      '| ${diff.file} | ${diff.pages} | '
      '`${diff.bookHash.substring(0, 12)}…` | ${diff.status} |',
    );
  }
  final failing = diffs.where((d) => d.hasBaseline && !d.matches).toList();
  buffer
    ..writeln()
    ..writeln('## 差异与归因')
    ..writeln();
  if (failing.isEmpty) {
    buffer.writeln(
      '- **无未解释差异**：5 本样本页序列与基线一致；本次运行为首版基线'
      '（或基线由有意变更后更新），归因为「初始基线/预期变更」。',
    );
  } else {
    for (final diff in failing) {
      buffer.writeln('### ${diff.file}（${diff.status}）');
      buffer.writeln();
      for (final pageDiff in diff.pageDiffs) {
        buffer.writeln('- $pageDiff');
      }
      buffer.writeln('- 归因：待确认（预期变更或缺陷）');
      buffer.writeln();
    }
  }
  buffer
    ..writeln()
    ..writeln('## 失败用例清单')
    ..writeln();
  if (failing.isEmpty) {
    buffer.writeln('- 无');
  } else {
    for (final diff in failing) {
      buffer.writeln('- ${diff.file}：${diff.pageDiffs.length} 处差异');
    }
  }
  buffer
    ..writeln()
    ..writeln('## 复现')
    ..writeln()
    ..writeln('```bash')
    ..writeln('cd packages/reader_core')
    ..writeln(
      'STYLE_REGRESSION_REPORT=1 flutter test '
      'test/snapshot/style_regression_test.dart   # 对照并生成报告',
    )
    ..writeln(
      'STYLE_REGRESSION_UPDATE=1 flutter test '
      'test/snapshot/style_regression_test.dart   # 有意变更后更新基线',
    )
    ..writeln('```');
  return buffer.toString();
}
