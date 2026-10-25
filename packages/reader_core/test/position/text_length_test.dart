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
