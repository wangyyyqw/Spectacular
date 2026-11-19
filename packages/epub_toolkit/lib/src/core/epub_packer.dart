import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

class EpubPacker {
  EpubPacker._();

  static final Uint8List _mimetypeBytes = Uint8List.fromList(
    utf8.encode('application/epub+zip'),
  );

  static void ensureMimetype(Archive archive) {
    final existing = archive.findFile('mimetype');
    if (existing != null) {
      existing.compression = CompressionType.none;
      existing.comment = null;
      return;
    }
    archive.addFile(ArchiveFile.noCompress('mimetype', 20, _mimetypeBytes));
  }

  static Future<void> pack({
    required Archive archive,
    required String outputPath,
  }) async {
    ensureMimetype(archive);
    _validateMimetype(archive.findFile('mimetype')!);
    final output = Archive()..comment = archive.comment;
    output.addFile(ArchiveFile.noCompress('mimetype', 20, _mimetypeBytes));
    for (final file in archive.files) {
      if (file.name.isEmpty || file.name == 'mimetype' || !file.isFile) {
        continue;
      }
      output.addFile(
        ArchiveFile.bytes(file.name, _normalizedContent(file))
          ..compression = file.compression,
      );
    }
    await File(outputPath).writeAsBytes(ZipEncoder().encodeBytes(output));
  }

  static Future<void> packStreaming({
    required Iterable<ArchiveFile> files,
    required String outputPath,
  }) async {
    final destination = File(outputPath).absolute;
    final temporary = await destination.parent.createTemp('.epub-pack-');
    OutputFileStream? output;
    try {
      final staged = File('${temporary.path}/output.epub');
      output = OutputFileStream(staged.path);
      final encoder = ZipEncoder()..startEncode(output);
      encoder.add(ArchiveFile.noCompress('mimetype', 20, _mimetypeBytes));
      final written = <String>{};
      for (final file in files) {
        if (file.name.isEmpty || !file.isFile || !written.add(file.name)) {
          continue;
        }
        if (file.name == 'mimetype') {
          _validateMimetype(file);
        } else if (_isHtmlFile(file.name)) {
          encoder.add(
            ArchiveFile.bytes(file.name, _normalizedContent(file))
              ..compression = file.compression,
          );
        } else {
          encoder.add(file, autoClose: false);
        }
      }
      encoder.endEncode();
      output.closeSync();
      output = null;
      await staged.rename(destination.path);
    } finally {
      output?.closeSync();
      await temporary.delete(recursive: true);
    }
  }

  static void _validateMimetype(ArchiveFile file) {
    final content = utf8.decode(file.content);
    if (content.replaceAll('\uFEFF', '').trim() != 'application/epub+zip') {
      throw StateError('EPUB 打包失败：mimetype 内容无效: $content');
    }
  }

  static List<int> _normalizedContent(ArchiveFile file) {
    final content = file.content;
    if (!_isHtmlFile(file.name)) return content;
    try {
      final text = utf8.decode(content);
      if (_isAlreadyNormalizedXhtml(text)) return content;
      final normalized = _normalizeXhtml(text);
      return normalized == text ? content : utf8.encode(normalized);
    } on FormatException {
      return content;
    }
  }

  static bool _isHtmlFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  static bool _isAlreadyNormalizedXhtml(String text) {
    return text.startsWith('<?xml') &&
        text.contains('xmlns="http://www.w3.org/1999/xhtml"') &&
        text.contains('<!DOCTYPE html') &&
        text.contains('<head') &&
        text.contains('<body') &&
        text.contains('</head>') &&
        text.contains('</body>');
  }

  static String _normalizeXhtml(String input) {
    var text = input.replaceFirst('\uFEFF', '').trimLeft();
    final withoutDeclaration = text
        .replaceFirst(
          RegExp(r'^\s*<\?xml[^>]*\?>\s*', caseSensitive: false),
          '',
        )
        .trimLeft();
    if (withoutDeclaration.toLowerCase().startsWith('<svg')) {
      return _ensureXmlDeclaration(text);
    }
    final hasHtml = RegExp(
      r'<html(?:\s|>)',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasHtml) {
      final withoutComments = text
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
          .trimLeft();
      if (withoutComments.toLowerCase().startsWith('<svg')) {
        return _ensureXmlDeclaration(text);
      }
      text =
          '<html xmlns="http://www.w3.org/1999/xhtml">\n'
          '<head><title></title></head>\n'
          '<body>\n$text\n</body>\n</html>';
    } else {
      text = _ensureHtmlNamespace(text);
      text = _ensureHead(text);
      text = _ensureBody(text);
    }
    return _ensureXmlDeclaration(_ensureDoctype(text));
  }

  static String _ensureHtmlNamespace(String text) {
    final htmlOpen = RegExp(
      r'<html\b([^>]*)>',
      caseSensitive: false,
    ).firstMatch(text);
    if (htmlOpen == null || htmlOpen.group(0)!.contains('xmlns=')) {
      return text;
    }
    return text.replaceFirstMapped(
      RegExp(r'<html\b([^>]*)>', caseSensitive: false),
      (match) => '<html${match.group(1)} xmlns="http://www.w3.org/1999/xhtml">',
    );
  }

  static String _ensureHead(String text) {
    if (RegExp(r'<head(?:\s|>)', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    return text.replaceFirstMapped(
      RegExp(r'<html\b[^>]*>', caseSensitive: false),
      (match) => '${match.group(0)}\n<head><title></title></head>',
    );
  }

  static String _ensureBody(String text) {
    if (RegExp(r'<body(?:\s|>)', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    final headEnd = RegExp(
      r'</head\s*>',
      caseSensitive: false,
    ).firstMatch(text);
    final htmlEnd = RegExp(
      r'</html\s*>',
      caseSensitive: false,
    ).firstMatch(text);
    if (headEnd == null || htmlEnd == null || headEnd.end > htmlEnd.start) {
      return text.replaceFirst(
        RegExp(r'</html\s*>', caseSensitive: false),
        '<body></body>\n</html>',
      );
    }
    final beforeBody = text.substring(0, headEnd.end);
    final bodyContent = text.substring(headEnd.end, htmlEnd.start).trim();
    final afterHtml = text.substring(htmlEnd.end);
    return '$beforeBody\n<body>\n$bodyContent\n</body>\n</html>$afterHtml';
  }

  static String _ensureXmlDeclaration(String text) {
    if (text.startsWith('<?xml')) return text;
    return '<?xml version="1.0" encoding="utf-8"?>\n$text';
  }

  static String _ensureDoctype(String text) {
    if (RegExp(r'<!DOCTYPE\s+html', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    const doctype =
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n'
        '  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">';
    if (text.startsWith('<?xml')) {
      return text.replaceFirstMapped(
        RegExp(r'(<\?xml[^>]*\?>)\s*', caseSensitive: false),
        (match) => '${match.group(1)}\n$doctype\n',
      );
    }
    return '$doctype\n$text';
  }
}
