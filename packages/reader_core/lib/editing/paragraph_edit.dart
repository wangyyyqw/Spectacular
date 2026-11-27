import 'package:xml/xml.dart' show XmlParserException, XmlTagException;
import 'package:xml/xml_events.dart';

import 'editable_document.dart';
import 'element_commands.dart';
import 'epub_edit_session.dart';

class EpubParagraphEdit {
  EpubParagraphEdit._(this.session, this.first, this.last);

  factory EpubParagraphEdit.fromSelection(
    EpubEditSession session,
    int spineIndex,
    String startCfi,
    String endCfi,
  ) {
    final targets = session.resolveEditableElements(spineIndex, [
      startCfi,
      endCfi,
    ]);
    final first = _paragraph(targets.first);
    final last = _paragraph(targets.last);
    if (first.parent != last.parent || first.start > last.start) {
      throw const EpubEditException('选区跨越了不同的段落容器，请分段编辑');
    }
    return EpubParagraphEdit._(session, first, last);
  }

  final EpubEditSession session;
  final EditableElementRef first;
  final EditableElementRef last;

  bool get isHtml => first != last || first.children.isNotEmpty;
  late final String initialText = isHtml
      ? first.document.source.substring(first.start, last.end)
      : first.text;

  static EditableElementRef _paragraph(EditableElementRef target) {
    const tags = {
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'div',
      'li',
      'dt',
      'dd',
      'blockquote',
      'pre',
      'td',
      'th',
      'figcaption',
      'caption',
    };
    if (!target.ancestors.any((node) => node.tag == 'body')) {
      throw const EpubEditException('所选文字不在可编辑的正文段落中');
    }
    var node = target;
    while (!tags.contains(node.tag) && node.parent!.tag != 'body') {
      node = node.parent!;
    }
    return node;
  }

  void apply(String input) {
    session.checkElement(first);
    if (input == initialText) return;
    if (!isHtml) {
      session.replaceText(first, input);
      return;
    }
    try {
      parseEvents(input, validateNesting: true).lastOrNull;
    } on XmlTagException catch (error) {
      final expected = error.expectedName;
      throw EpubEditException(
        expected == null
            ? '标签不匹配：多余的 </${error.actualName}>'
            : '标签未正确闭合：此处需要 </$expected>',
      );
    } on XmlParserException {
      throw const EpubEditException('HTML 格式有误，请检查标签是否闭合、属性引号是否完整');
    }
    session.transaction('编辑阅读段落', (tx) {
      tx.writeText(
        first.path,
        first.document.source.replaceRange(first.start, last.end, input),
      );
    });
  }
}
