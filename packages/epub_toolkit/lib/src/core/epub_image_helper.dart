import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_packer.dart';

class EpubImageHelper {
  EpubImageHelper._();

  static const compressExts = [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.gif',
  ];

  static const webpConvertExts = ['.jpg', '.jpeg', '.png', '.bmp'];

  static const mimeMap = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
    '.gif': 'image/gif',
  };

  static String sizeStr(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }

  static Future<Archive> readArchive(String epubPath) async {
    return ZipDecoder().decodeBytes(await File(epubPath).readAsBytes());
  }

  static String? findOpfPath(Archive archive) {
    final container = archive.findFile('META-INF/container.xml');
    if (container != null) {
      try {
        final document = XmlDocument.parse(
          utf8.decode(container.content, allowMalformed: true),
        );
        for (final rootfile in document.findAllElements(
          'rootfile',
          namespaceUri: '*',
        )) {
          final fullPath = rootfile.getAttribute('full-path');
          if (fullPath == null || fullPath.isEmpty) continue;
          final path = p.posix.normalize(fullPath);
          if (archive.findFile(path) != null) return path;
          final decoded = Uri.decodeFull(path);
          if (archive.findFile(decoded) != null) return decoded;
        }
      } on XmlException {
        return _firstOpfPath(archive);
      } on FormatException {
        return _firstOpfPath(archive);
      }
    }
    return _firstOpfPath(archive);
  }

  static String? _firstOpfPath(Archive archive) {
    for (final file in archive.files) {
      if (file.isFile && file.name.toLowerCase().endsWith('.opf')) {
        return file.name;
      }
    }
    return null;
  }

  static String opfDir(String opfPath) {
    final index = opfPath.lastIndexOf('/');
    return index >= 0 ? opfPath.substring(0, index + 1) : '';
  }

  static String encodeHref(String href) {
    final separator = href.indexOf(RegExp(r'[?#]'));
    if (separator < 0) return Uri.encodeFull(href);
    return '${Uri.encodeFull(href.substring(0, separator))}${href.substring(separator)}';
  }

  static List<ArchiveFile> findImages(
    Archive archive,
    List<String> extensions,
  ) {
    return archive.files.where((file) {
      if (!file.isFile || file.name.isEmpty) return false;
      final lowerName = file.name.toLowerCase();
      return extensions.any(lowerName.endsWith);
    }).toList();
  }

  static Uint8List readBytes(ArchiveFile file) => file.content;

  static Future<void> saveArchive(
    Archive archive,
    String outputPath, {
    Map<String, String>? renameMap,
  }) async {
    if (renameMap != null && renameMap.isNotEmpty) {
      _updateReferences(archive, renameMap);
    }
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
  }

  static void addOrReplaceFile(Archive archive, ArchiveFile newFile) {
    archive.addFile(newFile);
  }

  static Archive addOrReplaceFileSafe(Archive archive, ArchiveFile newFile) {
    archive.addFile(newFile);
    return archive;
  }

  static void replaceFile(
    Archive archive,
    String oldName,
    String newName,
    Uint8List data,
  ) {
    final replacement = ArchiveFile.bytes(newName, data);
    for (var index = 0; index < archive.files.length; index++) {
      if (archive.files[index].name == oldName) {
        archive[index] = replacement;
        return;
      }
    }
    archive.addFile(replacement);
  }

  static Archive removeFiles(Archive archive, Set<String> namesToRemove) {
    final output = Archive()..comment = archive.comment;
    for (final file in archive.files) {
      if (file.name.isNotEmpty && !namesToRemove.contains(file.name)) {
        output.addFile(file);
      }
    }
    return output;
  }

  static void _updateReferences(
    Archive archive,
    Map<String, String> renameMap,
  ) {
    final paths = {
      for (final entry in renameMap.entries)
        p.posix.normalize(entry.key): p.posix.normalize(entry.value),
    };
    final files = archive.files.where((file) {
      final extension = p.posix.extension(file.name).toLowerCase();
      return file.isFile &&
          const [
            '.opf',
            '.xhtml',
            '.html',
            '.htm',
            '.css',
            '.ncx',
            '.svg',
          ].contains(extension);
    }).toList();
    for (final file in files) {
      final original = utf8.decode(file.content);
      final extension = p.posix.extension(file.name).toLowerCase();
      final content = switch (extension) {
        '.opf' => _updatePackageReferences(original, file.name, paths),
        '.css' => _updateCssReferences(original, file.name, paths),
        _ => _updateMarkupReferences(original, file.name, paths),
      };
      if (content != original) {
        archive.addFile(ArchiveFile.string(file.name, content));
      }
    }
  }

  static String _updatePackageReferences(
    String content,
    String sourcePath,
    Map<String, String> renameMap,
  ) {
    final document = XmlDocument.parse(content);
    var modified = false;
    for (final element in document.descendants.whereType<XmlElement>()) {
      for (final attribute in element.attributes.toList()) {
        if (!const ['href', 'src'].contains(attribute.name.local)) continue;
        final renamed = _renamedReference(
          attribute.value,
          sourcePath,
          renameMap,
        );
        if (renamed == null) continue;
        attribute.value = renamed;
        if (element.name.local == 'item' && attribute.name.local == 'href') {
          final newExtension = p.posix
              .extension(renamed.split(RegExp(r'[?#]')).first)
              .toLowerCase();
          final newMime = mimeMap[newExtension];
          if (newMime != null) element.setAttribute('media-type', newMime);
        }
        modified = true;
      }
    }
    return modified ? document.toXmlString() : content;
  }

  static String _updateMarkupReferences(
    String content,
    String sourcePath,
    Map<String, String> renameMap,
  ) {
    final updated = content.replaceAllMapped(
      RegExp(
        r"""<!--[\s\S]*?-->|<[A-Za-z_][\w:.-]*(?:[^>"']|"[^"]*"|'[^']*')*>""",
      ),
      (match) => match.group(0)!.startsWith('<!--')
          ? match.group(0)!
          : _updateTagReferences(match.group(0)!, sourcePath, renameMap),
    );
    return updated.replaceAllMapped(
      RegExp(
        r'<!--[\s\S]*?-->|(<style\b[^>]*>)([\s\S]*?)(</style\s*>)',
        caseSensitive: false,
      ),
      (match) => match.group(1) == null
          ? match.group(0)!
          : '${match.group(1)}${_updateCssReferences(match.group(2)!, sourcePath, renameMap)}${match.group(3)}',
    );
  }

  static String _updateTagReferences(
    String tag,
    String sourcePath,
    Map<String, String> renameMap,
  ) {
    return tag.replaceAllMapped(
      RegExp(
        r'''(\s(?:href|src|xlink:href|poster|data|background|style)\s*=\s*)(["'])(.*?)\2''',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final prefix = match.group(1)!;
        final quote = match.group(2)!;
        final value = match.group(3)!;
        final updated = prefix.trimLeft().toLowerCase().startsWith('style')
            ? _updateCssReferences(value, sourcePath, renameMap)
            : _renamedReference(value, sourcePath, renameMap);
        return updated == null
            ? match.group(0)!
            : '$prefix$quote$updated$quote';
      },
    );
  }

  static String _updateCssReferences(
    String content,
    String sourcePath,
    Map<String, String> renameMap,
  ) {
    final updated = content.replaceAllMapped(
      RegExp(
        r'''/\*[\s\S]*?\*/|\burl\(\s*(["']?)(.*?)\1\s*\)''',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        if (match.group(1) == null) return match.group(0)!;
        final renamed = _renamedReference(
          match.group(2)!,
          sourcePath,
          renameMap,
        );
        return renamed == null
            ? match.group(0)!
            : 'url(${match.group(1)}$renamed${match.group(1)})';
      },
    );
    return updated.replaceAllMapped(
      RegExp(
        r'''/\*[\s\S]*?\*/|(@import\s+)(["'])(.*?)\2''',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        if (match.group(1) == null) return match.group(0)!;
        final renamed = _renamedReference(
          match.group(3)!,
          sourcePath,
          renameMap,
        );
        return renamed == null
            ? match.group(0)!
            : '${match.group(1)}${match.group(2)}$renamed${match.group(2)}';
      },
    );
  }

  static String? _renamedReference(
    String reference,
    String sourcePath,
    Map<String, String> renameMap,
  ) {
    final value = reference.trim();
    if (value.isEmpty ||
        value.startsWith('//') ||
        value.startsWith('#') ||
        value.startsWith('?') ||
        RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value)) {
      return null;
    }
    final separator = value.indexOf(RegExp(r'[?#]'));
    final referencePath = separator < 0 ? value : value.substring(0, separator);
    final suffix = separator < 0 ? '' : value.substring(separator);
    final decoded = referencePath.replaceAllMapped(
      RegExp(r'(?:%[0-9a-fA-F]{2})+'),
      (match) => Uri.decodeComponent(match.group(0)!),
    );
    final sourceDirectory = p.posix.dirname(sourcePath);
    final rootRelative = decoded.startsWith('/');
    final resolved = p.posix.normalize(
      rootRelative
          ? decoded.substring(1)
          : p.posix.join(sourceDirectory, decoded),
    );
    final renamed = renameMap[resolved];
    if (renamed == null) return null;
    final relative = rootRelative
        ? '/$renamed'
        : p.posix.relative(renamed, from: sourceDirectory);
    return '${relative.split('/').map(Uri.encodeComponent).join('/')}$suffix';
  }
}
