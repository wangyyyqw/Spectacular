import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi.dart' as hb;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _mediaTypes = {
  '.xhtml': 'application/xhtml+xml',
  '.css': 'text/css',
  '.ncx': 'application/x-dtbncx+xml',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.bmp': 'image/bmp',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

Archive mediaEpub({
  required Map<String, Uint8List> resources,
  String body = '<p>AB A</p>',
  String stylesheet = '',
  Map<String, String> otherChapters = const {},
  Map<String, String> manifestIds = const {},
}) {
  final files = <String, Uint8List>{
    'OEBPS/styles/style.css': utf8.encode(stylesheet),
    'OEBPS/text/ch1.xhtml': utf8.encode(mediaXhtml(body)),
    for (final chapter in otherChapters.entries)
      chapter.key: utf8.encode(mediaXhtml(chapter.value)),
    ...resources,
  };
  final ids = {
    for (final name in files.keys)
      name: manifestIds[name] ?? 'resource${files.keys.toList().indexOf(name)}',
  };
  final manifest = files.keys.map((name) {
    final href = p.posix.relative(name, from: 'OEBPS');
    final encoded = href.split('/').map(Uri.encodeComponent).join('/');
    return '<item id="${ids[name]}" href="$encoded" '
        'media-type="${_mediaTypes[p.posix.extension(name)] ?? 'application/octet-stream'}"/>';
  }).join();
  final chapters = ['OEBPS/text/ch1.xhtml', ...otherChapters.keys];
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="book">媒体回归</dc:identifier><dc:title>媒体回归</dc:title>'
            '<dc:language>zh</dc:language></metadata><manifest>$manifest</manifest>'
            '<spine>${chapters.map((name) => '<itemref idref="${ids[name]}"/>').join()}</spine>'
            '</package>',
      ),
    );
  for (final file in files.entries) {
    archive.addFile(ArchiveFile.bytes(file.key, file.value));
  }
  return archive;
}

String mediaXhtml(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:xlink="http://www.w3.org/1999/xlink"><head><title>媒体回归</title>'
    '<link href="../styles/style.css" rel="stylesheet" type="text/css"/>'
    '</head><body>$body</body></html>';

img.Image mediaImage({
  bool transparent = false,
  img.Format format = img.Format.uint8,
}) {
  final image = img.Image(
    width: 96,
    height: 80,
    numChannels: 4,
    format: format,
  );
  for (final pixel in image) {
    pixel
      ..rNormalized = (pixel.x * 7 % 256) / 255
      ..gNormalized = (pixel.y * 11 % 256) / 255
      ..bNormalized = ((pixel.x + pixel.y) * 3 % 256) / 255
      ..aNormalized = transparent && pixel.x < 48 ? (pixel.x % 3) / 2 : 1;
  }
  return image;
}

Future<void> writeMediaEpub(String path, Archive archive) =>
    File(path).writeAsBytes(ZipEncoder().encode(archive));

Future<Archive> readMediaEpub(String path) async =>
    ZipDecoder().decodeBytes(await File(path).readAsBytes());

String mediaText(Archive archive, String path) =>
    utf8.decode(archive.findFile(path)!.content);

Map<String, Uint8List> mediaFontTables(Uint8List font) {
  final data = ByteData.sublistView(font);
  return {
    for (var index = 0; index < data.getUint16(4); index++)
      String.fromCharCodes(font.sublist(12 + index * 16, 16 + index * 16)): font
          .sublist(
            data.getUint32(20 + index * 16),
            data.getUint32(20 + index * 16) + data.getUint32(24 + index * 16),
          ),
  };
}

int mediaFontChecksum(Uint8List bytes) {
  var sum = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    var word = 0;
    for (var index = 0; index < 4; index++) {
      word =
          (word << 8) |
          (offset + index < bytes.length ? bytes[offset + index] : 0);
    }
    sum = (sum + word) & 0xffffffff;
  }
  return sum;
}

Result _withMediaFont<Result>(
  Uint8List data,
  Result Function(Pointer<hb.hb_font_t>, Arena) callback,
) => using((arena) {
  final bytes = arena<Uint8>(data.length)
    ..asTypedList(data.length).setAll(0, data);
  final blob = hb.hb_blob_create(
    bytes.cast(),
    data.length,
    hb.hb_memory_mode_t.HB_MEMORY_MODE_DUPLICATE,
    nullptr,
    nullptr,
  );
  final face = hb.hb_face_create(blob, 0);
  final font = hb.hb_font_create(face);
  try {
    return callback(font, arena);
  } finally {
    hb.hb_font_destroy(font);
    hb.hb_face_destroy(face);
    hb.hb_blob_destroy(blob);
  }
});

int mediaGlyphId(Uint8List data, int codePoint) =>
    _withMediaFont(data, (font, arena) {
      final glyph = arena<Uint32>();
      return hb.hb_font_get_nominal_glyph(font, codePoint, glyph) == 0
          ? 0
          : glyph.value;
    });

List<Object> mediaShape(
  Uint8List data,
  String text, {
  String feature = 'liga=1',
  bool vertical = false,
}) => _withMediaFont(data, (font, arena) {
  final buffer = hb.hb_buffer_create();
  try {
    hb.hb_buffer_add_utf8(
      buffer,
      text.toNativeUtf8(allocator: arena).cast(),
      -1,
      0,
      -1,
    );
    hb.hb_buffer_guess_segment_properties(buffer);
    if (vertical) {
      hb.hb_buffer_set_direction(buffer, hb.hb_direction_t.HB_DIRECTION_TTB);
    }
    final setting = arena<hb.hb_feature_t>();
    hb.hb_feature_from_string(
      feature.toNativeUtf8(allocator: arena).cast(),
      -1,
      setting,
    );
    hb.hb_shape(font, buffer, setting, 1);
    return _mediaShapeResult(font, buffer, arena);
  } finally {
    hb.hb_buffer_destroy(buffer);
  }
});

List<Object> _mediaShapeResult(
  Pointer<hb.hb_font_t> font,
  Pointer<hb.hb_buffer_t> buffer,
  Arena arena,
) {
  final count = arena<UnsignedInt>();
  final glyphs = hb.hb_buffer_get_glyph_infos(buffer, count);
  final positions = hb.hb_buffer_get_glyph_positions(buffer, nullptr);
  final name = arena<Char>(256);
  final result = <Object>[];
  for (var index = 0; index < count.value; index++) {
    hb.hb_font_glyph_to_string(font, glyphs[index].codepoint, name, 256);
    result.addAll([
      name.cast<Utf8>().toDartString(),
      positions[index].x_advance,
      positions[index].y_advance,
      positions[index].x_offset,
      positions[index].y_offset,
    ]);
  }
  return result;
}
