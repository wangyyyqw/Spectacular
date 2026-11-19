import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import '../../core/epub_packer.dart';
import 'epub_image_helper.dart';

class ManifestItem {
  final String id;
  final String href;
  final String mediaType;

  ManifestItem(this.id, this.href, this.mediaType);
}

class EncryptDecryptBase {
  EncryptDecryptBase._();

  static final _illegalChars = RegExp(r'[\\/*?"<>|:]');
  static const _nameMapPath = 'META-INF/epub-toolkit-names.json';
  static const zhangyueDrm = 'zhangyue_drm';
  static const encrypted = 'encrypted';
  static const notEncrypted = 'not_encrypted';
  static const _textExtensions = {
    '.html',
    '.xhtml',
    '.htm',
    '.css',
    '.ncx',
    '.opf',
    '.svg',
    '.smil',
    '.xml',
  };

  static List<ManifestItem> parseManifest(String opfContent) {
    final document = xml.XmlDocument.parse(opfContent);
    return [
      for (final item in document.findAllElements('item', namespaceUri: '*'))
        if ((item.getAttribute('id') ?? '').isNotEmpty &&
            (item.getAttribute('href') ?? '').isNotEmpty)
          ManifestItem(
            item.getAttribute('id')!,
            _decodeHref(item.getAttribute('href')!),
            item.getAttribute('media-type') ?? '',
          ),
    ];
  }

  static bool isEncrypted(String opfContent) => parseManifest(opfContent).any(
    (item) =>
        _illegalChars.hasMatch(p.posix.basename(_withoutSuffix(item.href))),
  );

  static bool checkZhangyueDrm(Archive archive) {
    final file = archive.findFile('META-INF/encryption.xml');
    return file != null &&
        utf8
            .decode(EpubImageHelper.readBytes(file))
            .toLowerCase()
            .contains('zhangyue');
  }

  static String obfuscateName(String id, String href) {
    var number = BigInt.zero;
    for (final byte in md5.convert(utf8.encode(id)).bytes) {
      number = (number << 8) | BigInt.from(byte);
    }
    final binary = number
        .toRadixString(2)
        .replaceAll('1', '*')
        .replaceAll('0', ':');
    final extension = p.posix.extension(_withoutSuffix(href)).toLowerCase();
    return '_$binary${href.toLowerCase().contains('~slim') ? '~slim' : ''}$extension';
  }

  static String deobfuscateName(String id, String href) {
    final extension = p.posix.extension(_withoutSuffix(href)).toLowerCase();
    final slim = href.toLowerCase().contains('~slim') ? '~slim' : '';
    final name = _illegalChars.hasMatch(id)
        ? md5.convert(utf8.encode(id)).toString()
        : id;
    final idExtension = p.posix.extension(id).toLowerCase();
    return _isValidExt(idExtension) ? '$name$slim' : '$name$slim$extension';
  }

  static bool _isValidExt(String extension) => const {
    '.html',
    '.xhtml',
    '.htm',
    '.css',
    '.js',
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.svg',
    '.webp',
    '.bmp',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.mp3',
    '.mp4',
    '.wav',
    '.ogg',
    '.ncx',
    '.opf',
    '.xml',
    '.txt',
  }.contains(extension);

  static String targetDir(String fileName, String mediaType) {
    final lowerName = fileName.toLowerCase();
    if (lowerName == 'mimetype' || lowerName.startsWith('meta-inf/')) return '';
    final extension = p.posix.extension(lowerName);
    if (extension == '.opf' || extension == '.ncx') return 'OEBPS/';
    if ({'.html', '.xhtml', '.htm'}.contains(extension) ||
        mediaType.contains('html')) {
      return 'OEBPS/Text/';
    }
    if (extension == '.css' || mediaType.contains('css')) {
      return 'OEBPS/Styles/';
    }
    if ({
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.svg',
          '.webp',
          '.bmp',
        }.contains(extension) ||
        mediaType.startsWith('image/')) {
      return 'OEBPS/Images/';
    }
    if ({'.ttf', '.otf', '.woff', '.woff2'}.contains(extension) ||
        mediaType.contains('font')) {
      return 'OEBPS/Fonts/';
    }
    if ({'.mp3', '.wav', '.ogg', '.aac'}.contains(extension) ||
        mediaType.startsWith('audio/')) {
      return 'OEBPS/Audio/';
    }
    if ({'.mp4', '.webm', '.avi'}.contains(extension) ||
        mediaType.startsWith('video/')) {
      return 'OEBPS/Video/';
    }
    return 'OEBPS/Misc/';
  }

  static Map<String, String> buildHrefMap(
    List<ManifestItem> items,
    String mode,
  ) {
    _validateMode(mode);
    final result = <String, String>{};
    for (final item in items) {
      final oldPath = _withoutSuffix(item.href);
      final name = mode == 'encrypt'
          ? obfuscateName(item.id, oldPath)
          : deobfuscateName(item.id, oldPath);
      result[oldPath] = p.posix.join(p.posix.dirname(oldPath), name);
      result[p.posix.basename(oldPath)] = name;
    }
    return result;
  }

  static String rewriteOpfManifest(
    String opfContent,
    Map<String, String> hrefMap,
  ) {
    final document = xml.XmlDocument.parse(opfContent);
    for (final item in document.findAllElements('item', namespaceUri: '*')) {
      final rawHref = item.getAttribute('href');
      if (rawHref == null) continue;
      final href = _decodeHref(_withoutSuffix(rawHref));
      final replacement =
          hrefMap[href] ??
          (hrefMap[p.posix.basename(href)] == null
              ? null
              : p.posix.join(
                  p.posix.dirname(href),
                  hrefMap[p.posix.basename(href)]!,
                ));
      if (replacement != null) {
        item.setAttribute(
          'href',
          '${_encodePath(replacement)}${_suffix(rawHref)}',
        );
      }
    }
    return document.toXmlString();
  }

  static void rewriteReferences(
    Archive archive,
    Map<String, String> hrefMap,
    String opfPath,
  ) {
    final pathMap = <String, String>{};
    for (final file in archive.files) {
      final relative = p.posix.relative(
        file.name,
        from: p.posix.dirname(opfPath),
      );
      final replacement = hrefMap[relative];
      final basename = hrefMap[p.posix.basename(file.name)];
      if (replacement != null) {
        pathMap[file.name] = p.posix.normalize(
          p.posix.join(p.posix.dirname(opfPath), replacement),
        );
      } else if (basename != null) {
        pathMap[file.name] = p.posix.join(p.posix.dirname(file.name), basename);
      }
    }
    final updated = _rewriteArchive(archive, pathMap, rename: false);
    archive.clearSync();
    for (final file in updated.files) {
      archive.addFile(file);
    }
  }

  static Future<String> process({
    required String epubPath,
    required String outputPath,
    required String mode,
  }) async {
    _validateMode(mode);
    final archive = await EpubImageHelper.readArchive(epubPath);
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) throw const FormatException('找不到 OPF 文件');
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw const FormatException('无法读取 OPF 文件');
    final opf = utf8.decode(EpubImageHelper.readBytes(opfFile));
    if (mode == 'decrypt' && checkZhangyueDrm(archive)) return zhangyueDrm;
    final hasEncryption = isEncrypted(opf);
    if (mode == 'encrypt' && hasEncryption) return encrypted;
    if (mode == 'decrypt' && !hasEncryption) return notEncrypted;
    final pathMap = mode == 'decrypt' && archive.findFile(_nameMapPath) != null
        ? _readNameMap(archive)
        : _manifestPathMap(archive, opfPath, parseManifest(opf), mode);
    _checkPathMap(archive, pathMap);
    final output = _rewriteArchive(archive, pathMap);
    if (mode == 'encrypt') _addNameMap(archive, output, pathMap);
    await EpubPacker.pack(archive: output, outputPath: outputPath);
    return '${mode == 'encrypt' ? '加密' : '解密'}完成: 处理 ${pathMap.length} 个资源\n'
        '输出文件: $outputPath';
  }

  static void _addNameMap(
    Archive source,
    Archive output,
    Map<String, String> pathMap,
  ) {
    if (source.findFile(_nameMapPath) != null) {
      throw StateError('EPUB 已有名称还原信息，未覆盖该文件');
    }
    final mappingBytes = utf8.encode(
      jsonEncode({for (final entry in pathMap.entries) entry.value: entry.key}),
    );
    output.addFile(
      ArchiveFile(_nameMapPath, mappingBytes.length, mappingBytes),
    );
  }

  static Map<String, String> _manifestPathMap(
    Archive archive,
    String opfPath,
    List<ManifestItem> items,
    String mode,
  ) {
    final result = <String, String>{};
    for (final item in items) {
      final oldPath = _resourcePath(opfPath, item.href);
      if (oldPath == null || archive.findFile(oldPath) == null) continue;
      final newName = mode == 'encrypt'
          ? obfuscateName(item.id, item.href)
          : deobfuscateName(item.id, item.href);
      result[oldPath] = p.posix.join(p.posix.dirname(oldPath), newName);
    }
    return result;
  }

  static Map<String, String> _readNameMap(Archive archive) {
    final decoded = jsonDecode(
      utf8.decode(EpubImageHelper.readBytes(archive.findFile(_nameMapPath)!)),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('名称还原信息格式无效');
    }
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.value is! String || archive.findFile(entry.key) == null) {
        throw const FormatException('名称还原信息与 EPUB 资源不匹配');
      }
      result[entry.key] = entry.value as String;
    }
    return result;
  }

  static void _checkPathMap(Archive archive, Map<String, String> pathMap) {
    if (pathMap.isEmpty) throw const FormatException('没有可处理的本地 manifest 资源');
    final targets = <String>{};
    for (final entry in pathMap.entries) {
      if (!targets.add(entry.value) ||
          (entry.value != entry.key &&
              archive.findFile(entry.value) != null &&
              !pathMap.containsKey(entry.value))) {
        throw StateError('名称混淆会覆盖已有资源: ${entry.value}');
      }
    }
  }

  static Archive _rewriteArchive(
    Archive archive,
    Map<String, String> pathMap, {
    bool rename = true,
  }) {
    final output = Archive()..comment = archive.comment;
    for (final file in archive.files) {
      if (rename && file.name == _nameMapPath) continue;
      final newName = rename ? pathMap[file.name] ?? file.name : file.name;
      var data = EpubImageHelper.readBytes(file);
      if (_textExtensions.contains(
        p.posix.extension(file.name).toLowerCase(),
      )) {
        data = utf8.encode(_rewriteText(utf8.decode(data), file.name, pathMap));
      }
      output.addFile(
        ArchiveFile(newName, data.length, data)
          ..compression = file.compression
          ..isFile = file.isFile,
      );
    }
    return output;
  }

  static String _rewriteText(
    String content,
    String source,
    Map<String, String> pathMap,
  ) {
    final attributes = RegExp(
      r'''(\b(?:href|xlink:href|src|poster|data|full-path)\s*=\s*)(["'])(.*?)\2''',
      caseSensitive: false,
    );
    final result = content.replaceAllMapped(attributes, (match) {
      final reference = _rewriteReference(match.group(3)!, source, pathMap);
      return '${match.group(1)}${match.group(2)}$reference${match.group(2)}';
    });
    return _rewriteCssReferences(result, source, pathMap);
  }

  static String _rewriteCssReferences(
    String content,
    String source,
    Map<String, String> pathMap,
  ) {
    final references = RegExp(
      r'''(url\(\s*["']?)([^"')]*?)(["']?\s*\))|(@import\s+)(["'])(.*?)\5''',
      caseSensitive: false,
    );
    return content.replaceAllMapped(references, (match) {
      if (match.group(2) != null) {
        return '${match.group(1)}'
            '${_rewriteReference(match.group(2)!, source, pathMap)}${match.group(3)}';
      }
      return '${match.group(4)}${match.group(5)}'
          '${_rewriteReference(match.group(6)!, source, pathMap)}${match.group(5)}';
    });
  }

  static String _rewriteReference(
    String reference,
    String source,
    Map<String, String> pathMap,
  ) {
    final oldPath = _resourcePath(source, reference);
    final newPath = pathMap[oldPath];
    if (newPath == null) return reference;
    final relative = p.posix.relative(newPath, from: p.posix.dirname(source));
    return '${_encodePath(relative)}${_suffix(reference)}';
  }

  static String? _resourcePath(String source, String reference) {
    final value = reference.trim();
    if (value.isEmpty || value.startsWith('#')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    final decoded = _decodeHref(_withoutSuffix(value));
    return p.posix.normalize(
      decoded.startsWith('/')
          ? decoded.substring(1)
          : p.posix.join(p.posix.dirname(source), decoded),
    );
  }

  static String _decodeHref(String href) => href.replaceAllMapped(
    RegExp(r'(?:%[0-9a-fA-F]{2})+'),
    (match) => Uri.decodeComponent(match.group(0)!),
  );

  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static String _withoutSuffix(String value) =>
      value.split(RegExp(r'[?#]')).first;

  static String _suffix(String value) {
    final index = value.indexOf(RegExp(r'[?#]'));
    return index < 0 ? '' : value.substring(index);
  }

  static void _validateMode(String mode) {
    if (mode != 'encrypt' && mode != 'decrypt') {
      throw ArgumentError.value(mode, 'mode', '仅支持 encrypt 或 decrypt');
    }
  }
}
