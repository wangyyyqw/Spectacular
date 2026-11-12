part of 'class_style_editor.dart';

class _EditSelectorElement implements SelectorElement {
  _EditSelectorElement(this.node);
  final EditableElementRef node;
  @override
  String get tag => node.tag;
  @override
  Map<String, String> get attributes => node.attributes;
  @override
  late final List<SelectorElement> childElements = node.children
      .map(_EditSelectorElement.new)
      .toList();
}

class _StyleTarget {
  const _StyleTarget(this.node, this.element, this.ancestors, this.rules);
  final EditableElementRef node;
  final SelectorElement element;
  final List<SelectorElement> ancestors;
  final List<_SourcedRule> rules;
}

class _SourcedRule {
  _SourcedRule(this.path, this.rule, this.media)
    : selectors = SelectorParser.parse(rule.selector);
  final String path;
  final CssRule rule;
  final List<String> media;
  final SelectorList selectors;
}

extension _ClassSources on ClassStyleEditor {
  List<_StyleTarget> _targets(String className) {
    final targets = <_StyleTarget>[];
    final cache = <String, CssStylesheet>{};
    for (final resource in session.resources.where(
      (r) => r.mediaType == 'application/xhtml+xml',
    )) {
      final source = session.readText(resource.path);
      final doc = EditableDocument.parse(
        source,
        path: resource.path,
        revision: session.revision,
      );
      if (!doc.elements.any((e) => e.classes.contains(className))) continue;
      final rules = _loadRules(resource.path, source, cache);
      void visit(
        _EditSelectorElement element,
        List<SelectorElement> ancestors,
      ) {
        if (element.node.classes.contains(className)) {
          targets.add(_StyleTarget(element.node, element, ancestors, rules));
        }
        for (final child
            in element.childElements.cast<_EditSelectorElement>()) {
          visit(child, [...ancestors, element]);
        }
      }

      visit(_EditSelectorElement(doc.elements.first), []);
    }
    return targets;
  }

  List<_SourcedRule> _loadRules(
    String path,
    String source,
    Map<String, CssStylesheet> cache,
  ) {
    final result = <_SourcedRule>[];
    void load(
      String origin,
      CssStylesheet sheet,
      List<String> media,
      Set<String> active,
    ) {
      if (active.length > 16) throw const EpubEditException('CSS 导入层级过深');
      for (final imported in sheet.imports) {
        final target = resolveEditReference(origin, imported.url).$1;
        if (active.contains(target)) continue;
        if (Uri.tryParse(target)?.hasScheme ?? true) continue;
        final next = cache.putIfAbsent(
          target,
          () => CssParser.parse(session.readText(target)),
        );
        load(target, next, [...media, ?imported.media], {...active, target});
      }
      for (final rule in sheet.rules) {
        result.add(
          _SourcedRule(origin, rule, [
            ...media,
            ...rule.mediaConditions,
            if (rule.mediaConditions.isEmpty && rule.media != null) rule.media!,
          ]),
        );
      }
    }

    for (final request in CssParser.extractFromXhtml(source).sources) {
      final media = [?request.media];
      if (request.href case final href?) {
        final target = resolveEditReference(path, href).$1;
        if (Uri.tryParse(target)?.hasScheme ?? true) continue;
        final sheet = cache.putIfAbsent(
          target,
          () => CssParser.parse(session.readText(target)),
        );
        load(target, sheet, media, {target});
      } else {
        load(path, CssParser.parse(request.css ?? ''), media, {});
      }
    }
    return result;
  }

  void _inspectTarget(
    _StyleTarget target,
    String className,
    Map<String, String> values,
    List<ClassStyleConflict> conflicts,
    List<ClassStyleDeclaration> sources,
    Set<String> seen,
  ) {
    for (final sourced in target.rules) {
      final matching = sourced.selectors.selectors
          .where((s) => s.matches(target.element, target.ancestors))
          .toList();
      if (matching.isEmpty) continue;
      for (final declaration in sourced.rule.declarations) {
        final key =
            '${sourced.path}|${sourced.rule.selector}|${declaration.property}|${declaration.value}|${sourced.media}';
        if (seen.add(key)) {
          sources.add(
            ClassStyleDeclaration(
              path: sourced.path,
              selector: sourced.rule.selector,
              property: declaration.property,
              value: declaration.value,
              important: declaration.important,
              media: sourced.media.isEmpty ? null : sourced.media.join(' / '),
            ),
          );
        }
      }
      final stronger = matching.any(
        (s) => s.specificity.compareTo(const Specificity(0, 0, 1, 0)) > 0,
      );
      final sharedOtherClass =
          sourced.path == session.metadata['classStylesheet'] &&
          target.node.classes.any((name) => _isClassRule(sourced.rule, name)) &&
          !_isClassRule(sourced.rule, className);
      if (sourced.path == session.metadata['classStylesheet'] &&
          _isClassRule(sourced.rule, className) &&
          sourced.media.isEmpty) {
        continue;
      }
      for (final entry in values.entries) {
        if (!_ruleConflicts(target, sourced.rule, entry)) continue;
        if (!stronger &&
            !sharedOtherClass &&
            !sourced.rule.declarations.any((d) => d.important)) {
          continue;
        }
        conflicts.add(
          ClassStyleConflict(
            target.node.path,
            sourced.rule.selector,
            entry.key,
            sharedOtherClass
                ? '多个 class 在同一元素上要求不同值'
                : sourced.media.isNotEmpty
                ? '条件规则可能覆盖此属性：${sourced.media.join(' / ')}'
                : '更高优先级的作者声明',
          ),
        );
      }
    }
    final inline = CssParser.parseInlineDeclarations(
      target.node.attributes['style'] ?? '',
    );
    for (final entry in values.entries) {
      if (_ruleConflicts(
        target,
        CssRule(selector: '*', declarations: inline),
        entry,
      )) {
        conflicts.add(
          ClassStyleConflict(
            target.node.path,
            '[style]',
            entry.key,
            '内联样式覆盖此属性',
          ),
        );
      }
    }
  }
}

bool _ruleConflicts(
  _StyleTarget target,
  CssRule rule,
  MapEntry<String, String> proposal,
) {
  for (final declaration in rule.declarations) {
    final property = declaration.property;
    final covers =
        property == proposal.key ||
        proposal.key.startsWith('$property-') ||
        (property == 'all' && !proposal.key.startsWith('--')) ||
        (property == 'font' && proposal.key == 'line-height');
    final contextual =
        const {
          'inherit',
          'initial',
          'unset',
          'revert',
          'revert-layer',
        }.contains(declaration.value.trim()) ||
        declaration.value.contains('var(');
    if (covers && contextual && declaration.value != proposal.value) {
      return true;
    }
  }
  final computed = Cascade.compute(
    element: target.element,
    ancestors: target.ancestors,
    rules: [
      CascadeRule(
        rule: CssRule(selector: '*', declarations: rule.declarations),
        origin: CascadeOrigin.author,
      ),
    ],
  );
  final expected = Cascade.compute(
    element: target.element,
    ancestors: target.ancestors,
    rules: [
      CascadeRule(
        rule: CssRule(
          selector: '*',
          declarations: CssParser.parseInlineDeclarations(
            '${proposal.key}: ${proposal.value}',
          ),
        ),
        origin: CascadeOrigin.author,
      ),
    ],
  );
  final raw = computed.values[proposal.key];
  return raw != null && raw != expected.values[proposal.key];
}

class _EffectiveStyleCache {
  _EffectiveStyleCache(this.width);
  final double width;
  final _elements = <SelectorElement, ComputedStyle>{};
  final _rules = <List<_SourcedRule>, List<CascadeRule>>{};

  ComputedStyle forTarget(_StyleTarget target) {
    final rules = _rules.putIfAbsent(
      target.rules,
      () => [
        for (var i = 0; i < target.rules.length; i++)
          CascadeRule(
            rule: CssRule(
              selector: target.rules[i].rule.selector,
              declarations: target.rules[i].rule.declarations,
              mediaConditions: target.rules[i].media,
            ),
            origin: CascadeOrigin.author,
            order: i,
          ),
      ],
    );
    ComputedStyle? parent;
    final ancestors = <SelectorElement>[];
    for (final element in [...target.ancestors, target.element]) {
      parent =
          _elements[element] ??
          Cascade.compute(
            element: element,
            ancestors: ancestors,
            rules: rules,
            parent: parent,
            containingWidth: width,
            viewportWidth: width,
            inlineDeclarations: CssParser.parseInlineDeclarations(
              element.attributes['style'] ?? '',
            ),
          );
      _elements[element] = parent;
      ancestors.add(element);
    }
    return parent!;
  }
}
