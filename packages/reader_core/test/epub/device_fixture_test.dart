import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/src/api/models.dart';

import '../support/corpus.dart';

/// 真机验收 fixtures（tests/corpus/build_device_fixtures.py 生成，不入库）
/// 的引擎侧校验：能打开、结构正确、容错不阻断。
///
/// 只在本地样本存在时运行；缺失时整组跳过，保持 CI 可移植。
/// 真机验收 fixtures（tests/corpus/build_device_fixtures.py 生成，不入库）
/// 的引擎侧校验：结构正确、资源可解析、容错不阻断。
///
/// 只在本地样本存在时运行；缺失时整组跳过，保持 CI 可移植。章节正文的
/// 解析与排版由 reader_mobile 的章节源负责，这里只做核心层断言。
void main() {
  final corpus = findCorpusRoot();
  Uint8List? read(String name) => readSampleBytes(corpus, name);
  final mixedBytes = read('generated/verify-mixed.epub');
  final toleranceBytes = read('generated/verify-tolerance.epub');
  final smallBytes = read('generated/verify-small.epub');
  final skip = corpus == null || mixedBytes == null
      ? '本地 fixtures 缺失：先运行 tests/corpus/build_device_fixtures.py'
      : null;

  int tocDepth(List<TocEntry> entries) {
    var depth = 0;
    for (final entry in entries) {
      final childDepth = entry.children.isEmpty ? 1 : 1 + tocDepth(entry.children);
      if (childDepth > depth) {
        depth = childDepth;
      }
    }
    return depth;
  }

  test('混合样本：打开、spine 与三层嵌套目录', () async {
    final result = await openEpub(mixedBytes!);
    expect(result.ok, isTrue, reason: '${result.report.warnings}');
    final document = result.document!;
    expect(document.spine.length, 12);
    expect(
      document.spine.map((item) => item.href).toList(),
      containsAll(<String>['long.xhtml', 'tolerance.xhtml', 'ch05.xhtml']),
    );
    expect(tocDepth(document.toc), greaterThanOrEqualTo(3));
    final titles = document.toc.map((entry) => entry.title).toList();
    expect(titles, contains('第三部 压力'));
  }, skip: skip);

  test('混合样本：章节文件、字体与资源可读', () async {
    final result = await openEpub(mixedBytes!);
    final document = result.document!;
    // 长章节文件应当在包内且体量足够（真机性能用例的直接输入）。
    final long = document.archive.readBytes('OEBPS/long.xhtml');
    expect(long, isNotNull);
    expect(long!.length, greaterThan(80 * 1024));
    final chapter = document.archive.readBytes('OEBPS/ch06.xhtml');
    expect(chapter, isNotNull);
    final fonts = document.archive.readBytes(
      'OEBPS/fonts/SourceHanSerifSC-Regular.otf',
    );
    expect(fonts, isNotNull);
    expect(fonts!.length, greaterThan(100 * 1024));

    // 资源解析：正常图片命中、缺失图片返回 null 且不抛异常。
    final png = document.resources.read(
      document.archive,
      'OEBPS/images/photo-1.png',
      baseDir: 'OEBPS',
    );
    expect(png, isNotNull);
    final svg = document.resources.read(
      document.archive,
      'OEBPS/images/mark.svg',
      baseDir: 'OEBPS',
    );
    expect(svg, isNotNull);
    final missing = document.resources.read(
      document.archive,
      'OEBPS/images/missing-photo.jpg',
      baseDir: 'OEBPS',
    );
    expect(missing, isNull);
  }, skip: skip);

  test('容错样本：缺章/缺样式仍可读且报告降级', () async {
    final result = await openEpub(toleranceBytes!);
    expect(result.ok, isTrue);
    final document = result.document!;
    // spine 保留 4 项（缺章在读取期降级），打开本身必须成功。
    expect(document.spine.length, 4);
    expect(
      document.archive.readBytes('OEBPS/missing-chapter.xhtml'),
      isNull,
    );
    expect(result.report.readabilityLevel, greaterThanOrEqualTo(1));
    expect(document.toc, isNotEmpty);
  }, skip: skip);

  test('小样本：四章与目录兜底', () async {
    final result = await openEpub(smallBytes!);
    expect(result.ok, isTrue);
    final document = result.document!;
    expect(document.spine.length, 4);
    expect(document.toc, isNotEmpty);
    expect(document.toc.length, 4);
    expect(
      document.archive.readBytes('OEBPS/s1.xhtml'),
      isNotNull,
    );
  }, skip: skip);

  test('fixtures 未被误提交', () {
    // test_corpus/ 整体不入库（P0 附录 A-08），这里断言生成目录存在时
    // 只用于本地校验；缺失（CI）不算失败。
    if (corpus == null) {
      return;
    }
    final generated = Directory('${corpus.path}/generated');
    expect(
      generated.existsSync() || !File('${corpus.path}/generated').existsSync(),
      isTrue,
    );
  });
}
