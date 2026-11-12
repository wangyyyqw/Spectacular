import 'package:path/path.dart' as p;
import 'package:xml/xml_events.dart';

import 'editable_document.dart';
import 'epub_edit_session.dart';

/// 原文命令只改目标源码区间，事务统一处理验证、历史与预览版本。
extension EpubElementCommands on EpubEditSession {
  void replaceText(EditableElementRef element, String text) {
    checkElement(element);
    final replacement = _replaceText(element, text);
    transaction('修改正文', (tx) => tx.writeText(element.path, replacement));
  }

  void replaceInnerHtml(EditableElementRef element, String html) {
    checkElement(element);
    transaction(
      '修改段落 HTML',
      (tx) => tx.writeText(element.path, element.replaceInner(html)),
    );
  }

  void deleteElement(EditableElementRef element) {
    _requireBodyChild(element);
    _splice(this, element, (element.start, element.end), '', '删除元素');
  }

  void insertBefore(EditableElementRef element, String html) {
    _requireBodyChild(element);
    _splice(this, element, (element.start, element.start), html, '在元素前插入');
  }

  void insertAfter(EditableElementRef element, String html) {
    _requireBodyChild(element);
    _splice(this, element, (element.end, element.end), html, '在元素后插入');
  }

  void splitAtTextOffset(EditableElementRef element, int offset) {
    _requireBodyChild(element);
    if (!const {
      'p',
      'div',
      'li',
      'blockquote',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(element.tag)) {
      throw const EpubEditException('只能拆分段落或标题元素');
    }
    checkElement(element);
    final split = _splitMarkup(element, offset);
    _splice(this, element, (element.start, element.end), split, '拆分段落');
  }

  /// 图片资源由资源事务导入；这里只插入相对引用，不隐式更改 OPF。
  void insertImage(
    EditableElementRef element, {
    required String resourcePath,
    String alt = '',
    bool after = true,
  }) {
    if (readBytes(resourcePath) == null) {
      throw const EpubEditException('图片资源不存在');
    }
    final relative = p.posix.relative(
      normalizePath(resourcePath),
      from: p.posix.dirname(element.path),
    );
    final href = relative.split('/').map(Uri.encodeComponent).join('/');
    final html =
        '<img src="${escapeXmlAttribute(href)}" alt="${escapeXmlAttribute(alt)}"/>';
    if (after) {
      insertAfter(element, html);
    } else {
      insertBefore(element, html);
    }
  }

  void replaceImage(
    EditableElementRef element,
    String resourcePath, {
    String? alt,
  }) {
    if (element.tag != 'img') throw const EpubEditException('目标不是 XHTML 图片');
    checkElement(element);
    if (readBytes(resourcePath) == null) {
      throw const EpubEditException('图片资源不存在');
    }
    final relative = p.posix.relative(
      normalizePath(resourcePath),
      from: p.posix.dirname(element.path),
    );
    final href = relative.split('/').map(Uri.encodeComponent).join('/');
    var source = element.replaceAttribute('src', href);
    if (alt != null) {
      final current = EditableDocument.parse(source)
          .elementAtOffset(element.start)!;
      source = current.replaceAttribute('alt', alt);
    }
    transaction('替换图片', (tx) => tx.writeText(element.path, source));
  }
}

void _requireBodyChild(EditableElementRef element) {
  if (!element.ancestors.any((node) => node.tag == 'body')) {
    throw const EpubEditException('正文命令不能删除或拆分文档根与 head');
  }
}

void _splice(
  EpubEditSession session,
  EditableElementRef element,
  (int, int) range,
  String replacement,
  String label,
) {
  session.checkElement(element);
  final source = session
      .readText(element.path)
      .replaceRange(range.$1, range.$2, replacement);
  session.transaction(label, (tx) => tx.writeText(element.path, source));
}

typedef _TextPiece = ({int start, int end, String text});

List<_TextPiece> _pieces(EditableElementRef element) => [
  for (final event in parseEvents(
    element.innerXml,
    withLocation: true,
    validateNesting: true,
  ))
    if (event is XmlTextEvent)
      (
        start: element.openEnd + event.start!,
        end: element.openEnd + event.stop!,
        text: event.value,
      )
    else if (event is XmlCDATAEvent)
      (
        start: element.openEnd + event.start!,
        end: element.openEnd + event.stop!,
        text: event.value,
      ),
];

String _replaceText(EditableElementRef element, String next) {
  final previous = element.text;
  if (previous == next) return element.document.source;
  final pieces = _pieces(element);
  if (pieces.isEmpty) {
    return element.replaceInner('${escapeXmlText(next)}${element.innerXml}');
  }
  final (prefix, suffix) = _textDifference(previous, next);
  final insertion = next.substring(prefix, next.length - suffix);
  final edits = _textEdits(pieces, prefix, previous.length - suffix, insertion);
  var source = element.document.source;
  for (final edit in edits.reversed) {
    source = source.replaceRange(
      edit.start,
      edit.end,
      escapeXmlText(edit.text),
    );
  }
  return source;
}

(int, int) _textDifference(String previous, String next) {
  var prefix = 0;
  while (prefix < previous.length &&
      prefix < next.length &&
      previous[prefix] == next[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < previous.length - prefix &&
      suffix < next.length - prefix &&
      previous[previous.length - suffix - 1] ==
          next[next.length - suffix - 1]) {
    suffix++;
  }
  // 不在 UTF-16 代理对内部截断。
  if (prefix > 0 &&
      prefix < previous.length &&
      _low(previous.codeUnitAt(prefix))) {
    prefix--;
  }
  if (suffix > 0 &&
      suffix < previous.length &&
      _low(previous.codeUnitAt(previous.length - suffix))) {
    suffix--;
  }
  return (prefix, suffix);
}

List<_TextPiece> _textEdits(
  List<_TextPiece> pieces,
  int start,
  int end,
  String replacement,
) {
  final edits = <_TextPiece>[];
  var cursor = 0;
  var inserted = false;
  for (final piece in pieces) {
    final next = cursor + piece.text.length;
    final replacesText = start < end && next > start && cursor < end;
    final insertsText =
        start == end && next >= start && cursor <= start && !inserted;
    if (replacesText || insertsText) {
      final from = (start - cursor).clamp(0, piece.text.length);
      final to = (end - cursor).clamp(from, piece.text.length);
      edits.add((
        start: piece.start,
        end: piece.end,
        text: piece.text.replaceRange(from, to, inserted ? '' : replacement),
      ));
      inserted = true;
    }
    cursor = next;
  }
  return edits;
}

String _splitMarkup(EditableElementRef element, int offset) {
  if (offset <= 0 ||
      offset >= element.text.length ||
      _low(element.text.codeUnitAt(offset))) {
    throw const EpubEditException('拆分点必须在段落文字内部，且不能拆开代理对');
  }
  var remaining = offset;
  for (final piece in _pieces(element)) {
    if (remaining > piece.text.length) {
      remaining -= piece.text.length;
      continue;
    }
    return _splitPiece(element, piece, remaining);
  }
  throw const EpubEditException('无法确定拆分点的原文范围');
}

String _splitPiece(EditableElementRef element, _TextPiece piece, int offset) {
  final nested = element.document.elements
      .where(
        (node) =>
            node.start > element.start &&
            node.openEnd <= piece.start &&
            node.closeStart >= piece.end,
      )
      .toList();
  final source = element.document.source;
  final left =
      source.substring(element.openEnd, piece.start) +
      escapeXmlText(piece.text.substring(0, offset));
  final right =
      escapeXmlText(piece.text.substring(offset)) +
      source.substring(piece.end, element.closeStart);
  final opening = source.substring(element.start, element.openEnd);
  final closes = nested.reversed
      .map((node) => '</${node.qualifiedName}>')
      .join();
  final opens = nested.map(_openingWithoutId).join();
  return '$opening$left$closes</${element.qualifiedName}>'
      '${_openingWithoutId(element)}$opens$right</${element.qualifiedName}>';
}

String _openingWithoutId(EditableElementRef element) {
  final opening = element.document.source.substring(
    element.start,
    element.openEnd,
  );
  return opening.replaceAllMapped(
    RegExp(r'''\s+([^\s=<>/]+)\s*=\s*(["'])(.*?)\2''', dotAll: true),
    (match) => const {'id', 'xml:id'}.contains(match[1]) ? '' : match[0]!,
  );
}

bool _low(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
