/// 为 html5lib 准备 XHTML 输入。
///
/// html5lib 不把空自闭合 `<title/>` 视为已闭合标签，会把后续 head/body
/// 内容吞进 `title` 的原始文本。用等长注释替换，既绕开该行为，又保持
/// sourceSpan 偏移与原文一致，避免破坏 CFI。
String prepareHtml5Input(String xhtml) {
  return xhtml.replaceAllMapped(
    RegExp(r'<title\s*/>', caseSensitive: false),
    (match) => '<!--${' ' * (match[0]!.length - 7)}-->',
  );
}
