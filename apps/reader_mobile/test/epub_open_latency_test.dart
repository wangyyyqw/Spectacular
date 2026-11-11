import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

/// 真书测试统一使用《诸神愚戏》（148.5MB / 1541 章），本地样本库不入库。
const _bookName = 'zhushen-yuxi.epub';

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
  test('诸神愚戏：打开书 + 首章分页耗时（本地样本库，CI 跳过）', () async {
    final corpus = _findCorpus();
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
    final watch = Stopwatch()..start();
    final source = await EpubChapterSource.open(bytes);
    final openMs = watch.elapsedMilliseconds;
    final pages = await source.loadChapter(0);
    final chapterMs = watch.elapsedMilliseconds - openMs;
    watch.stop();
    // ignore: avoid_print
    print(
      'BENCH book=$_bookName size_mb=${(bytes.length / (1 << 20)).toStringAsFixed(1)} '
      'epub_open_ms=$openMs first_chapter_ms=$chapterMs '
      'pages=${pages.length} chapters=${source.chapterCount}',
    );
    expect(pages, isNotEmpty);
    expect(pages.first.slices, isNotEmpty);
    expect(source.chapterCount, greaterThan(100));
    // 调试模式阈值放宽；目标设备首章分页为 10ms 级（见 P2-26 真书数据）。
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });
}
