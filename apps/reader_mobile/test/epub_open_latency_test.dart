import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 向上查找本地样本库（不入库）。
Directory? _findCorpus() {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}

void main() {
  test('真实 EPUB：打开 + 首章分页耗时（本地样本库，CI 跳过）', () async {
    final corpus = _findCorpus();
    if (corpus == null) {
      // ignore: avoid_print
      print('SKIP 本地真实样本缺失（test_corpus/ 不入库）');
      return;
    }
    const names = <String>[
      'monk-and-robot.epub',
      'mj-003.epub',
      'ludingji-1.epub',
    ];
    for (final name in names) {
      final file = File('${corpus.path}/real/$name');
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP 缺少 $name');
        continue;
      }
      final bytes = file.readAsBytesSync();
      final watch = Stopwatch()..start();
      final source = await EpubChapterSource.open(bytes);
      final openMs = watch.elapsedMilliseconds;
      final pages = await source.loadChapter(0);
      watch.stop();
      // ignore: avoid_print
      print(
        'BENCH book=$name epub_open_ms=$openMs first_chapter_ms='
        '${watch.elapsedMilliseconds - openMs} pages=${pages.length} '
        'chapters=${source.chapterCount}',
      );
      expect(pages, isNotEmpty);
      expect(source.chapterCount, greaterThan(0));
      expect(pages.first.slices, isNotEmpty);
      // 调试模式阈值放宽；目标设备上首章分页为 10ms 级（见 P2-26 真实书数据）。
      expect(watch.elapsedMilliseconds, lessThan(3000));
    }
  });
}
