import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/page_snapshot.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/src/api/models.dart' show EpubNode, TextBlockNode;

import '../support/corpus.dart';

const _pageWidth = 360.0;
const _pageHeight = 640.0;

/// 真书测试统一使用《诸神愚戏》（148.5MB / 1541 章）。
const _bookName = 'zhushen-yuxi.epub';

/// 默认跳过（避免拖慢本地/CI 常规测试）；显式开启：
/// `REAL_EPUB=1 flutter test test/bench/real_epub_test.dart`
/// 需要两次运行对比确定性时再加 `REAL_EPUB_TWICE=1`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['REAL_EPUB'] == '1';
  final skip = enabled ? null : '默认跳过（设置 REAL_EPUB=1 运行真书测试）';

  test(
    '诸神愚戏：真书打开、整书分页、单章预算与确定性',
    () async {
      final corpus = findCorpusRoot();
      if (corpus == null) {
        // ignore: avoid_print
        print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
        return;
      }
      final file = File('${corpus.path}/real/$_bookName');
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP 缺少真书 $_bookName');
        return;
      }
      final bytes = file.readAsBytesSync();
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.6',
        'font-family': 'serif',
        'text-align': 'justify',
      });

      final first = await _measure(bytes, style);
      var sameDigest = true;
      if (Platform.environment['REAL_EPUB_TWICE'] == '1') {
        final second = await _measure(bytes, style);
        sameDigest = first.digest == second.digest;
      }

      // ignore: avoid_print
      print(
        'BENCH real_book=$_bookName size_mb='
        '${(bytes.length / (1 << 20)).toStringAsFixed(1)} '
        'open_ms=${first.openMs} chapters=${first.chapters} '
        'pages=${first.pages} chars=${first.chars} '
        'total_ms=${first.totalMs} chapter_median_ms=${first.medianMs} '
        'first_chapter_ms=${first.firstChapterMs} '
        'max_chapter_chars=${first.maxChapterChars} '
        'max_chapter_ms=${first.maxChapterMs} '
        'rss_mb=${(ProcessInfo.currentRss / (1 << 20)).toStringAsFixed(0)} '
        'digest=${first.digest} same_digest=$sameDigest',
      );

      expect(first.chapters, greaterThan(100));
      expect(first.pages, greaterThan(1000));
      expect(first.chars, greaterThan(1000000));
      expect(first.firstChapterMs, lessThan(2000), reason: '首章首次分页应 <2s');
      expect(first.maxChapterMs, lessThan(2000), reason: '最大章首次分页应 <2s');
      expect(first.digest, hasLength(64));
      expect(sameDigest, isTrue);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class _BookMeasurement {
  _BookMeasurement({
    required this.openMs,
    required this.chapters,
    required this.pages,
    required this.chars,
    required this.totalMs,
    required this.medianMs,
    required this.firstChapterMs,
    required this.maxChapterChars,
    required this.maxChapterMs,
    required this.digest,
  });

  final int openMs;
  final int chapters;
  final int pages;
  final int chars;
  final int totalMs;
  final double medianMs;
  final int firstChapterMs;
  final int maxChapterChars;
  final int maxChapterMs;
  final String digest;
}

Future<_BookMeasurement> _measure(Uint8List bytes, ComputedStyle style) async {
  final openWatch = Stopwatch()..start();
  final opened = await openEpub(bytes);
  openWatch.stop();
  final document = opened.document;
  if (document == null) {
    throw StateError('打开失败：${opened.report.message}');
  }
  final cache = TextLayoutCache();
  final pages = <SnapshotPage>[];
  final chapterMicros = <int>[];
  var chars = 0;
  var firstChapterMs = 0;
  var maxChapterChars = 0;
  var maxChapterMs = 0;
  final totalWatch = Stopwatch()..start();
  for (var spine = 0; spine < document.spine.length; spine++) {
    final watch = Stopwatch()..start();
    var chapterChars = 0;
    final aggregated = document.aggregateText(spine);
    final blocks = <PageBlock>[];
    void collect(EpubNode node) {
      if (node is TextBlockNode) {
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        chapterChars += text.length;
        final layout = cache.layout(
          text: text,
          style: style,
          maxWidth: _pageWidth,
        );
        if (layout.lineCount > 0) {
          blocks.add(
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: _pageWidth,
            ),
          );
        }
      } else if (node is BlockNode) {
        for (final child in node.children) {
          collect(child);
        }
      } else if (node is InlineNode) {
        for (final child in node.children) {
          collect(child);
        }
      }
    }

    collect(aggregated.root);
    final chapterPages = Paginator(pageHeight: _pageHeight)
        .measureChapter(blocks: blocks, spineIndex: spine)
        .pages;
    for (final page in chapterPages) {
      final buffer = StringBuffer();
      for (final slice in page.slices) {
        for (var i = slice.startLine; i < slice.endLine; i++) {
          final line = slice.block.layout.lines[i];
          buffer.write(slice.block.layout.text.substring(line.start, line.end));
        }
      }
      pages.add(SnapshotPage(text: buffer.toString()));
    }
    watch.stop();
    chapterMicros.add(watch.elapsedMicroseconds);
    chars += chapterChars;
    if (spine == 0) {
      firstChapterMs = watch.elapsedMilliseconds;
    }
    if (chapterChars > maxChapterChars) {
      maxChapterChars = chapterChars;
      maxChapterMs = watch.elapsedMilliseconds;
    }
    if ((spine + 1) % 500 == 0) {
      // ignore: avoid_print
      print(
        'PROGRESS chapters=${spine + 1}/${document.spine.length} '
        'pages=${pages.length} elapsed_ms=${totalWatch.elapsedMilliseconds}',
      );
    }
  }
  totalWatch.stop();
  chapterMicros.sort();
  final medianMs = chapterMicros[chapterMicros.length ~/ 2] / 1000;
  final digest = PageSnapshot.hash(
    pages,
    const SnapshotConfig(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      devicePixelRatio: 1,
      fontFamily: 'serif',
      fontSize: 16,
      lineHeight: 1.6,
      language: 'zh-CN',
    ),
  );
  return _BookMeasurement(
    openMs: openWatch.elapsedMilliseconds,
    chapters: document.spine.length,
    pages: pages.length,
    chars: chars,
    totalMs: totalWatch.elapsedMilliseconds,
    medianMs: medianMs,
    firstChapterMs: firstChapterMs,
    maxChapterChars: maxChapterChars,
    maxChapterMs: maxChapterMs,
    digest: digest,
  );
}
