import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late EpubEditSession session;
  final sources = <EpubChapterSource>[];
  setUp(() async {
    ChapterLayoutCache.recent.clear();
    directory = await Directory.systemTemp.createTemp('preview-cache-');
    session = await EpubEditSession.open(await _book(directory));
  });
  tearDown(() async {
    for (final source in sources) {
      source.close();
      await source.preparationsStopped;
    }
    sources.clear();
    session.close();
    ChapterLayoutCache.recent.clear();
    await directory.delete(recursive: true);
  });
  Future<EpubChapterSource> preview() async {
    final source = await session.createPreviewSource(
      options: const ReaderOpenOptions(contentWidth: 240, contentHeight: 320),
    );
    sources.add(source);
    return source;
  }

  test('正文仅失效本章，旧 source 关闭后其他章结构与页面仍复用', () async {
    final original = await session.baseFile.readAsBytes();
    final old = await preview();
    final pages = [for (var i = 0; i < 3; i++) await old.loadChapter(i)];
    old.close();
    await old.preparationsStopped;
    _replace(session, 'OPS/c0.xhtml', '第0章正文', '第0章新正文');
    final next = await preview();
    expect(identical(await next.loadChapter(1), pages[1]), isTrue);
    expect(identical(await next.loadChapter(2), pages[2]), isTrue);
    expect(next.anchorPreparationCount, 0);
    expect(next.chapterLayoutCount, 0);
    expect(identical(await next.loadChapter(0), pages[0]), isFalse);
    expect((await next.loadAnchorChapter(0)).text, contains('第0章新正文'));
    expect(next.anchorPreparationCount, 1);
    expect(next.chapterLayoutCount, 1);
    expect(await session.baseFile.readAsBytes(), original);
    expect(directory.listSync().whereType<File>(), hasLength(1));
  });

  test('共享 CSS 的 import 仅失效依赖章，其他章不重新准备或排版', () async {
    final old = await preview();
    final pages = [for (var i = 0; i < 3; i++) await old.loadChapter(i)];
    old.close();
    _replace(session, 'OPS/shared.css', '16px', '24px');
    final next = await preview();
    expect(identical(await next.loadChapter(2), pages[2]), isTrue);
    expect(next.anchorPreparationCount, 0);
    for (var i = 0; i < 2; i++) {
      final changed = await next.loadChapter(i);
      expect(identical(changed, pages[i]), isFalse);
      expect(
        changed
            .expand((page) => page.slices)
            .any((slice) => slice.block.style?.fontSize == 24),
        isTrue,
      );
    }
    expect(next.anchorPreparationCount, 2);
    expect(next.chapterLayoutCount, 2);
  });

  test('替换图片使引用章失效，新快照读取新字节且旧快照保持原图', () async {
    final old = await preview();
    final pages = [for (var i = 0; i < 3; i++) await old.loadChapter(i)];
    final originalImage = await old.readImageBytes('OPS/image.png');
    final replacement = await _png(20, 10);
    session.transaction(
      '换图',
      (tx) => tx.writeBytes('OPS/image.png', replacement),
    );
    final next = await preview();
    expect(identical(await next.loadChapter(1), pages[1]), isTrue);
    expect(identical(await next.loadChapter(2), pages[2]), isTrue);
    expect(identical(await next.loadChapter(0), pages[0]), isFalse);
    expect(await next.readImageBytes('OPS/image.png'), replacement);
    expect(await old.readImageBytes('OPS/image.png'), originalImage);
    expect(next.anchorPreparationCount, 1);
    expect(next.chapterLayoutCount, 1);
  });

  test('关闭在途旧快照不会发布旧结果或污染新版本缓存', () async {
    final old = await preview();
    final handle = old.scheduleChapter(0);
    final cancelled = expectLater(
      handle.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    old.close();
    _replace(session, 'OPS/c0.xhtml', '第0章正文', '取消后新正文');
    final next = await preview();
    await next.loadChapter(0);
    await cancelled;
    await old.preparationsStopped;
    expect((await next.loadAnchorChapter(0)).text, contains('取消后新正文'));
    final finalPreview = await preview();
    await finalPreview.loadChapter(0);
    expect(finalPreview.anchorPreparationCount, 0);
    expect(finalPreview.chapterLayoutCount, 0);
  });

  test('共享样式中的图片资源变化按引用失效，尺寸变化不会误用旧结构', () async {
    session.transaction(
      '背景图',
      (tx) => tx.writeText(
        'OPS/shared.css',
        'p { font-size:16px; background-image:url(image.png); }',
      ),
    );
    final old = await preview();
    final pages = [for (var i = 0; i < 3; i++) await old.loadChapter(i)];
    old.close();
    final bytes = await _png(12, 9);
    session.transaction(
      '背景资源换图',
      (tx) => tx.writeBytes('OPS/image.png', bytes),
    );
    final next = await preview();
    expect(identical(await next.loadChapter(2), pages[2]), isTrue);
    expect(next.anchorPreparationCount, 0);
    for (var i = 0; i < 2; i++) {
      expect(identical(await next.loadChapter(i), pages[i]), isFalse);
    }
    expect(next.anchorPreparationCount, 2);
    final resized = await session.createPreviewSource(
      options: const ReaderOpenOptions(contentWidth: 180, contentHeight: 320),
    );
    sources.add(resized);
    expect(identical(await resized.loadChapter(2), pages[2]), isFalse);
    expect(resized.anchorPreparationCount, 1);
    expect(resized.chapterLayoutCount, 1);
  });
}

void _replace(EpubEditSession session, String path, String old, String next) =>
    session.transaction(
      '修改 $path',
      (tx) =>
          tx.writeText(path, session.readText(path).replaceFirst(old, next)),
    );

Future<File> _book(Directory directory) async {
  final resources = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles>'
      '<rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    ),
    'OPS/book.opf': utf8.encode(_package),
    for (var i = 0; i < 3; i++) 'OPS/c$i.xhtml': utf8.encode(_chapter(i)),
    'OPS/linked.css': utf8.encode('@import "shared.css";'),
    'OPS/shared.css': utf8.encode('p { font-size:16px; }'),
    'OPS/other.css': utf8.encode('p { font-size:17px; }'),
    'OPS/image.png': await _png(1, 1),
  };
  final archive = Archive();
  for (final entry in resources.entries) {
    archive.addFile(
      entry.key == 'mimetype'
          ? ArchiveFile.noCompress(entry.key, entry.value.length, entry.value)
          : ArchiveFile.bytes(entry.key, entry.value),
    );
  }
  return File('${directory.path}/book.epub')
      .writeAsBytes(ZipEncoder().encodeBytes(archive));
}

String _chapter(int i) =>
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>$i</title><link rel="stylesheet" href="${i == 2 ? 'other' : 'linked'}.css"/>'
    '</head><body><p>第$i章正文</p>${i == 0 ? '<img src="image.png"/>' : ''}</body></html>';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

const _package = '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">preview-cache</dc:identifier><dc:title>预览</dc:title><dc:language>zh</dc:language></metadata>
<manifest><item id="c0" href="c0.xhtml" media-type="application/xhtml+xml"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
<item id="linked" href="linked.css" media-type="text/css"/><item id="shared" href="shared.css" media-type="text/css"/><item id="other" href="other.css" media-type="text/css"/><item id="image" href="image.png" media-type="image/png"/></manifest>
<spine><itemref idref="c0"/><itemref idref="c1"/><itemref idref="c2"/></spine></package>''';
