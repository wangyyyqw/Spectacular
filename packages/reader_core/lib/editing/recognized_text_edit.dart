import 'package:xml/xml_events.dart';

import '../parser/document_parser.dart';
import '../parser/cfi_children.dart';
import '../position/cfi.dart';
import 'editable_document.dart';
import 'epub_edit_session.dart';

typedef _RecognizedPiece = ({int start, int end, String before, String after});

/// OCR 仅作为用户输入初值；实际替换范围仍由严格 CFI 和原文证据限定。
class RecognizedTextEdit {
  RecognizedTextEdit._(
    this.path,
    this.source,
    this.initialText,
    this._pieces,
    this.prefix,
  );

  final String path;
  final String source;
  final String initialText;
  final List<_RecognizedPiece> _pieces;
  final String prefix;

  static RecognizedTextEdit capture(
    EpubEditSession session,
    int spineIndex,
    String startCfi,
    String endCfi,
    ({String text, String sourceText}) recognized, {
    bool preview = false,
  }) {
    final targets = session.resolveEditableElements(spineIndex, [
      startCfi,
      endCfi,
    ], preview: preview);
    final first = targets.first;
    final source = first.document.source;
    final parsed = DocumentParser.parse(xhtml: source, spineIndex: spineIndex);
    final start = EpubCfi.parse(startCfi)!;
    final end = EpubCfi.parse(endCfi)!;
    final startNode = parsed.nodeAtCfi(start);
    final endNode = parsed.nodeAtCfi(end);
    if (startNode is! ParsedText ||
        endNode is! ParsedText ||
        start.charOffset == null ||
        end.charOffset == null ||
        start.compareTo(end) >= 0) {
      throw const EpubEditException('选区没有精确的文字范围，请重新选择');
    }
    final pieces = _capturePieces(
      parsed,
      startNode,
      endNode,
      start.charOffset!,
      end.charOffset!,
    );
    String compact(String value) => value.replaceAll(RegExp(r'\s'), '');
    if (pieces.parts.isEmpty ||
        compact(pieces.text) != compact(recognized.sourceText)) {
      throw const EpubEditException('所选原文已变化，未写入识别结果');
    }
    final name = first.qualifiedName;
    return RecognizedTextEdit._(
      first.path,
      source,
      recognized.text,
      pieces.parts,
      name.contains(':') ? '${name.split(':').first}:' : '',
    );
  }

  static ({String text, List<_RecognizedPiece> parts}) _capturePieces(
    ParsedDocument parsed,
    ParsedText startNode,
    ParsedText endNode,
    int startOffset,
    int endOffset,
  ) {
    final nodes = parsed.textNodes
        .where(
          (node) => node.start >= startNode.start && node.end <= endNode.end,
        )
        .toList();
    final expected = StringBuffer();
    final pieces = <_RecognizedPiece>[];
    final events = parseEvents(
      parsed.source,
      entityMapping: cfiEntityMapping,
      withLocation: true,
    ).toList();
    for (final node in nodes) {
      final from = identical(node, startNode) ? startOffset : 0;
      final to = identical(node, endNode) ? endOffset : node.text.length;
      for (final offset in [from, to]) {
        if (offset > 0 &&
            offset < node.text.length &&
            node.text.codeUnitAt(offset) >= 0xdc00 &&
            node.text.codeUnitAt(offset) <= 0xdfff) {
          throw const EpubEditException('选区切开了完整字符，请重新选择');
        }
      }
      expected.write(node.text.substring(from, to));
      pieces.addAll(_piecesFor(events, node, from, to));
    }
    return (text: expected.toString(), parts: pieces);
  }

  static Iterable<_RecognizedPiece> _piecesFor(
    List<XmlEvent> events,
    ParsedText node,
    int from,
    int to,
  ) sync* {
    var offset = 0;
    for (final event in events) {
      final String value;
      final int padding;
      if (event is XmlTextEvent) {
        value = event.value;
        padding = 0;
      } else if (event is XmlCDATAEvent) {
        value = event.value;
        padding = 9;
      } else {
        continue;
      }
      final contentStart = event.start! + padding;
      if (contentStart < node.start || contentStart >= node.end) continue;
      final next = offset + value.length;
      if (next > from && offset < to) {
        final first = (from - offset).clamp(0, value.length);
        final last = (to - offset).clamp(first, value.length);
        yield (
          start: event.start!,
          end: event.stop!,
          before: value.substring(0, first),
          after: value.substring(last),
        );
      }
      offset = next;
    }
  }

  void apply(EpubEditSession session, String input) {
    if (session.readText(path) != source) {
      throw const EpubEditException('原文已变化，请重新选择');
    }
    var updated = source;
    // 明文必须使用普通字体，不能继续继承码点已重映射的书内字体。
    final replacement =
        '<${prefix}span style="font-family: serif !important; white-space: pre-wrap !important;">'
        '${escapeXmlText(input)}</${prefix}span>';
    for (var i = _pieces.length - 1; i >= 0; i--) {
      final piece = _pieces[i];
      updated = updated.replaceRange(
        piece.start,
        piece.end,
        '${escapeXmlText(piece.before)}${i == 0 ? replacement : ''}${escapeXmlText(piece.after)}',
      );
    }
    session.transaction('编辑识别文字', (tx) => tx.writeText(path, updated));
  }
}
