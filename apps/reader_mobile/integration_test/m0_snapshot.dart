import 'dart:convert';

import 'package:reader_core/layout/paginator.dart';

import 'package:reader_mobile/reader/demo_source.dart';

/// 一页的快照记录。
class M0PageRecord {
  /// 创建记录。
  const M0PageRecord({
    required this.spineIndex,
    required this.pageIndex,
    required this.text,
  });

  /// 章节序号。
  final int spineIndex;

  /// 页序号。
  final int pageIndex;

  /// 页文本。
  final String text;

  /// 序列化。
  Map<String, Object> toJson() => <String, Object>{
    'spine': spineIndex,
    'page': pageIndex,
    'head': text.length <= 20 ? text : text.substring(0, 20),
    'tail': text.length <= 20 ? text : text.substring(text.length - 20),
  };
}

/// 页序列快照。
class M0Snapshot {
  /// 创建快照。
  const M0Snapshot({required this.pages, required this.hash});

  /// 页记录。
  final List<M0PageRecord> pages;

  /// 序列 hash（FNV-1a 32）。
  final String hash;

  /// 转 JSON。
  Map<String, Object> toJson() => <String, Object>{
    'version': 1,
    'pageCount': pages.length,
    'hash': hash,
    'pages': pages.map((page) => page.toJson()).toList(),
  };
}

/// 生成 30 章示例书的页序列快照。
Future<M0Snapshot> buildM0Snapshot() async {
  final source = DemoChapterSource();
  final pages = <M0PageRecord>[];
  for (var spine = 0; spine < source.chapterCount; spine++) {
    final chapterPages = await source.loadChapter(spine);
    for (var page = 0; page < chapterPages.length; page++) {
      pages.add(
        M0PageRecord(
          spineIndex: spine,
          pageIndex: page,
          text: _pageText(chapterPages[page]),
        ),
      );
    }
  }
  final buffer = StringBuffer();
  for (final page in pages) {
    buffer.writeln(
      '${page.spineIndex}/${page.pageIndex}|${page.toJson()['head']}|${page.toJson()['tail']}',
    );
  }
  return M0Snapshot(pages: pages, hash: _fnv1a(buffer.toString()));
}

String _pageText(PageContent page) {
  final buffer = StringBuffer();
  for (final slice in page.slices) {
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = slice.block.layout.lines[i];
      buffer.writeln(slice.block.layout.text.substring(line.start, line.end));
    }
  }
  return buffer.toString();
}

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
