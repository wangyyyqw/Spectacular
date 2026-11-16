import 'package:xml/xml.dart';

import '../position/cfi.dart';
import 'cfi_children.dart';

/// 失效 CFI 的容错结果。
class CfiResolution {
  /// 创建结果。
  const CfiResolution({
    this.cfi,
    this.exact = false,
    this.adjusted = false,
    this.warnings = const <String>[],
    this.textOffset,
  });

  /// 解析后的最近可定位 CFI；完全失败时为 null。
  final EpubCfi? cfi;

  /// 是否与输入完全一致。
  final bool exact;

  /// 是否发生回退/钳制。
  final bool adjusted;

  /// 告警。
  final List<String> warnings;

  /// 文本偏移（若定位到文本节点）。
  final int? textOffset;

  /// 是否定位成功。
  bool get ok => cfi != null;
}

/// 在章节 XHTML 中容错解析 CFI。
///
/// 节点删除、嵌套变化、字符越界时回退到最近可定位节点，并返回 warning；
/// 解析失败不抛异常。
abstract final class CfiResolver {
  /// 解析 [target] 到当前章节。
  static CfiResolution resolve({
    required String xhtml,
    required EpubCfi target,
    int? expectedSpineIndex,
  }) {
    final warnings = <String>[];
    try {
      final point = target.isRange ? target.rangeStart : target;
      if (point == null) {
        return const CfiResolution(warnings: <String>['CFI 不是可解析的点']);
      }
      final itemref = point.itemref;
      if (itemref == null || itemref.isOdd) {
        return const CfiResolution(warnings: <String>['CFI 缺少合法 itemref']);
      }
      if (expectedSpineIndex != null &&
          itemref != (expectedSpineIndex + 1) * 2) {
        return const CfiResolution(
          warnings: <String>['CFI 的 itemref 与当前章节不匹配'],
        );
      }

      final document = XmlDocument.parse(
        xhtml,
        entityMapping: cfiEntityMapping,
      );
      final body = _firstElement(document, 'body');
      if (body == null) {
        return const CfiResolution(warnings: <String>['XHTML 缺少 body']);
      }

      var current = body;
      var adjusted = false;
      CfiChild<XmlNode>? textChunk;

      for (final step in point.steps) {
        if (step.index.isEven) {
          final elements = current.childElements.toList(growable: false);
          final desired = step.index ~/ 2;
          var candidate = desired >= 1 && desired <= elements.length
              ? elements[desired - 1]
              : null;
          if (candidate == null) {
            adjusted = true;
            warnings.add('步骤 ${step.toCfi()} 不存在，回退到最近节点');
            if (elements.isEmpty) {
              break;
            }
            candidate = elements.last;
          }

          final assertion = step.assertion;
          if (assertion != null && assertion.isNotEmpty) {
            final actualId = candidate.getAttribute('id')?.trim();
            if (actualId != assertion) {
              adjusted = true;
              final byId = _findById(body, assertion);
              if (byId != null) {
                candidate = byId;
                warnings.add('结构变化，按 id 断言定位：$assertion');
              } else {
                warnings.add('id 断言不存在，保留最近节点：$assertion');
              }
            }
          }
          current = candidate;
        } else {
          final texts = xmlCfiChildren(current)
              .where((child) => child.index.isOdd)
              .toList(growable: false);
          final desired = (step.index + 1) ~/ 2;
          if (desired >= 1 && desired <= texts.length) {
            textChunk = texts[desired - 1];
          } else {
            adjusted = true;
            warnings.add('文本节点不存在，回退到最近文本或元素');
            for (final text in texts.reversed) {
              if (text.text.isNotEmpty) {
                textChunk = text;
                break;
              }
            }
          }
          break;
        }
      }

      final path = _pathTo(body, current);
      if (path == null) {
        return CfiResolution(warnings: <String>[...warnings, '无法计算最近节点路径']);
      }

      int? offset;
      if (textChunk != null && point.charOffset != null) {
        final rawOffset = point.charOffset!;
        if (rawOffset < 0 || rawOffset > textChunk.text.length) {
          adjusted = true;
          warnings.add('字符偏移越界（$rawOffset/${textChunk.text.length}），已钳制');
        }
        offset = rawOffset.clamp(0, textChunk.text.length);
      } else if (point.charOffset != null && textChunk == null) {
        adjusted = true;
        warnings.add('目标不是文本节点，忽略字符偏移');
      }

      final builder = CfiBuilder().itemRef(itemref).body(point.body ?? 4);
      for (final step in path) {
        builder.step(step.index, assertion: step.assertion);
      }
      if (textChunk != null) {
        builder.step(textChunk.index);
        if (offset != null) {
          builder.charOffset(offset);
        }
      }
      builder.side(point.side);
      final resolved = builder.build();
      return CfiResolution(
        cfi: resolved,
        exact: !adjusted && resolved.serialize() == target.serialize(),
        adjusted: adjusted,
        warnings: List<String>.unmodifiable(warnings),
        textOffset: offset,
      );
    } on FormatException catch (error) {
      return CfiResolution(
        warnings: <String>[...warnings, 'XHTML/CFI 解析失败：${error.message}'],
      );
    } catch (error) {
      return CfiResolution(warnings: <String>[...warnings, 'CFI 容错失败：$error']);
    }
  }

  static XmlElement? _firstElement(XmlNode node, String localName) {
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) {
        return element;
      }
    }
    return null;
  }

  static XmlElement? _findById(XmlElement body, String id) {
    for (final element in body.descendants.whereType<XmlElement>()) {
      if (element.getAttribute('id')?.trim() == id) {
        return element;
      }
    }
    return null;
  }

  static List<CfiStep>? _pathTo(XmlElement body, XmlElement target) {
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
}
