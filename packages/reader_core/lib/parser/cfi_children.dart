import 'package:xml/xml.dart';

/// 元素或逻辑字符块在父元素内的 CFI 位置。
class CfiChild<T> {
  /// 元素使用偶数位置。
  CfiChild.element(this.index, T node)
    : element = node,
      characters = const [],
      text = '';

  /// 字符块使用奇数位置，可包含多个实际文本节点或为空。
  CfiChild.characters(this.index, List<T> nodes, this.text)
    : element = null,
      characters = List<T>.unmodifiable(nodes);

  final int index;
  final T? element;
  final List<T> characters;
  final String text;
}

/// EPUB CFI §3.1.1：只有元素划分字符槽，其余非字符节点不占位置。
///
/// 空槽只保留索引，不向调用方的正文树插入节点。
Iterable<CfiChild<T>> cfiChildren<T>(
  Iterable<T> nodes, {
  required bool Function(T) isElement,
  required String? Function(T) textOf,
}) sync* {
  var index = 1;
  var characters = <T>[];
  var text = StringBuffer();
  for (final node in nodes) {
    if (isElement(node)) {
      yield CfiChild.characters(index, characters, text.toString());
      yield CfiChild.element(index + 1, node);
      index += 2;
      characters = <T>[];
      text = StringBuffer();
    } else {
      final value = textOf(node);
      if (value != null) {
        characters.add(node);
        text.write(value);
      }
    }
  }
  yield CfiChild.characters(index, characters, text.toString());
}

/// XML 字符数据同时包含普通文本和 CDATA，忽略注释与处理指令。
Iterable<CfiChild<XmlNode>> xmlCfiChildren(XmlElement element) => cfiChildren(
  element.children,
  isElement: (node) => node is XmlElement,
  textOf: (node) => switch (node) {
    XmlText() => node.value,
    XmlCDATA() => node.value,
    _ => null,
  },
);

/// 三个解析入口使用同一实体解码；不预改源码，事件位置仍对应原 UTF-16。
const XmlEntityMapping cfiEntityMapping = _CfiEntityMapping();

class _CfiEntityMapping extends XmlDefaultEntityMapping {
  const _CfiEntityMapping() : super.html5();

  static final _named = RegExp(r'^[a-zA-Z][a-zA-Z0-9]+$');

  @override
  String? decodeEntity(String input) =>
      super.decodeEntity(input) ?? (_named.hasMatch(input) ? ' ' : null);
}
