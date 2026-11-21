import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_mobile/book_source/online_epub_metadata.dart';
import 'package:reader_mobile/book_source/online_epub_update.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

Uint8List _book(List<int> ids) => const OnlineEpubBuilder().build(
  OnlineEpubInput(
    title: '在线测试书',
    author: '作者',
    sourceName: '测试源',
    bookUrl: 'https://example.test/book/1',
    chapters: [
      for (final id in ids)
        OnlineEpubChapter(
          title: '第$id章',
          html: '<p>第$id章原有正文</p>',
          sourceUrl: 'https://example.test/chapter?cid=$id',
        ),
    ],
  ),
);

List<OnlineChapter> _toc(int count) => [
  for (var index = 0; index < count; index++)
    OnlineChapter(
      index: index,
      title: '第${index + 1}章',
      url: 'https://example.test/chapter?cid=${index + 1}',
    ),
];

void main() {
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('online-update-'),
  );
  tearDown(() async => dir.delete(recursive: true));

  test('已有两章只追加第三章，原正文原样保留且正式 EPUB 能重开', () async {
    final original = _book([1, 2]);
    final file = File('${dir.path}/book.epub');
    await file.writeAsBytes(original);
    final updater = await OnlineEpubUpdate.open(file.path);
    expect(updater.newChapters(_toc(3)).map((chapter) => chapter.index), [2]);
    final updated = updater.append(_book([3]), _toc(3));
    final oldZip = ZipDecoder().decodeBytes(original);
    final newZip = ZipDecoder().decodeBytes(updated);
    for (final path in [
      'OEBPS/text/chapter_0001.xhtml',
      'OEBPS/text/chapter_0002.xhtml',
      'OEBPS/style.css',
    ]) {
      expect(newZip.findFile(path)!.content, oldZip.findFile(path)!.content);
    }
    final before = (await openEpub(original)).document!;
    final after = (await openEpub(updated)).document!;
    expect(after.meta.identifier, before.meta.identifier);
    expect(after.spine, hasLength(3));
    expect(after.toc.map((entry) => entry.title), ['第1章', '第2章', '第3章']);
    expect(after.chapterXhtml(2), contains('第3章原有正文'));
    expect(
      after.spine.take(2).map((item) => item.href),
      before.spine.map((item) => item.href),
    );
    before.archive.close();
    after.archive.close();
    await file.writeAsBytes(updated);
    final next = await OnlineEpubUpdate.open(file.path);
    expect(next.newChapters(_toc(3)), isEmpty);
    expect(next.newChapters(_toc(4)).single.index, 3);
    final fourth = next.append(_book([4]), _toc(4));
    final reopened = (await openEpub(fourth)).document!;
    expect(reopened.spine, hasLength(4));
    expect(reopened.chapterXhtml(3), contains('第4章原有正文'));
    reopened.archive.close();
  });

  test('旧包缺少索引按目录匹配，目录缩短或身份变化拒绝写回', () async {
    final original = ZipDecoder().decodeBytes(_book([1, 2]));
    final legacy = Archive();
    for (final file in original.files) {
      if (!file.name.endsWith('online_chapters.json')) legacy.addFile(file);
    }
    final file = File('${dir.path}/legacy.epub');
    await file.writeAsBytes(ZipEncoder().encodeBytes(legacy));
    final updater = await OnlineEpubUpdate.open(file.path);
    expect(updater.newChapters(_toc(3)), hasLength(1));
    expect(
      () => updater.newChapters(_toc(1)),
      throwsA(isA<BookSourceException>()),
    );
    final bytes = await file.readAsBytes();
    expect(
      utf8.decode(original.findFile('OEBPS/text/chapter_0001.xhtml')!.content),
      contains('第1章原有正文'),
    );
    expect(await file.readAsBytes(), bytes);
    final changed = [
      const OnlineChapter(
        index: 0,
        title: '另一章',
        url: 'https://example.test/other',
      ),
      ..._toc(3).skip(1),
    ];
    expect(
      () => updater.newChapters(changed),
      throwsA(isA<BookSourceException>()),
    );
  });

  test('阅微完整索引使用 URL 和 POST 参数核对身份，不退回同名章节匹配', () async {
    final archive = ZipDecoder().decodeBytes(_book([1, 2]));
    final original = Archive();
    for (final file in archive.files) {
      if (!file.name.endsWith('online_chapters.json')) original.addFile(file);
    }
    final metadata = OnlineEpubMetadata.fromJson({
      'version': 2,
      'sourceId': 'module-source',
      'detailUrl': 'https://example.test/book/1',
      'bookName': '在线测试书',
      'mode': 'FULL',
      'chapters': [
        for (var index = 1; index <= 2; index++)
          {
            'sourceChapterId': '$index',
            'url':
                'https://example.test/content,{"method":"POST","body":"chapter=$index"}',
            'title': '同名章节',
            'volumeTitle': '',
            'href': 'text/chapter_${index.toString().padLeft(4, '0')}.xhtml',
            'state': 'READY',
          },
      ],
    })!;
    final file = File('${dir.path}/reamicro.epub');
    await file.writeAsBytes(ZipEncoder().encodeBytes(original));
    final updater = await OnlineEpubUpdate.open(
      file.path,
      sourceMetadata: metadata,
    );
    final chapters = [
      for (var index = 1; index <= 3; index++)
        OnlineChapter(
          index: index - 1,
          title: '同名章节',
          url: 'https://example.test/content',
          requestOptions: {'method': 'POST', 'body': 'chapter=$index'},
        ),
    ];
    expect(updater.newChapters(chapters).single.index, 2);
    expect(
      () => updater.newChapters([chapters[1], chapters[0], chapters[2]]),
      throwsA(isA<BookSourceException>()),
    );
    expect(
      () => updater.newChapters([
        chapters[0],
        const OnlineChapter(
          index: 1,
          title: '同名章节',
          url: 'https://example.test/content',
          requestOptions: {'method': 'POST', 'body': 'chapter=其他章'},
        ),
        chapters[2],
      ]),
      throwsA(isA<BookSourceException>()),
    );
    final bytes = updater.append(_book([3]), chapters);
    final updated = await openEpub(bytes);
    expect(updated.document!.spine, hasLength(3));
    expect(updated.document!.chapterXhtml(2), contains('第3章原有正文'));
    updated.document!.archive.close();
    await file.writeAsBytes(bytes);
    final reopened = await OnlineEpubUpdate.open(
      file.path,
      sourceMetadata: metadata,
    );
    expect(reopened.newChapters(chapters), isEmpty);
  });

  test('追加章节中的相对图片和样式路径可通过正式 EPUB 资源入口读取', () async {
    final file = File('${dir.path}/resources.epub');
    await file.writeAsBytes(_book([1]));
    final updater = await OnlineEpubUpdate.open(file.path);
    final imageBytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    final incoming = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '在线测试书',
        author: '作者',
        chapters: const [
          OnlineEpubChapter(
            title: '第2章',
            html: '<p>新增正文<img src="../images/new.png"/></p>',
            sourceUrl: 'https://example.test/chapter?cid=2',
          ),
        ],
        images: [
          OnlineEpubImage(
            path: 'images/new.png',
            bytes: imageBytes,
            mediaType: 'image/png',
          ),
        ],
      ),
    );
    final opened = await openEpub(updater.append(incoming, _toc(2)));
    final doc = opened.document!;
    final href = doc.spine[1].href;
    final html = XmlDocument.parse(doc.chapterXhtml(1)!);
    final img = html.descendants.whereType<XmlElement>().firstWhere(
      (element) => element.name.local == 'img',
    );
    final css = html.descendants.whereType<XmlElement>().firstWhere(
      (element) => element.name.local == 'link',
    );
    String resolve(String relative) => p.posix.normalize(
      '${p.posix.dirname(doc.opfPath)}/${p.posix.dirname(href)}/$relative',
    );
    expect(
      doc.archive.readBytes(resolve(img.getAttribute('src')!)),
      imageBytes,
    );
    expect(
      doc.archive.readString(resolve(css.getAttribute('href')!)),
      contains('body'),
    );
    doc.archive.close();
  });
}
