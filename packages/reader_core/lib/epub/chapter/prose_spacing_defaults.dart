import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';

/// 只补普通正文缺省值；作者声明来源与计算值分开，继承的左对齐也不能覆盖。
ComputedStyle proseSpacingDefaults(
  ComputedStyle style,
  List<SelectorElement> chain,
  String text, {
  bool specialComponent = false,
}) {
  if (specialComponent || !_isProse(style, chain, text)) return style;
  return style.withTypography(
    textAlign: style.declaredTextProperties.contains('text-align')
        ? null
        : CssTextAlign.justify,
    textSpacingTrim: style.declaredTextProperties.contains('text-spacing-trim')
        ? null
        : CssTextSpacingTrim.trimAll,
  );
}

bool _isProse(ComputedStyle style, List<SelectorElement> chain, String text) {
  if (chain.isEmpty ||
      text.trim().isEmpty ||
      text.contains('\n') ||
      style.writingMode != CssWritingMode.horizontalTb ||
      style.isRtl ||
      style.whiteSpace != CssWhiteSpace.normal ||
      style.isOutOfFlow ||
      style.cssFloat != CssFloat.none ||
      (style.columnCount ?? 1) > 1 ||
      style.columnWidth != null ||
      style.display != CssDisplay.block ||
      style.initialLetterLines != null) {
    return false;
  }
  final element = chain.last;
  if (element.tag != 'p' && element.tag != 'div') return false;
  if (chain.any(_specialElement)) return false;
  return !element.childElements.any(_containsBlock);
}

bool _containsBlock(SelectorElement element) =>
    _blockTags.contains(element.tag) ||
    element.childElements.any(_containsBlock);

bool _specialElement(SelectorElement element) {
  if (_excludedTags.contains(element.tag)) return true;
  final semantics = [
    element.attributes['epub:type'] ?? '',
    element.attributes['role'] ?? '',
    element.attributes['class'] ?? '',
  ].join(' ').toLowerCase().split(RegExp(r'\s+'));
  return semantics.any(
    (token) =>
        _excludedSemantics.contains(token) ||
        _excludedSemantics.contains(token.split(':').last),
  );
}

const _excludedTags = {
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'dl',
  'dt',
  'dd',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'td',
  'th',
  'caption',
  'figcaption',
  'nav',
  'pre',
  'code',
  'samp',
  'kbd',
  'header',
  'footer',
  'svg',
  'math',
};

const _blockTags = {
  ..._excludedTags,
  'div',
  'p',
  'section',
  'article',
  'aside',
  'blockquote',
  'figure',
  'hr',
  'br',
};

const _excludedSemantics = {
  'poem',
  'poetry',
  'verse',
  'stanza',
  'linegroup',
  'line',
  'title',
  'subtitle',
  'caption',
  'toc',
  'nav',
  'doc-toc',
  'doc-subtitle',
  'doc-pageheader',
  'doc-pagefooter',
  'doc-footnote',
  'doc-endnote',
  'code',
};
