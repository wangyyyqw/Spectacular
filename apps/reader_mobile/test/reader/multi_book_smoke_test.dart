import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// P8-04 真书多书冒烟：test_corpus/real 全部真书打开 + 前 3 章分页非空。
/// 防引擎改动退化为单书适配（诸神愚戏专属回归的补充）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('七本真书打开与前章分页冒烟', () async {
    final dir = Directory('../../test_corpus/real');
    if (!dir.existsSync()) {
      // ignore: avoid_print
      print('SKIP 本地真书库缺失（test_corpus/real/ 不入库）');
      return;
    }
    final books = <File>[
      for (final entry in dir.listSync())
        if (entry is File && entry.path.endsWith('.epub')) entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
    expect(books.length, greaterThanOrEqualTo(5),
        reason: '真书库应有至少 5 本（当前 ${books.length}）');
    final failures = <String>[];
    for (final book in books) {
      final name = book.uri.pathSegments.last;
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(await book.readAsBytes());
      } catch (error) {
        failures.add('$name 读取失败 $error');
        continue;
      }
      try {
        final source = await EpubChapterSource.open(bytes);
        expect(source.chapterCount, greaterThan(0), reason: '$name 章数');
        final probe = source.chapterCount < 3 ? source.chapterCount : 3;
        var nonEmpty = 0;
        var empty = 0;
        for (var spine = 0; spine < probe; spine++) {
          final pages = await source.loadChapter(spine);
          if (pages.isEmpty) {
            // 合法空章：书作者以 display:none 隐藏的制作页/装饰章
            //（级联正确生效的产物），VirtualPager 按 P2-32 跳过。
            empty += 1;
            continue;
          }
          nonEmpty += 1;
        }
        expect(nonEmpty, greaterThan(0),
            reason: '$name 前 $probe 章全部为空（疑似级联回归）');
        // ignore: avoid_print
        print('SMOKE $name chapters=${source.chapterCount} '
            'probe nonEmpty=$nonEmpty empty=$empty ok');
      } catch (error) {
        failures.add('$name $error');
      }
    }
    expect(failures, isEmpty, reason: '真书冒烟失败清单：$failures');
  }, timeout: const Timeout(Duration(minutes: 10)),
      skip: Platform.environment['REAL_EPUB'] != '1');
}
