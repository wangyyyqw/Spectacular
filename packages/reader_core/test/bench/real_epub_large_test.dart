import 'dart:io';

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

/// 大体积真实书（约 148MB / 1500+ 章），默认跳过；用环境变量显式开启：
/// `REAL_EPUB_LARGE=1 flutter test test/bench/real_epub_large_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['REAL_EPUB_LARGE'] == '1';
  final skip = enabled ? null : '默认跳过（设置 REAL_EPUB_LARGE=1 运行大书测试）';

  test(
    '诸神愚戏：整书分页耗时与确定性',
    () async {
      final corpus = findCorpusRoot();
      if (corpus == null) {
        // ignore: avoid_print
        print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
        return;
      }
      final file = File('${corpus.path}/real/zhushen-yuxi.epub');
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP 缺少 zhushen-yuxi.epub');
        return;
      }
      final bytes = file.readAsBytesSync();
      final openWatch = Stopwatch()..start();
      final opened = await openEpub(bytes);
      openWatch.stop();
      final document = opened.document!;
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.6',
        'font-family': 'serif',
        'text-align': 'justify',
      });
      final cache = TextLayoutCache();
      final pages = <SnapshotPage>[];
      final chapterMicros = <int>[];
      var chars = 0;
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
              buffer.write(
                slice.block.layout.text.substring(line.start, line.end),
              );
            }
          }
          pages.add(SnapshotPage(text: buffer.toString()));
        }
        watch.stop();
        chapterMicros.add(watch.elapsedMicroseconds);
        chars += chapterChars;
        if (chapterChars > maxChapterChars) {
          maxChapterChars = chapterChars;
          maxChapterMs = watch.elapsedMilliseconds;
        }
        if ((spine + 1) % 200 == 0) {
          // ignore: avoid_print
          print(
            'PROGRESS chapters=${spine + 1}/${document.spine.length} '
            'pages=${pages.length} elapsed_ms=${totalWatch.elapsedMilliseconds}',
          );
        }
      }
      totalWatch.stop();
      chapterMicros.sort();
      final median = chapterMicros[chapterMicros.length ~/ 2] / 1000;
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
      // ignore: avoid_print
      print(
        'BENCH large_book=zhushen-yuxi.epub size_mb='
        '${(bytes.length / (1 << 20)).toStringAsFixed(1)} '
        'open_ms=${openWatch.elapsedMilliseconds} '
        'chapters=${document.spine.length} pages=${pages.length} chars=$chars '
        'total_ms=${totalWatch.elapsedMilliseconds} '
        'chapter_median_ms=${median.toStringAsFixed(1)} '
        'max_chapter_chars=$maxChapterChars max_chapter_ms=$maxChapterMs '
        'rss_mb=${(ProcessInfo.currentRss / (1 << 20)).toStringAsFixed(0)} '
        'digest=$digest',
      );
      expect(pages, isNotEmpty);
      expect(chars, greaterThan(1000000));
      expect(maxChapterMs, lessThan(2000), reason: '单章首次分页应 <2s');
      expect(digest, hasLength(64));
      // 同一进程重复计算首页哈希应稳定（缓存不影响文本）。
      expect(
        PageSnapshot.hash(
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
        ),
        digest,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
