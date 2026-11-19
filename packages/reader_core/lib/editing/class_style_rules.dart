part of 'class_style_editor.dart';

class EditableStyleRule {
  const EditableStyleRule({
    required this.path,
    required this.sourceDigest,
    required this.start,
    required this.end,
    required this.selector,
    required this.text,
    this.media,
  });

  final String path;
  final String sourceDigest;
  final int start;
  final int end;
  final String selector;
  final String text;
  final String? media;
}

extension ElementStylesheetRules on ClassStyleEditor {
  List<EditableStyleRule> rulesForElement(EditableElementRef element) {
    session.checkElement(element);
    final chain = [...element.ancestors, element];
    var target = _EditSelectorElement(chain.first);
    final ancestors = <SelectorElement>[];
    for (final child in chain.skip(1)) {
      ancestors.add(target);
      target = target.childElements.cast<_EditSelectorElement>().firstWhere(
        (candidate) => candidate.node.start == child.start,
      );
    }
    final sources = _loadRules(
      element.path,
      session.readText(element.path),
      {},
    );
    return [
      for (final path in sources.map((source) => source.path).toSet())
        for (final rule in _sourceRules(session, path))
          if (SelectorParser.parse(rule.selector).matches(target, ancestors))
            rule,
    ];
  }

  void replaceStyleRule(EditableStyleRule rule, String replacement) {
    final source = session.readText(rule.path);
    if (editDigest(source) != rule.sourceDigest ||
        source.substring(rule.start, rule.end) != rule.text) {
      throw const EpubEditException('样式表已变化，请重新选择段落后再应用');
    }
    final errors = <csslib.Message>[];
    final parsed = csslib.parse(replacement, errors: errors);
    if (errors.isNotEmpty ||
        parsed.topLevels.length != 1 ||
        parsed.topLevels.single is! cssast.RuleSet) {
      throw const FormatException('请输入一条完整的 CSS 规则，并使用英文分号和成对花括号');
    }
    final next = source.replaceRange(rule.start, rule.end, replacement);
    writeSources({rule.path: next}, validate: true);
  }
}

List<EditableStyleRule> _sourceRules(EpubEditSession session, String path) {
  final source = session.readText(path);
  final digest = editDigest(source);
  final resource = session.resources.firstWhere(
    (resource) => resource.path == path,
  );
  final segments = <({String css, int offset})>[];
  if (resource.mediaType == 'text/css' || path.toLowerCase().endsWith('.css')) {
    segments.add((css: source, offset: 0));
  } else {
    for (final style
        in session
            .editableDocument(path)
            .elements
            .where((node) => node.tag == 'style')) {
      var css = style.innerXml;
      var offset = style.openEnd;
      if (css.trim().startsWith('<![CDATA[') && css.trim().endsWith(']]>')) {
        final start = css.indexOf('<![CDATA[') + 9;
        offset += start;
        css = css.substring(start, css.lastIndexOf(']]>'));
      }
      segments.add((css: css, offset: offset));
    }
  }
  return [
    for (final segment in segments)
      ...(_StyleRuleCollector(
        path,
        source,
        digest,
        segment.offset,
      )..visitTree(csslib.parse(segment.css))).rules,
  ];
}

class _StyleRuleCollector extends cssast.Visitor {
  _StyleRuleCollector(this.path, this.source, this.digest, this.offset);
  final String path;
  final String source;
  final String digest;
  final int offset;
  final rules = <EditableStyleRule>[];
  final _media = <String>[];

  @override
  void visitRuleSet(cssast.RuleSet node) {
    final start = offset + node.span.start.offset;
    final end = offset + node.declarationGroup.span.end.offset;
    rules.add(
      EditableStyleRule(
        path: path,
        sourceDigest: digest,
        start: start,
        end: end,
        selector: node.selectorGroup!.span!.text.trim(),
        text: source.substring(start, end),
        media: _media.isEmpty ? null : _media.join(' / '),
      ),
    );
  }

  @override
  void visitMediaDirective(cssast.MediaDirective node) {
    _media.add(node.mediaQueries.map((query) => query.span.text).join(', '));
    super.visitMediaDirective(node);
    _media.removeLast();
  }
}
