import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/api.dart';
import 'package:xml/xml.dart';

import 'book_source_models.dart';

/// 对现有在线 EPUB 只追加新章，原章节文件、样式、资源和标识保持原值。
class OnlineEpubUpdate {
  OnlineEpubUpdate._(this.bytes, this.opfPath, this.chapters);

  final Uint8List bytes;
  final String opfPath;
  final List<Map<String, String>> chapters;

  static Future<OnlineEpubUpdate> open(String path) async {
    final bytes = await File(path).readAsBytes();
    final opened = await openEpub(bytes, verifyCrc: false);
    final document = opened.document;
    if (document == null) throw const BookSourceException('本地 EPUB 无法打开');
    try {
      final dir = p.posix.dirname(document.opfPath);
      final stored = document.archive.readString('$dir/online_chapters.json');
      final rows = <Map<String, String>>[];
      if (stored != null) {
        final json = jsonDecode(stored) as Map;
        for (final row
            in (json['chapters'] as List).whereType<Map<Object?, Object?>>()) {
          rows.add({
            for (final item in row.entries) '${item.key}': '${item.value}',
          });
        }
      } else {
        // 旧下载包无源章节索引，沿用参考项目按原目录标题匹配一次。
        final titles = <int, String>{};
        void visit(List<TocEntry> entries) {
          for (final entry in entries) {
            titles.putIfAbsent(entry.spineIndex, () => entry.title);
            visit(entry.children);
          }
        }

        visit(document.toc);
        for (var index = 0; index < document.spine.length; index++) {
          final item = document.spine[index];
          if (item.href.endsWith('cover.xhtml') ||
              item.properties.contains('cover-image')) {
            continue;
          }
          final title = titles[index];
          if (title == null) throw const BookSourceException('本地章节缺少目录标题');
          rows.add({
            'href': item.href,
            'title': title,
            'url': '',
            'volume': '',
          });
        }
      }
      if (rows.isEmpty) throw const BookSourceException('本地章节索引为空');
      return OnlineEpubUpdate._(bytes, document.opfPath, rows);
    } finally {
      document.archive.close();
    }
  }

  /// URL 身份优先，旧包按标题匹配；失配、重排或目录缩短时保留原书。
  List<OnlineChapter> newChapters(List<OnlineChapter> remote) {
    if (remote.length < chapters.length) {
      throw const BookSourceException('远端目录少于本地章节，已停止更新');
    }
    for (var index = 0; index < chapters.length; index++) {
      final stored = chapters[index];
      final latest = remote[index];
      final url = stored['url'] ?? '';
      final matches = url.isNotEmpty
          ? _chapterKey(url) == _chapterKey(latest.url)
          : (stored['title'] ?? '').trim() == latest.title.trim();
      if (!matches) {
        throw const BookSourceException('目录身份或顺序发生变化，已停止更新以保留原有正文');
      }
    }
    return remote.sublist(chapters.length);
  }

  Uint8List append(Uint8List downloaded, List<OnlineChapter> remote) {
    final original = ZipDecoder().decodeBytes(bytes);
    final incoming = ZipDecoder().decodeBytes(downloaded);
    final dir = p.posix.dirname(opfPath);
    final prefix = 'updates/chapters_${chapters.length}_${remote.length}';
    final replacements = <String, String>{};
    String read(Archive archive, String path) =>
        utf8.decode(archive.findFile(path)!.content as List<int>);
    final opf = XmlDocument.parse(read(original, opfPath));
    final nextOpf = XmlDocument.parse(read(incoming, 'OEBPS/content.opf'));
    XmlElement element(XmlDocument doc, String name) => doc.descendants
        .whereType<XmlElement>()
        .firstWhere((node) => node.name.local == name);
    final manifest = element(opf, 'manifest');
    final newManifest = element(nextOpf, 'manifest');
    final idPrefix = 'online_${chapters.length}_';
    for (final item in newManifest.childElements) {
      if (item.getAttribute('properties') == 'nav' ||
          item.getAttribute('id') == 'ncx' ||
          item.getAttribute('id') == 'online-index' ||
          item.getAttribute('id') == 'cover-page') {
        continue;
      }
      final copy = item.copy();
      copy.setAttribute('id', '$idPrefix${item.getAttribute('id')}');
      copy.setAttribute('href', '$prefix/${item.getAttribute('href')}');
      copy.removeAttribute('properties');
      manifest.children.add(copy);
    }
    if (!manifest.childElements.any(
      (item) => item.getAttribute('href') == 'online_chapters.json',
    )) {
      manifest.children.add(
        XmlElement(XmlName.parts('item', prefix: manifest.name.prefix), [
          XmlAttribute(XmlName.parts('id'), 'online-index'),
          XmlAttribute(XmlName.parts('href'), 'online_chapters.json'),
          XmlAttribute(XmlName.parts('media-type'), 'application/json'),
        ]),
      );
    }
    final spine = element(opf, 'spine');
    for (final item in element(nextOpf, 'spine').childElements) {
      if (item.getAttribute('idref') == 'cover-page') continue;
      final copy = item.copy();
      copy.setAttribute('idref', '$idPrefix${item.getAttribute('idref')}');
      spine.children.add(copy);
    }
    replacements[opfPath] = opf.toXmlString();
    // 原生下载包同时包含 NAV 和 NCX，两份目录同步追加。
    for (final item in manifest.childElements.toList()) {
      final href = item.getAttribute('href') ?? '';
      final path = p.posix.normalize('$dir/$href');
      final isNav = (item.getAttribute('properties') ?? '')
          .split(' ')
          .contains('nav');
      final isNcx =
          item.getAttribute('media-type') == 'application/x-dtbncx+xml';
      if (!isNav && !isNcx) continue;
      final doc = XmlDocument.parse(read(original, path));
      final next = XmlDocument.parse(
        read(incoming, isNav ? 'OEBPS/nav.xhtml' : 'OEBPS/toc.ncx'),
      );
      if (isNav) {
        final nav = doc.descendants.whereType<XmlElement>().firstWhere(
          (node) =>
              node.name.local == 'nav' &&
              node.attributes.any(
                (attr) => attr.name.local == 'type' && attr.value == 'toc',
              ),
        );
        final list = nav.descendants.whereType<XmlElement>().firstWhere(
          (node) => node.name.local == 'ol',
        );
        for (final li in element(next, 'ol').childElements) {
          final copy = li.copy();
          for (final anchor in copy.descendants.whereType<XmlElement>().where(
            (node) => node.name.local == 'a',
          )) {
            anchor.setAttribute(
              'href',
              p.posix.relative(
                '$dir/$prefix/${anchor.getAttribute('href')}',
                from: p.posix.dirname(path),
              ),
            );
          }
          list.children.add(copy);
        }
      } else {
        final map = element(doc, 'navMap');
        final count = map.childElements.length;
        var offset = 0;
        for (final point in element(next, 'navMap').childElements) {
          final copy = point.copy();
          copy.setAttribute('id', '$idPrefix${point.getAttribute('id')}');
          copy.setAttribute('playOrder', '${count + ++offset}');
          for (final content in copy.descendants.whereType<XmlElement>().where(
            (node) => node.name.local == 'content',
          )) {
            content.setAttribute(
              'src',
              p.posix.relative(
                '$dir/$prefix/${content.getAttribute('src')}',
                from: p.posix.dirname(path),
              ),
            );
          }
          map.children.add(copy);
        }
      }
      replacements[path] = doc.toXmlString();
    }
    final nextIndex =
        jsonDecode(read(incoming, 'OEBPS/online_chapters.json')) as Map;
    final upgraded = [
      for (var index = 0; index < chapters.length; index++)
        {
          ...chapters[index],
          'url': remote[index].url,
          'volume': remote[index].volume,
        },
      for (final item
          in (nextIndex['chapters'] as List).whereType<Map<Object?, Object?>>())
        {...item, 'href': '$prefix/${item['href']}'},
    ];
    replacements['$dir/online_chapters.json'] = jsonEncode({
      'version': 1,
      'chapters': upgraded,
    });
    final output = Archive();
    for (final file in original.files) {
      if (replacements.containsKey(file.name)) continue;
      output.addFile(ArchiveFile(file.name, file.size, file.content));
    }
    for (final entry in replacements.entries) {
      final data = utf8.encode(entry.value);
      output.addFile(ArchiveFile(entry.key, data.length, data));
    }
    for (final file in incoming.files) {
      if (!file.isFile || !file.name.startsWith('OEBPS/')) continue;
      final target = '$dir/$prefix/${file.name.substring(6)}';
      if (original.findFile(target) != null) {
        throw const BookSourceException('新增章节资源路径冲突，已停止更新');
      }
      output.addFile(ArchiveFile(target, file.size, file.content));
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(output));
  }
}

String _chapterKey(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  for (final name in ['chapter_id', 'chapterId', 'cid', 'chapterid']) {
    if (uri.queryParameters[name]?.isNotEmpty ?? false) {
      return '$name:${uri.queryParameters[name]}';
    }
  }
  return uri.replace(fragment: '').toString();
}
