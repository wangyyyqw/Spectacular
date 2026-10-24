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

/// 真实样本子集（大文件如 155MB 书籍不进基准，避免测试内存与耗时失控）。
const _realBooks = <String>[
  'monk-and-robot.epub',
  'mj-003.epub',
  'ludingji-1.epub',
];

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.6',
  'font-family': 'serif',
  'text-align': 'justify',
});

class _BookResult {
  _BookResult(this.name);
  final String name;
  int chapters = 0;
  int pages = 0;
  int chars = 0;
  int elapsedMs = 0;
  int maxChapterChars = 0;
  int maxChapterMs = 0;
  int firstChapterMs = 0;
  int warmMs = 0;
  String? digest;
}

/// 分页整本书；返回页快照摘要（用于两次运行对比）。
Future<_BookResult> _paginateBook(
  String name,
  List<int> bytes,
  TextLayoutCache cache,
) async {
  final result = _BookResult(name);
  final stopwatch = Stopwatch()..start();
  final opened = await openEpub(Uint8List.fromList(bytes));
  final document = opened.document;
  if (document == null) {
    throw StateError('打开失败：${opened.report.message}');
  }
  final style = _style();
  final pages = <SnapshotPage>[];
  for (var spine = 0; spine < document.spine.length; spine++) {
    final chapterWatch = Stopwatch()..start();
    result.chapters += 1;
    var chapterChars = 0;
    final aggregated = document.aggregateText(spine);
    final blocks = <PageBlock>[];
    void collect(EpubNode node) {
      if (node is TextBlockNode) {
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        result.chars += text.length;
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
    result.pages += chapterPages.length;
    chapterWatch.stop();
    final chapterMs = chapterWatch.elapsedMilliseconds;
    if (spine == 0) {
      result.firstChapterMs = chapterMs;
    }
    if (chapterChars > result.maxChapterChars) {
      result.maxChapterChars = chapterChars;
      result.maxChapterMs = chapterMs;
    }
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
  }
  stopwatch.stop();
  result.elapsedMs = stopwatch.elapsedMilliseconds;
  result.digest = PageSnapshot.hash(
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
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 EPUB 分页与缓存复用（本地样本库）', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      // ignore: avoid_print
      print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
      return;
    }
    final realDir = Directory('${corpus.path}/real');
    for (final name in _realBooks) {
      final file = File('${realDir.path}/$name');
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP 缺少真实样本 $name');
        continue;
      }
      final bytes = file.readAsBytesSync();
      final coldCache = TextLayoutCache();
      final warmCache = TextLayoutCache();
      // 预热 warmCache：先用同一份数据跑一遍，再测“缓存已热”的耗时。
      await _paginateBook(name, bytes, warmCache);
      final cold = await _paginateBook(name, bytes, coldCache);
      final warm = await _paginateBook(name, bytes, warmCache);

      // ignore: avoid_print
      print(
        'BENCH real book=$name size_mb=${(bytes.length / (1 << 20)).toStringAsFixed(1)} '
        'chapters=${cold.chapters} pages=${cold.pages} chars=${cold.chars} '
        'cold_ms=${cold.elapsedMs} warm_ms=${warm.elapsedMs} '
        'first_chapter_ms=${cold.firstChapterMs} '
        'largest_chapter_chars=${cold.maxChapterChars} '
        'largest_chapter_ms=${cold.maxChapterMs} '
        'same_digest=${cold.digest == warm.digest}',
      );

      expect(cold.chapters, greaterThan(0));
      expect(cold.pages, greaterThan(0));
      expect(cold.chars, greaterThan(0));
      expect(warm.digest, cold.digest, reason: '两次分页页序列哈希应一致');
      expect(warmCache.hits, greaterThan(0), reason: '第二次运行应命中段落缓存');
      expect(
        cold.firstChapterMs,
        lessThan(2000),
        reason: '首章首次分页应 <2s，实际 ${cold.firstChapterMs} ms',
      );
      expect(
        cold.maxChapterMs,
        lessThan(2000),
        reason:
            '最大章（${cold.maxChapterChars} 字）首次分页应 <2s，'
            '实际 ${cold.maxChapterMs} ms',
      );
    }
  });
}
