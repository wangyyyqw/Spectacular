import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/toc.dart';
import 'package:reader_core/api.dart';
import 'package:xml/xml.dart';

import 'book_source_models.dart';
import 'online_chapter_request.dart';
import 'online_epub_metadata.dart';

/// 将新增章节合入远端目录对应位置，保留原章节文件、样式、资源和标识。
class OnlineEpubUpdate {
  /// 按需书转为完整 EPUB 时保留原 OPF 身份，避免更换书架主键。
  static Future<Uint8List> preserveBookIdentity(
    String path,
    Uint8List bytes,
  ) async {
    final opened = await openEpub(
      await File(path).readAsBytes(),
      verifyCrc: false,
    );
    final document = opened.document;
    if (document == null) throw const BookSourceException('原书身份无法读取');
    try {
      final oldOpf = XmlDocument.parse(
        document.archive.readString(document.opfPath)!,
      );
      final incoming = ZipDecoder().decodeBytes(bytes);
      final opfFile = incoming.findFile('OEBPS/content.opf')!;
      final newOpf = XmlDocument.parse(utf8.decode(opfFile.content));
      for (final name in const ['identifier', 'title', 'creator']) {
        final old = oldOpf.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == name)
            .firstOrNull;
        final target = newOpf.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == name)
            .firstOrNull;
        if (old != null && target != null) {
          target.children
            ..clear()
            ..add(XmlText(old.innerText));
        }
      }
      final text = utf8.encode(newOpf.toXmlString());
      incoming.addFile(ArchiveFile('OEBPS/content.opf', text.length, text));
      return Uint8List.fromList(ZipEncoder().encodeBytes(incoming));
    } finally {
      document.archive.close();
    }
  }

  OnlineEpubUpdate._(this.bytes, this.opfPath, this.chapters);

  final Uint8List bytes;
  final String opfPath;
  final List<Map<String, String>> chapters;

  static Future<List<Map<String, String>>> readChapterIndex(
    String path, {
    OnlineEpubMetadata? sourceMetadata,
    Uint8List? memoryBytes,
  }) async {
    final opened = memoryBytes == null
        ? await openEpubFile(File(path))
        : await openEpub(memoryBytes, verifyCrc: false);
    final document = opened.document;
    if (document == null) throw const BookSourceException('本地 EPUB 无法打开');
    try {
      return _chapterRows(document, sourceMetadata);
    } finally {
      document.archive.close();
    }
  }

  static Future<OnlineEpubUpdate> open(
    String path, {
    OnlineEpubMetadata? sourceMetadata,
  }) async {
    final bytes = await File(path).readAsBytes();
    final opened = await openEpub(bytes, verifyCrc: false);
    final document = opened.document;
    if (document == null) throw const BookSourceException('本地 EPUB 无法打开');
    try {
      return OnlineEpubUpdate._(
        bytes,
        document.opfPath,
        _chapterRows(document, sourceMetadata),
      );
    } finally {
      document.archive.close();
    }
  }

  static List<Map<String, String>> _chapterRows(
    EpubDocumentImpl document,
    OnlineEpubMetadata? sourceMetadata,
  ) {
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
    } else if (sourceMetadata != null) {
      for (final (index, chapter) in sourceMetadata.chapters.indexed) {
        final request = chapter.toChapter(index, sourceMetadata.detailUrl);
        rows.add({
          'href': p.posix.relative(chapter.href, from: dir),
          'title': chapter.title,
          'url': request.url,
          'volume': chapter.volume,
          'requestOptions': jsonEncode(request.requestOptions),
        });
      }
    } else {
      // 旧下载包无源章节索引，沿用参考项目按原目录标题匹配一次。
      final titles = <int, ({String title, String volume})>{};
      final headings = <int>{};
      void visit(List<TocEntry> entries, String volume) {
        for (final entry in entries) {
          if (entry.children.isEmpty) {
            titles[entry.spineIndex] = (title: entry.title, volume: volume);
          } else {
            headings.add(entry.spineIndex);
            visit(entry.children, entry.title);
          }
        }
      }

      final entries = switch (document.tocSource) {
        'nav' => TocFallback.parseNav(
          archive: document.archive,
          package: document.package,
          opfPath: document.opfPath,
          item: TocFallback.findNavItem(document.package)!,
        ).entries,
        'ncx' => TocParser.parseNcx(
          archive: document.archive,
          package: document.package,
          opfPath: document.opfPath,
        ).entries,
        _ => document.toc,
      };
      visit(entries, '');
      for (var index = 0; index < document.spine.length; index++) {
        final item = document.spine[index];
        if (item.href.endsWith('cover.xhtml') ||
            item.properties.contains('cover-image')) {
          continue;
        }
        final title = titles[index];
        if (title == null && headings.contains(index)) continue;
        if (title == null) throw const BookSourceException('本地章节缺少目录标题');
        rows.add({
          'href': item.href,
          'title': title.title,
          'url': '',
          'volume': title.volume,
        });
      }
    }
    if (rows.isEmpty) throw const BookSourceException('本地章节索引为空');
    return rows;
  }

  static Set<int> insertionIndices(
    List<Map<String, String>> stored,
    List<OnlineChapter> remote,
  ) {
    final added = <int>{};
    var cursor = 0;
    for (final (index, chapter) in remote.indexed) {
      if (cursor < stored.length && _matchesChapter(stored[cursor], chapter)) {
        cursor++;
      } else {
        added.add(index);
      }
    }
    if (cursor != stored.length) {
      throw const BookSourceException('目录身份或顺序发生变化，已停止更新以保留原有正文');
    }
    return added;
  }

  List<OnlineChapter> newChapters(List<OnlineChapter> remote) => [
    for (final index in insertionIndices(chapters, remote)) remote[index],
  ];

  Uint8List append(Uint8List downloaded, List<OnlineChapter> remote) {
    final additions = insertionIndices(chapters, remote);
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
    final manifestHrefs = {
      for (final item in manifest.childElements)
        item.getAttribute('id'): item.getAttribute('href'),
    };
    void merge(
      XmlElement root,
      Map<String, XmlElement> byHref,
      List<XmlElement> incomingNodes,
    ) {
      if (incomingNodes.length != additions.length) {
        throw const BookSourceException('新增章节与目录不一致，已停止更新');
      }
      var storedIndex = 0;
      var newIndex = 0;
      XmlElement? previous;
      for (final (index, chapter) in remote.indexed) {
        final next = storedIndex < chapters.length
            ? byHref[chapters[storedIndex]['href']]
            : null;
        if (!additions.contains(index)) {
          previous = next;
          storedIndex++;
          continue;
        }
        final node = incomingNodes[newIndex++];
        final samePrevious =
            index > 0 && remote[index - 1].volume == chapter.volume;
        final sameNext =
            storedIndex < chapters.length &&
            chapters[storedIndex]['volume'] == chapter.volume;
        final before =
            previous == null || (!samePrevious && sameNext && next != null);
        final neighbor = before ? next : previous;
        if (neighbor == null) {
          throw const BookSourceException('无法定位新增章节的目录位置，已停止更新');
        }
        var anchor = neighbor;
        if (!(before ? sameNext : samePrevious)) {
          while (anchor.parentElement != root) {
            anchor = anchor.parentElement!;
          }
        }
        final siblings = anchor.parentElement!.children;
        siblings.insert(siblings.indexOf(anchor) + (before ? 0 : 1), node);
        previous = node;
      }
    }

    merge(
      spine,
      {
        for (final item in spine.childElements)
          if (manifestHrefs[item.getAttribute('idref')] case final href?)
            p.posix.normalize(href): item,
      },
      [
        for (final item in element(nextOpf, 'spine').childElements)
          if (item.getAttribute('idref') != 'cover-page')
            item.copy()
              ..setAttribute('idref', '$idPrefix${item.getAttribute('idref')}'),
      ],
    );
    replacements[opfPath] = opf.toXmlString();
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
      String localHref(String href) => p.posix.relative(
        p.posix.normalize('${p.posix.dirname(path)}/${href.split('#').first}'),
        from: dir,
      );
      Map<String, XmlElement> targets(
        XmlElement root,
        String tag,
        String attr,
      ) => {
        for (final link in root.descendants.whereType<XmlElement>())
          if (link.name.local == tag && link.getAttribute(attr) != null)
            localHref(link.getAttribute(attr)!): link.parentElement!,
      };
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
        final nodes = <XmlElement>[];
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
          nodes.add(copy);
        }
        merge(list, targets(list, 'a', 'href'), nodes);
      } else {
        final map = element(doc, 'navMap');
        final nodes = <XmlElement>[];
        for (final point in element(next, 'navMap').childElements) {
          final copy = point.copy();
          copy.setAttribute('id', '$idPrefix${point.getAttribute('id')}');
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
          nodes.add(copy);
        }
        merge(map, targets(map, 'content', 'src'), nodes);
        var order = 0;
        for (final point in map.descendants.whereType<XmlElement>()) {
          if (point.name.local == 'navPoint') {
            point.setAttribute('playOrder', '${++order}');
          }
        }
      }
      replacements[path] = doc.toXmlString();
    }
    final nextIndex =
        jsonDecode(read(incoming, 'OEBPS/online_chapters.json')) as Map;
    final incomingRows = (nextIndex['chapters'] as List)
        .cast<Map<String, Object?>>();
    var storedIndex = 0;
    var newIndex = 0;
    final upgraded = <Map<String, String>>[];
    for (final (index, chapter) in remote.indexed) {
      final row = additions.contains(index)
          ? {
              'href': '$prefix/${incomingRows[newIndex++]['href']}',
              'title': chapter.title,
            }
          : chapters[storedIndex++];
      upgraded.add({
        ...row,
        'url': chapter.url,
        'volume': chapter.volume,
        'requestOptions': jsonEncode(chapter.requestOptions),
      });
    }
    replacements['$dir/online_chapters.json'] = jsonEncode({
      'version': 1,
      'chapters': upgraded,
    });
    if (original.findFile(OnlineEpubMetadata.indexPath) != null) {
      final metadata =
          jsonDecode(read(original, OnlineEpubMetadata.indexPath)) as Map;
      final oldRows = (metadata['chapters'] as List)
          .cast<Map<String, Object?>>();
      final byHref = {
        for (final row in oldRows)
          p.posix.normalize(
            '${row['href']}'.replaceFirst(RegExp(r'^OEBPS/'), ''),
          ): row,
      };
      final absoluteHrefs = oldRows.any(
        (row) => '${row['href']}'.startsWith('OEBPS/'),
      );
      metadata['chapters'] = [
        for (final (index, row) in upgraded.indexed)
          {
            ...?byHref[row['href']],
            'href':
                byHref[row['href']]?['href'] ??
                (absoluteHrefs
                    ? p.posix.normalize('$dir/${row['href']}')
                    : row['href']),
            'title': row['title'],
            'volumeTitle': remote[index].volume,
            'url': remote[index].requestOptions.isEmpty
                ? remote[index].url
                : '${remote[index].url},${jsonEncode(remote[index].requestOptions)}',
            'state': 'READY',
          },
      ];
      replacements[OnlineEpubMetadata.indexPath] = jsonEncode(metadata);
    }
    final output = Archive()
      ..addFile(
        ArchiveFile.noCompress(
          'mimetype',
          20,
          ascii.encode('application/epub+zip'),
        ),
      );
    for (final file in original.files) {
      if (file.name == 'mimetype' || replacements.containsKey(file.name)) {
        continue;
      }
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

bool _matchesChapter(Map<String, String> stored, OnlineChapter chapter) {
  final url = stored['url'] ?? '';
  if (url.isEmpty) {
    return stored['title']?.trim() == chapter.title.trim() &&
        ((stored['volume'] ?? '').isEmpty ||
            stored['volume'] == chapter.volume);
  }
  final request = splitBookSourceUrlOptions(url);
  if (stored.containsKey('requestOptions') ||
      request.options.isNotEmpty ||
      chapter.requestOptions.isNotEmpty) {
    return onlineRequestIdentity(
          url,
          bookSourceRuleMap(stored['requestOptions']),
        ) ==
        onlineChapterIdentity(chapter);
  }
  return _chapterKey(url) == _chapterKey(chapter.url);
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
