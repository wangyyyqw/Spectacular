import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_mobile/book_source/online_epub_export.dart';
import 'package:reader_mobile/library/library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('旧包导出一次整理同名插图、CSS 与章内引用，保留索引和自定义样式并生成书名封面', () async {
    final directory = await Directory.systemTemp.createTemp('online-export-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    final original = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '没有原图的旧书',
        author: '',
        sourceId: 'source',
        chapters: const [
          OnlineEpubChapter(
            title: '第1章 章名',
            html: '<p>正文</p><img src="../images/a.png"/><img src="../old/a.png"/>',
          ),
        ],
        images: [
          for (final path in ['images/a.png', 'old/a.png'])
            OnlineEpubImage(path: path, bytes: bytes, mediaType: 'image/png'),
        ],
      ),
    );
    final old = Archive();
    for (final item in ZipDecoder().decodeBytes(original).files) {
      if (item.name == 'OEBPS/Styles/style.css') {
        old.addFile(
          ArchiveFile.string(
            'OEBPS/style.css',
            '${OnlineEpubBuilder.chapterStylesheet.replaceFirst('1.5em - 4px', '1.5em - 2px')}\np.custom {background:url("old/a.png");}',
          ),
        );
      } else if (item.name.endsWith('.xhtml') || item.name.endsWith('.opf')) {
        old.addFile(
          ArchiveFile.string(
            item.name,
            utf8
                .decode(item.content)
                .replaceAll('Styles/style.css', 'style.css'),
          ),
        );
      } else {
        old.addFile(item);
      }
    }
    final source = File('${directory.path}/source.epub');
    final oldBytes = ZipEncoder().encodeBytes(old);
    await source.writeAsBytes(oldBytes);
    final book = BookEntry(
      id: 'legacy',
      title: '没有原图的旧书',
      author: '',
      filePath: source.path,
      addedAt: DateTime(2026),
    );
    final target = File('${directory.path}/export.epub');
    await OnlineEpubExport.write(book, target);
    final result = (await openEpubFile(target)).document!;
    addTearDown(result.archive.close);
    expect(result.coverResourcePath, 'OEBPS/Images/cover.png');
    expect(result.readCoverBytes(), isNot(equals(bytes)));
    expect(result.chapterXhtml(0), contains('alt="没有原图的旧书"'));
    final chapter = result.chapterXhtml(1)!;
    for (final image in ['a.png', 'a-2.png']) {
      expect(chapter, contains('../Images/$image'));
      expect(result.archive.readBytes('OEBPS/Images/$image'), bytes);
    }
    expect(chapter, contains('../Styles/style.css'));
    final css = result.archive.readString('OEBPS/Styles/style.css')!;
    expect(css, contains('1.5em - 4px'));
    expect(css, contains('p.custom {background:url("../Images/a-2.png");}'));
    expect(result.archive.contains('OEBPS/style.css'), isFalse);
    expect(
      result.archive.readBytes('OEBPS/reamicro-online-chapters.json'),
      old.findFile('OEBPS/reamicro-online-chapters.json')!.content,
    );
    expect(await source.readAsBytes(), oldBytes);
  });
}
