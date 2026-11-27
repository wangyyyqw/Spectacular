import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:xml/xml.dart';

import '../editing/epub_export.dart';
import '../library/library_store.dart';
import 'book_cover_url.dart';
import 'online_epub_builder.dart';
import 'online_epub_metadata.dart';

abstract final class OnlineEpubExport {
  static Future<bool> save(BookEntry book, String fileName) async {
    final source = File(book.filePath);
    final archive = await EpubArchive.fromFile(source);
    final bool online;
    try {
      online =
          archive.contains('OEBPS/online_chapters.json') ||
          archive.contains(OnlineEpubMetadata.indexPath);
    } finally {
      archive.close();
    }
    if (!online) return EpubExport.saveToDownloads(source, fileName: fileName);
    final temporary = await EpubExport.createTemporaryDirectory();
    try {
      final output = File(p.join(temporary.path, 'export.epub'));
      await write(book, output);
      return await EpubExport.saveToDownloads(output, fileName: fileName);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<void> write(BookEntry book, File output) async {
    final session = await EpubEditSession.open(File(book.filePath));
    try {
      final editor = PackageEditor(session);
      final directory = p.posix.dirname(session.opfPath);
      final resources = session.resources;
      final occupied = resources.map((item) => item.path).toSet();
      final moves = <String, String>{};
      final styles = <String>[];
      for (final item in resources) {
        final css = item.mediaType == 'text/css' || item.path.endsWith('.css');
        if (!css && !item.mediaType.startsWith('image/')) continue;
        if (css) styles.add(item.path);
        final targetDir = p.posix.join(
          directory,
          css ? 'Styles' : OnlineEpubImage.directory,
        );
        if (p.posix.dirname(item.path) == targetDir) continue;
        moves[item.path] = _reserve(
          occupied,
          p.posix.join(targetDir, p.posix.basename(item.path)),
        );
      }
      editor.renameResources(moves);
      const generatedTitle =
          '.chapter-title { font-size: calc(1.5em - 2px); margin: 0 0 1.2em; text-align: center; }';
      session.transaction('更新在线章标题字号', (tx) {
        for (final original in styles) {
          final path = moves[original] ?? original;
          final css = session.readText(path);
          if (css.contains(generatedTitle)) {
            tx.writeText(
              path,
              css.replaceFirst(
                generatedTitle,
                generatedTitle.replaceFirst('2px', '4px'),
              ),
            );
          }
        }
      });
      final package = OpfParser.parse(session.readText(session.opfPath));
      final declared = package.manifest
          .where(
            (item) =>
                item.mediaType.startsWith('image/') &&
                (item.properties.contains('cover-image') ||
                    item.id == package.coverItemId),
          )
          .firstOrNull;
      final embedded = declared == null
          ? null
          : resolveEditReference(session.opfPath, declared.href).$1;
      if (embedded == null || session.readBytes(embedded)?.isNotEmpty != true) {
        final cover = await _shelfCover(book) ?? await _titleCover(book.title);
        final path = _reserve(occupied, p.posix.join(directory, cover.path));
        editor.addResource(path, cover.bytes, cover.mediaType);
        editor.setCover(path);
        final page = p.posix.join(directory, 'cover.xhtml');
        final opf = XmlDocument.parse(session.readText(session.opfPath));
        final guide = opf.rootElement.childElements
            .where((element) => element.name.local == 'guide')
            .firstOrNull;
        if (!occupied.contains(page) &&
            !(guide?.childElements.any(
                  (item) => item.getAttribute('type') == 'cover',
                ) ??
                false)) {
          editor.addXhtml(page, '封面', index: 0);
          final style = styles.firstOrNull;
          final coverPage = const OnlineEpubBuilder().buildCoverDocument(
            book.title,
            relativeEditReference(page, path),
            stylesheet: style == null
                ? null
                : relativeEditReference(page, moves[style] ?? style),
          );
          session.transaction('写入封面页', (tx) {
            tx.writeText(page, coverPage);
            if (guide == null) return;
            final updated = XmlDocument.parse(
              session.readText(session.opfPath),
            );
            updated.rootElement.childElements
                .firstWhere((item) => item.name.local == 'guide')
                .children
                .add(
                  XmlElement(
                    XmlName.parts('reference', prefix: guide.name.prefix),
                    [
                      XmlAttribute(XmlName.parts('type'), 'cover'),
                      XmlAttribute(XmlName.parts('title'), '封面'),
                      XmlAttribute(
                        XmlName.parts('href'),
                        relativeEditReference(session.opfPath, page),
                      ),
                    ],
                  ),
                );
            tx.writeText(session.opfPath, updated.toXmlString());
          });
        }
      }
      await EpubWriter.write(session, output);
    } finally {
      session.close();
    }
  }

  static String _reserve(Set<String> occupied, String path) {
    var candidate = path;
    for (var counter = 2; !occupied.add(candidate); counter++) {
      candidate =
          '${p.posix.withoutExtension(path)}-$counter${p.posix.extension(path)}';
    }
    return candidate;
  }

  static Future<OnlineEpubImage?> _shelfCover(BookEntry book) async {
    const limit = 8 * 1024 * 1024;
    if (book.coverPath case final path?) {
      final file = File(path);
      if (await file.exists() && await file.length() <= limit) {
        final cover = OnlineEpubImage.fromBytes(
          await file.readAsBytes(),
          'cover',
        );
        if (cover != null) return cover;
      }
    }
    final url = normalizeBookCoverUrl(book.remoteCoverUrl);
    if (url == null) return null;
    final client = http.Client();
    Future<OnlineEpubImage?> fetch() async {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(bookCoverHeaders(url));
      final response = await client.send(request);
      if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
        return null;
      }
      final buffer = BytesBuilder(copy: false);
      await for (final part in response.stream) {
        if (buffer.length + part.length > limit) return null;
        buffer.add(part);
      }
      return OnlineEpubImage.fromBytes(buffer.takeBytes(), 'cover');
    }

    try {
      return await fetch().timeout(const Duration(seconds: 8));
    } on Exception {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<OnlineEpubImage> _titleCover(String title) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xfff4f1eb), ui.BlendMode.src);
    final text =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: ui.TextAlign.center,
                  maxLines: 6,
                  ellipsis: '…',
                ),
              )
              ..pushStyle(
                ui.TextStyle(fontSize: 48, color: const ui.Color(0xff33302b)),
              )
              ..addText(title.trim().isEmpty ? '未命名书籍' : title))
            .build()
          ..layout(const ui.ParagraphConstraints(width: 480));
    canvas.drawParagraph(text, ui.Offset(60, (800 - text.height) / 2));
    text.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 800);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return OnlineEpubImage.fromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        'cover',
      )!;
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
