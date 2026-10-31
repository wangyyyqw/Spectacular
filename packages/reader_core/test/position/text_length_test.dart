import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/text_length.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('轻量正文字符统计（§22.3）', () {
    test('去标签与空白，只数正文', () {
      const xhtml =
          '<html><head><title>标题</title></head><body>'
          '<p>一二三</p>\n<p>四 五</p></body></html>';
      // 标签去掉后剩“标题一二三四 五”，非空白字符 = 标题一二三四五 = 7。
      expect(TextLengthScanner.count(xhtml), 7);
    });

    test('排除注释、script 与 style 内容', () {
      const xhtml =
          '<body><!-- 注释文字 --><script>var a = 1;</script>'
          '<style>p{color:red}</style><p>正文</p></body>';
      expect(TextLengthScanner.count(xhtml), 2);
    });

    test('解码实体与数字引用', () {
      const xhtml = '<p>a&amp;b&lt;c&#65;&#x42;&nbsp;d</p>';
      // a&b<c A B d → 8 个非空白字符（&nbsp; 解码为空格被排除）。
      expect(TextLengthScanner.count(xhtml), 8);
    });

    test('空文本为 0', () {
      expect(TextLengthScanner.count(''), 0);
      expect(TextLengthScanner.count('<p>   </p>'), 0);
    });

    test('排除全部 Unicode 空白且保留邻界非空白', () {
      final whitespace = <int>[
        for (var unit = 0x0009; unit <= 0x000d; unit++) unit,
        0x0020,
        0x00a0,
        0x1680,
        for (var unit = 0x2000; unit <= 0x200a; unit++) unit,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
        0xfeff,
      ];
      expect(TextLengthScanner.count(String.fromCharCodes(whitespace)), 0);
      final neighbors = <int>{
        for (final unit in whitespace) ...<int>[unit - 1, unit + 1],
        0x0085,
        0x180e,
        0x200b,
        0x2060,
      }..removeAll(whitespace);
      final text = String.fromCharCodes(neighbors);
      expect(TextLengthScanner.count(text), text.length);
    });

    test('全部 BMP 码元的空白判定与 Dart 正则一致', () {
      final whitespace = RegExp(r'\s');
      for (var unit = 0; unit <= 0xffff; unit++) {
        final text = String.fromCharCode(unit);
        expect(
          TextLengthScanner.count(text),
          whitespace.hasMatch(text) ? 0 : 1,
          reason: 'U+${unit.toRadixString(16).padLeft(4, '0')}',
        );
      }
    });

    test('代理对与未配对代理均保持 UTF-16 码元口径', () {
      expect(TextLengthScanner.count('\u{1f600}\u{20000}'), 4);
      expect(TextLengthScanner.count('\ud83d'), 1);
      expect(TextLengthScanner.count('\ude00'), 1);
      expect(TextLengthScanner.count('&#128512;&#x20000;'), 4);
    });

    test('标签与实体处理顺序及既有正文范围不变', () {
      const xhtml =
          '<head><title>标题</title></head><body>'
          '<!-- 注释 --><ScRiPt>隐藏</ScRiPt><STYLE>隐藏</STYLE>'
          '<p>甲&#x2003;&#65279;&#x85;&#x180e;&unknown;'
          '&lt;b&gt;乙&lt;/b&gt;</p></body>';
      // 实体在去标签后解码，解码出的 <b> 仍按文本计数；标题也保留。
      expect(TextLengthScanner.count(xhtml), 13);
    });
  });

  group('章节字符统计（导入期）', () {
    late Uint8List epub;

    setUpAll(() {
      final file = File('../../test_corpus/basic.epub');
      if (!file.existsSync()) {
        throw StateError('缺少测试样书：${file.path}');
      }
      epub = file.readAsBytesSync();
    });

    test('countChapterCharacters 与逐章扫描一致', () async {
      final document = (await openEpub(epub)).document!;
      final counts = await document.countChapterCharacters();
      expect(counts, hasLength(document.spine.length));
      for (var index = 0; index < counts.length; index++) {
        expect(counts[index], document.characterCountOf(index));
      }
      expect(counts.any((count) => count > 0), isTrue, reason: '正文有字符');
    });

    test('逐章统计仍让出事件循环并上报进度', () async {
      final document = (await openEpub(epub)).document!;
      var yielded = false;
      final pending = Future<void>.delayed(Duration.zero, () => yielded = true);
      final progress = <int>[];
      final counts = await document.countChapterCharacters(
        yieldEvery: 1,
        onProgress: (done, total) {
          expect(total, document.spine.length);
          progress.add(done);
        },
      );
      expect(yielded, isTrue);
      expect(progress.first, 1);
      expect(progress.last, counts.length);
      await pending;
    });

    test('线性 spine 全计入进度，nav 与 linear=no 排除', () async {
      final document = (await openEpub(epub)).document!;
      final excluded = document.progressExcludedSpineIndexes;
      for (var index = 0; index < document.spine.length; index++) {
        final item = document.spine[index];
        expect(excluded.contains(index), !item.linear);
      }
    });
  });
}
