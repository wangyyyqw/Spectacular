import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/epub/resource_index.dart';
import 'package:reader_core/epub/zip_source.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_ui/reader_session.dart';

const _chapter = 'OEBPS/Text/chapter.xhtml';
const _notes = 'OEBPS/Text/notes.xhtml';
const _indirect = 'OEBPS/Text/indirect.xhtml';
const _image = 'OEBPS/Images/插图.png';
const _opf = '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">prepare</dc:identifier><dc:title>准备测试</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="chapter"/></spine></package>''';

String _xhtml(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
    '<style>p{color:red}</style></head><body>$body</body></html>';

List<int> _utf16(String text) => [
  0xff,
  0xfe,
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

BookResources _resources(
  Map<String, List<int>> files, {
  CompressionType compression = CompressionType.deflate,
  Set<String> damaged = const {},
}) {
  final entries = Archive();
  for (final entry in files.entries) {
    entries.addFile(
      ArchiveFile(entry.key, entry.value.length, entry.value)
        ..compression = compression,
    );
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(entries));
  _damage(bytes, damaged);
  final archive = EpubArchive.fromBytes(bytes, verify: false);
  final package = OpfParser.parse(_opf);
  final resources = BookResources(
    EpubDocumentImpl(
      archive: archive,
      package: package,
      resources: ResourceIndex.build(
        archive: archive,
        manifest: package.manifest,
        opfPath: 'OEBPS/content.opf',
      ),
      opfPath: 'OEBPS/content.opf',
      toc: const [],
      tocSource: 'spine',
      report: const ImportReport(ok: true),
    ),
  );
  addTearDown(() => _close(resources));
  return resources;
}

Future<void> _close(BookResources resources) async {
  resources.close();
  await resources.preparationsStopped;
  expect(resources.preparationWorker.activeIsolates, 0);
  expect(resources.preparationWorker.openPortCount, 0);
}

void _damage(Uint8List bytes, Set<String> paths) {
  if (paths.isEmpty) return;
  final index = ZipIndex.tryParse(ZipByteSource.fromBytes(bytes))!;
  final data = ByteData.sublistView(bytes);
  for (final path in paths) {
    final offset = index.entries[path]!.localHeaderOffset;
    final start =
        offset +
        30 +
        data.getUint16(offset + 26, Endian.little) +
        data.getUint16(offset + 28, Endian.little);
    bytes[start] = 0x07;
  }
  index.release();
}

Matcher _missingChapter() => isA<EpubException>()
    .having((error) => error.code, '错误码', 'E_SPINE_MISSING')
    .having((error) => error.message, '错误文本', '章节文件不存在：$_chapter');

int _holdWorker(SendPort ready) {
  ready.send(true);
  while (true) {}
}

Future<void> _waitForWorker(BookResources resources) async {
  for (var turn = 0; turn < 100; turn++) {
    if (resources.preparationWorker.activeIsolates > 0) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('章节准备在 100 个事件循环轮次内未启动 worker');
}

Future<Uint8List> _pngBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff00ff00), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final compression in [CompressionType.none, CompressionType.deflate]) {
    test('$compression 图片异步读取保留原字节和相对路径兼容', () async {
      final bytes = utf8.encode('图片资源原始字节' * 100);
      final resources = _resources({_image: bytes}, compression: compression);
      for (final path in [
        _image,
        '/$_image',
        '../Images/插图.png',
        'OEBPS/Images/%E6%8F%92%E5%9B%BE.png#图片',
      ]) {
        expect(await resources.readImage(path), bytes, reason: path);
      }
      expect(await resources.readImage('missing.png'), isNull);
    });

    test('$compression 章节与直接脚注在 worker 解码 UTF16', () async {
      final source = _xhtml(
        '<p>中文正文'
        '<a epub:type="noteref" href="notes.xhtml#n">[1]</a>'
        '<a epub:type="noteref" href="missing.xhtml#m">[2]</a></p>',
      );
      final note = _xhtml(
        '<aside epub:type="footnote" id="n">中文注释'
        '<a epub:type="noteref" href="indirect.xhtml#x">[3]</a></aside>',
      );
      final files = {
        _chapter: _utf16(source),
        _notes: _utf16(note),
        _indirect: _utf16(_xhtml('<aside id="x">间接定义</aside>')),
      };
      final resources = _resources(files, compression: compression);
      final sync = _resources(files, compression: compression);
      final parsed = await resources.prepareChapter(0);
      expect(parsed.source, source);
      expect(parsed.plainText, sync.parsedChapter(0).plainText);
      expect(await resources.prepareChapter(0), same(parsed));
      expect(await resources.prepareStyleSources(0), hasLength(1));
      final notes = await resources.prepareFootnotes(0);
      expect(
        notes.values.firstWhere((note) => note.targetId == 'n').noteText,
        contains('中文注释'),
      );
      expect(
        notes.values.map((note) => note.noteText),
        sync.footnotes(0).values.map((note) => note.noteText),
      );
      expect(resources.document.archive.contains(_indirect), isTrue);
      expect(resources.footnoteCacheCount, 1);
    });
  }

  test('并发图片读取共享结果，损坏条目在结果提交后移除', () async {
    final bytes = utf8.encode('并发图片原始字节' * 1000);
    final resources = _resources(
      {_image: bytes, 'bad.png': bytes},
      damaged: {'bad.png'},
    );
    final reads = await Future.wait([
      resources.readImage(_image),
      resources.readImage('/$_image'),
      resources.readImage(_image.replaceAll('/', '\\')),
    ]);
    expect(reads.first, bytes);
    for (final read in reads.skip(1)) {
      expect(read, same(reads.first));
    }
    expect(await resources.readImage('bad.png'), isNull);
    expect(resources.document.archive.contains('bad.png'), isFalse);
    expect(await resources.readImage('bad.png'), isNull);
  });

  test('图片不抢占章节预取，被前台抢占后自动恢复而不返回缺图', () async {
    final bytes = Uint8List(8 * 1024 * 1024);
    final resources = _resources({_image: bytes});
    final backgroundReady = ReceivePort();
    addTearDown(backgroundReady.close);
    final background = resources.preparationWorker.schedule(
      '占用预取槽',
      () => backgroundReady.sendPort,
      _holdWorker,
      priority: ChapterLayoutPriority.prefetch,
    );
    await backgroundReady.first;
    final stopped = expectLater(
      background.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    final image = resources.readImage(_image);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(resources.preparationWorker.activeIsolates, 1);
    background.cancel();
    await stopped;
    await _waitForWorker(resources);
    final foregroundReady = ReceivePort();
    addTearDown(foregroundReady.close);
    final foreground = resources.preparationWorker.schedule(
      '前台章节优先',
      () => foregroundReady.sendPort,
      _holdWorker,
    );
    await foregroundReady.first;
    final foregroundStopped = expectLater(
      foreground.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    foreground.cancel();
    await foregroundStopped;
    expect(await image, bytes);
  });

  test('已解码图片命中缓存时不等待被占用的准备槽', () async {
    final resources = _resources({_image: await _pngBytes()});
    final images = DecodedImageCache(loadBytes: resources.readImage);
    addTearDown(images.clear);
    final image = await images.load(_image, displayWidth: 100);
    expect(image, isNotNull);
    final ready = ReceivePort();
    addTearDown(ready.close);
    final hold = resources.preparationWorker.schedule(
      '占用图片准备槽',
      () => ready.sendPort,
      _holdWorker,
    );
    await ready.first;
    expect(await images.load(_image, displayWidth: 100), same(image));
    final cancelled = expectLater(
      hold.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    hold.cancel();
    await cancelled;
  });

  test('关闭书籍丢弃排队与运行中的图片，随后读取返回空', () async {
    final resources = _resources({_image: Uint8List(8 * 1024 * 1024)});
    final ready = ReceivePort();
    addTearDown(ready.close);
    final hold = resources.preparationWorker.schedule(
      '图片之前占用槽位',
      () => ready.sendPort,
      _holdWorker,
    );
    await ready.first;
    final queued = resources.readImage(_image);
    final stopped = expectLater(
      hold.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    await _close(resources);
    await stopped;
    expect(await queued, isNull);
    expect(await resources.readImage(_image), isNull);

    final reopened = _resources({_image: Uint8List(8 * 1024 * 1024)});
    final running = reopened.readImage(_image);
    await _waitForWorker(reopened);
    await _close(reopened);
    expect(await running, isNull);
  });

  test('损坏章节在解压结果提交后移除，缺失错误码和文本保持不变', () async {
    final resources = _resources(
      {_chapter: utf8.encode(_xhtml('<p>坏压缩内容</p>' * 100))},
      damaged: {_chapter},
    );
    expect(resources.document.archive.contains(_chapter), isTrue);
    await expectLater(resources.prepareChapter(0), throwsA(_missingChapter()));
    expect(resources.document.archive.contains(_chapter), isFalse);
    await expectLater(resources.prepareChapter(0), throwsA(_missingChapter()));
  });

  test('损坏直接脚注跳过并移除，未引用坏条目保持未读取', () async {
    final resources = _resources(
      {
        _chapter: utf8.encode(
          _xhtml(
            '<a epub:type="noteref" '
            'href="notes.xhtml#n">[1]</a>',
          ),
        ),
        _notes: utf8.encode(_xhtml('<aside id="n">坏定义</aside>' * 100)),
        _indirect: utf8.encode(_xhtml('<p>未引用坏定义</p>' * 100)),
      },
      damaged: {_notes, _indirect},
    );
    final notes = await resources.prepareFootnotes(0);
    expect(notes.values.every((note) => note.noteText == null), isTrue);
    expect(resources.document.archive.contains(_notes), isFalse);
    expect(resources.document.archive.contains(_indirect), isTrue);
  });

  test('排队取消不读取坏章节，准备槽停止后释放端口', () async {
    final resources = _resources(
      {_chapter: utf8.encode(_xhtml('<p>坏压缩内容</p>' * 100))},
      damaged: {_chapter},
    );
    final ready = ReceivePort();
    addTearDown(ready.close);
    final hold = resources.preparationWorker.schedule(
      '占用准备槽',
      () => ready.sendPort,
      _holdWorker,
    );
    await ready.first;
    final queued = resources.scheduleChapter(0);
    final cancelled = expectLater(
      queued.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    resources.clearParsed();
    await cancelled;
    expect(resources.document.archive.contains(_chapter), isTrue);
    final stopped = expectLater(
      hold.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    hold.cancel();
    await stopped;
    await resources.preparationsStopped;
  });

  test('运行中清理可同键重建，关闭等待同一 worker 和端口释放', () async {
    final resources = _resources({
      _chapter: utf8.encode(_xhtml('<p>运行中取消正文</p>' * 10000)),
    });
    final stale = resources.scheduleChapter(0);
    final cancelled = expectLater(
      stale.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    await _waitForWorker(resources);
    resources.clearParsed();
    await cancelled;
    await resources.preparationsStopped;
    expect(resources.document.archive.contains(_chapter), isTrue);
    final rebuilt = await resources.prepareChapter(0);
    expect(rebuilt.plainText, contains('运行中取消正文'));
    expect(await resources.prepareChapter(0), same(rebuilt));
    resources.clearParsed();
    final closing = resources.scheduleChapter(0);
    final closed = expectLater(
      closing.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    await _waitForWorker(resources);
    await _close(resources);
    await closed;
    expect(resources.footnoteCacheCount, 0);
    await expectLater(
      resources.prepareChapter(0),
      throwsA(isA<ChapterLoadCancelled>()),
    );
  });
}
