import 'package:reader_core/api.dart' show EpubNode;
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';

/// 原始文档元素的只读选择器视图，保留真实兄弟与源码身份。
class ChapterNodeView implements SelectorElement {
  const ChapterNodeView(
    this.tag,
    this.attributes,
    this.childElements, {
    this.cacheIdentity = '',
  });

  @override
  final String tag;
  @override
  final Map<String, String> attributes;
  @override
  final List<SelectorElement> childElements;
  final String cacheIdentity;
}

/// 原始元素与聚合节点之间的选择器坐标桥，不持有章节源或分页结果。
class ChapterSelectors {
  ChapterSelectors(ParsedElement root) {
    _build(root);
    _index(root, const []);
  }

  ChapterSelectors._();

  final Map<String, List<SelectorElement>> _chains = {};
  final Map<String, ChapterNodeView> _views = {};
  final Map<Map<String, String>, List<SelectorElement>> _imageChains = {};
  final Map<String, List<List<SelectorElement>>> _imageChainsBySrc = {};
  final Map<Map<String, String>, String> _imageCfis = {};
  final Map<String, List<String>> _imageCfisBySrc = {};

  Iterable<List<SelectorElement>> get chains => _chains.values;

  /// 原始元素可按源码身份直接取链，不逐一查找属性集合。
  List<SelectorElement> chainForElement(ParsedElement element) =>
      _chains[_key(element.tag, element.start, element.end)] ?? const [];

  /// 阅读作业可在结构遍历中执行时间预算与取消检查。
  static Future<ChapterSelectors> prepare(
    ParsedElement root, {
    Future<void> Function()? checkpoint,
  }) async {
    final result = ChapterSelectors._();
    await result._buildAsync(root, checkpoint);
    await result._indexAsync(root, const [], checkpoint);
    return result;
  }

  ChapterNodeView _createView(
    ParsedElement element,
    List<SelectorElement> children,
  ) {
    final view = ChapterNodeView(
      element.tag,
      element.attributes,
      List<SelectorElement>.unmodifiable(children),
      cacheIdentity: '${element.start}:${element.end}',
    );
    _views[_key(element.tag, element.start, element.end)] = view;
    return view;
  }

  ChapterNodeView _build(ParsedElement element) => _createView(element, [
    for (final child in element.children.whereType<ParsedElement>())
      _build(child),
  ]);

  Future<ChapterNodeView> _buildAsync(
    ParsedElement element,
    Future<void> Function()? checkpoint,
  ) async {
    final children = <SelectorElement>[];
    for (final child in element.children.whereType<ParsedElement>()) {
      children.add(await _buildAsync(child, checkpoint));
    }
    if (checkpoint != null) await checkpoint();
    return _createView(element, children);
  }

  List<SelectorElement> _recordChain(
    ParsedElement element,
    List<SelectorElement> ancestors,
  ) {
    final key = _key(element.tag, element.start, element.end);
    final chain = List<SelectorElement>.unmodifiable([
      ...ancestors,
      _views[key]!,
    ]);
    _chains[key] = chain;
    if (const {'img', 'image', 'object'}.contains(element.tag)) {
      _imageChains[element.attributes] = chain;
      _imageCfis[element.attributes] = element.cfi.serialize();
      final src = _imageSource(element.attributes);
      if (src != null) {
        (_imageChainsBySrc[src] ??= []).add(chain);
        (_imageCfisBySrc[src] ??= []).add(element.cfi.serialize());
      }
    }
    return chain;
  }

  void _index(ParsedElement element, List<SelectorElement> ancestors) {
    final chain = _recordChain(element, ancestors);
    for (final child in element.children.whereType<ParsedElement>()) {
      _index(child, chain);
    }
  }

  Future<void> _indexAsync(
    ParsedElement element,
    List<SelectorElement> ancestors,
    Future<void> Function()? checkpoint,
  ) async {
    if (checkpoint != null) await checkpoint();
    final chain = _recordChain(element, ancestors);
    for (final child in element.children.whereType<ParsedElement>()) {
      await _indexAsync(child, chain, checkpoint);
    }
  }

  List<SelectorElement>? chainOf(EpubNode node) {
    final (tag, start, end, attributes) = switch (node) {
      InlineNode() => (node.tag, node.start, node.end, node.attributes),
      BlockNode() => (node.tag, node.start, node.end, node.attributes),
      _ => ('', -1, -1, const <String, String>{}),
    };
    if (const {'img', 'image', 'object'}.contains(tag)) {
      final exact = _imageChains[attributes];
      if (exact != null) return exact;
      final src = _imageSource(attributes);
      final sameSrc = src == null ? null : _imageChainsBySrc[src];
      if (sameSrc?.length == 1) return sameSrc!.single;
    }
    return _chains[_key(tag, start, end)];
  }

  static String? _imageSource(Map<String, String> attributes) =>
      attributes['src'] ??
      attributes['xlink:href'] ??
      attributes['href'] ??
      attributes['data'];

  /// 聚合折叠后的图片仍返回原始元素位置，不使用外层容器的 CFI。
  String? imageCfiOf(EpubNode node) {
    final attributes = switch (node) {
      BlockNode() => node.attributes,
      InlineNode() => node.attributes,
      _ => const <String, String>{},
    };
    return imageCfiForAttributes(attributes);
  }

  /// 行内标记保留原始属性身份；重复引用必须命中各自元素，不能猜位置。
  String? imageCfiForAttributes(Map<String, String> attributes) =>
      _imageCfis[attributes] ?? imageCfiForSource(_imageSource(attributes));

  String? imageCfiForSource(String? source) {
    final values = source == null ? null : _imageCfisBySrc[source];
    return values?.length == 1 ? values!.single : null;
  }

  static String _key(String tag, int start, int end) => '$tag:$start:$end';

  /// 相同样式形状可复用；依赖兄弟位置时加入源码身份，防止串用。
  static String chainKey(
    List<SelectorElement> chain,
    Map<SelectorElement, String> viewKeys,
    CascadeRuleSet rules,
  ) => chain
      .map(
        (view) => viewKeys.putIfAbsent(view, () {
          final keys = view.attributes.keys.toList()..sort();
          final attributes = [
            for (final key in keys) '$key=${view.attributes[key]}',
          ].join(';');
          final identity =
              view is ChapterNodeView &&
                  rules.candidatesFor(view).usesTreePosition
              ? view.cacheIdentity
              : '';
          return '${view.tag}|$attributes|$identity';
        }),
      )
      .join('>');
}

/// 一次作业的生成节点视图与链键缓存，禁止跨排版任务共享。
class ChapterSelectorViews {
  ChapterSelectorViews(this.index);

  final ChapterSelectors index;
  final Map<EpubNode, SelectorElement> _fallbackViews = {};
  final Map<SelectorElement, String> _viewKeys = {};
  int _generatedIdentity = 0;

  SelectorElement viewOf(EpubNode node) {
    final original = index.chainOf(node)?.last;
    if (original != null) return original;
    return _fallbackViews.putIfAbsent(node, () {
      final (tag, attributes, children) = switch (node) {
        BlockNode() => (node.tag, node.attributes, node.children),
        InlineNode() => (node.tag, node.attributes, node.children),
        _ => ('reader-anonymous', const <String, String>{}, const <EpubNode>[]),
      };
      return ChapterNodeView(tag, attributes, [
        for (final child in children)
          if (child is BlockNode || child is InlineNode) viewOf(child),
      ], cacheIdentity: 'generated:${_generatedIdentity++}');
    });
  }

  String keyFor(List<SelectorElement> chain, CascadeRuleSet rules) =>
      ChapterSelectors.chainKey(chain, _viewKeys, rules);
}
