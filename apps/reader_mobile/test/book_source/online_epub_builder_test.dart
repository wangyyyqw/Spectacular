import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';

void main() {
  test('生成 EPUB 3 目录、章节、封面与图片', () {
    final bytes = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '测试 & 书名',
        author: '作者',
        intro: '<p>简介</p>',
        sourceName: '示例源',
        bookUrl: 'https://example.com/book/1',
        cover: OnlineEpubImage(
          path: 'images/cover.png',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          mediaType: 'image/png',
        ),
        images: <OnlineEpubImage>[
          OnlineEpubImage(
            path: 'images/a.png',
            bytes: Uint8List.fromList(<int>[4, 5, 6]),
            mediaType: 'image/png',
          ),
        ],
        chapters: const <OnlineEpubChapter>[
          OnlineEpubChapter(title: '第一章', html: '<p>正文一</p>'),
          OnlineEpubChapter(title: '第二章', html: '<p>正文二</p>'),
        ],
      ),
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    String text(String name) => utf8.decode(archive.findFile(name)!.content);

    expect(text('mimetype'), 'application/epub+zip');
    expect(text('META-INF/container.xml'), contains('OEBPS/content.opf'));

    final opf = text('OEBPS/content.opf');
    expect(opf, contains('测试 &amp; 书名'));
    expect(opf, contains('chapter_0001.xhtml'));
    expect(opf, contains('chapter_0002.xhtml'));
    expect(opf, contains('properties="cover-image"'));
    expect(opf, contains('images/a.png'));

    final nav = text('OEBPS/nav.xhtml');
    expect(nav, contains('第一章'));
    expect(nav, contains('第二章'));
    expect(nav, contains('text/chapter_0002.xhtml'));

    expect(text('OEBPS/text/chapter_0001.xhtml'), contains('正文一'));
    expect(text('OEBPS/text/chapter_0002.xhtml'), contains('正文二'));
    expect(archive.findFile('OEBPS/images/a.png'), isNotNull);
    expect(archive.findFile('OEBPS/cover.xhtml'), isNotNull);
  });

  test('清理脚本、事件属性与无效图片', () {
    final bytes = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '清理',
        author: '',
        chapters: const <OnlineEpubChapter>[
          OnlineEpubChapter(
            title: '第一章',
            html:
                '<p onclick="bad()">正文</p>'
                '<script>alert(1)</script>'
                '<img src="data:image/png;base64,AAAA"/>'
                '<img src="../images/keep.png"/>',
          ),
        ],
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapter = utf8.decode(
      archive.findFile('OEBPS/text/chapter_0001.xhtml')!.content,
    );
    expect(chapter, isNot(contains('<script')));
    expect(chapter, isNot(contains('onclick')));
    expect(chapter, isNot(contains('data:image')));
    expect(chapter, contains('../images/keep.png'));
  });
}
