import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../position/cfi.dart';
import '../src/api/models.dart';
import 'archive_reader.dart';

/// 目录 CFI 绑定结果。
class TocCfiBindResult {
  /// 创建结果。
  const TocCfiBindResult({
    required this.toc,
    required this.bound,
    required this.missing,
    this.warnings = const <String>[],
  });

  /// 绑定后的目录。
  final List<TocEntry> toc;

  /// 成功绑定数。
  final int bound;

  /// 未绑定数。
  final int missing;

  /// 告警。
  final List<String> warnings;
}

/// 把目录项的 `(spineIndex, fragment)` 绑定为 CFI。
///
/// CFI 约定：`/6/{2*(spineIndex+1)}!/4/...`，`/4` 为 body。
abstract final class TocCfiBinder {
  /// 绑定目录；`maxEntries` 用于限制解析章节数（测试/渐进绑定）。
  static TocCfiBindResult bind({
    required EpubArchive archive,
    required List<SpineItem> spine,
    required String opfPath,
    required List<TocEntry> toc,
    int? maxEntries,
  }) {
    final chapters = <int, _Chapter?>{};
    final warnings = <String>[];
    var bound = 0;
    var missing = 0;
    var visited = 0;

    _Chapter? chapterFor(int spineIndex) {
      if (chapters.containsKey(spineIndex)) {
        return chapters[spineIndex];
      }
      _Chapter? chapter;
      if (spineIndex >= 0 && spineIndex < spine.length) {
        final item = spine[spineIndex];
        final baseDir = p.posix.dirname(opfPath);
        final path = p.posix.normalize(p.posix.join(baseDir, item.href));
        final text = archive.readString(path);
        if (text != null) {
          chapter = _Chapter.parse(text);
        }
      }
      chapters[spineIndex] = chapter;
      return chapter;
    }

    TocEntry bindEntry(TocEntry entry) {
      var cfi = entry.cfi;
      final canBind =
          entry.spineIndex >= 0 &&
          entry.spineIndex < spine.length &&
          (maxEntries == null || visited < maxEntries);
      if (canBind) {
        visited += 1;
        final chapter = chapterFor(entry.spineIndex);
        if (chapter != null) {
          cfi = chapter.cfiFor(entry.spineIndex, entry.fragment);
        }
        if (cfi != null) {
          bound += 1;
        } else if (entry.fragment != null) {
          missing += 1;
          warnings.add(
            '目录 CFI 未绑定：spine=${entry.spineIndex} '
            'fragment=${entry.fragment}',
          );
        }
      }

      return TocEntry(
        title: entry.title,
        spineIndex: entry.spineIndex,
        fragment: entry.fragment,
        playOrder: entry.playOrder,
        cfi: cfi,
        children: entry.children.map(bindEntry).toList(growable: false),
      );
    }

    return TocCfiBindResult(
      toc: toc.map(bindEntry).toList(growable: false),
      bound: bound,
      missing: missing,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}

class _Chapter {
  _Chapter(this.body, this.ids);

  factory _Chapter.parse(String xhtml) {
    final document = XmlDocument.parse(_sanitize(xhtml));
    XmlElement? body;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    final ids = <String, XmlElement>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      final id = element.getAttribute('id')?.trim();
      if (id != null && id.isNotEmpty) {
        ids.putIfAbsent(id, () => element);
      }
    }
    return _Chapter(body, ids);
  }

  final XmlElement? body;
  final Map<String, XmlElement> ids;

  EpubCfi? cfiFor(int spineIndex, String? fragment) {
    final bodyElement = body;
    if (bodyElement == null) {
      return null;
    }
    final steps = <CfiStep>[];
    if (fragment != null && fragment.isNotEmpty) {
      final target = ids[fragment];
      if (target == null) {
        return null;
      }
      final path = _pathTo(bodyElement, target);
      if (path == null) {
        return null;
      }
      steps.addAll(path);
    }

    final builder = CfiBuilder().itemRef((spineIndex + 1) * 2).body(4);
    for (final step in steps) {
      builder.step(step.index, assertion: step.assertion);
    }
    return builder.build();
  }

  List<CfiStep>? _pathTo(XmlElement body, XmlElement target) {
    if (identical(body, target)) {
      return const <CfiStep>[];
    }
    bool search(XmlElement parent, List<CfiStep> path) {
      final children = parent.childElements.toList(growable: false);
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final id = child.getAttribute('id')?.trim();
        path.add(
          CfiStep((i + 1) * 2, assertion: id == null || id.isEmpty ? null : id),
        );
        if (identical(child, target)) {
          return true;
        }
        if (search(child, path)) {
          return true;
        }
        path.removeLast();
      }
      return false;
    }

    final path = <CfiStep>[];
    return search(body, path) ? path : null;
  }

  static String _sanitize(String text) =>
      text.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]+);'), (match) {
        const known = <String, String>{
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
        };
        return known[match[1]] ?? match[0]!;
      });
}
