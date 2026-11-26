import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:re_editor/re_editor.dart';

import 'css_completion.dart';
import 'css_completion_overlay.dart';

/// 使用编辑器公开的行布局信息，将补全菜单定位到折叠和换行后的光标。
class CssCodeCompletion extends StatefulWidget {
  const CssCodeCompletion({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.builder,
    this.readOnly = false,
    this.mode = CssCompletionMode.stylesheet,
  });
  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final Widget Function(CodeIndicatorBuilder indicator) builder;
  final bool readOnly;
  final CssCompletionMode mode;

  @override
  State<CssCodeCompletion> createState() => _CssCodeCompletionState();
}

class _CssCodeCompletionState extends State<CssCodeCompletion> {
  final _gutter = GlobalKey();
  CodeIndicatorValueNotifier? _lines;

  TextEditingValue _read() {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.unfoldLineSelection;
    int offset(int line, int column) =>
        text
            .split('\n')
            .take(line)
            .fold<int>(0, (sum, text) => sum + text.length + 1) +
        column;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: offset(selection.baseIndex, selection.baseOffset),
        extentOffset: offset(selection.extentIndex, selection.extentOffset),
      ),
      composing: controller.isComposing
          ? const TextRange(start: 0, end: 1)
          : TextRange.empty,
    );
  }

  CodeLinePosition _position(int offset) {
    final controller = widget.controller;
    final prefix = controller.text.substring(0, offset).split('\n');
    var position = controller.lineIndex2Index(prefix.length - 1);
    while (position.chunkIndex >= 0) {
      controller.expandChunk(position.index);
      position = controller.lineIndex2Index(prefix.length - 1);
    }
    return CodeLinePosition(
      index: position.index,
      offset: prefix.last.replaceAll('\r', '').length,
    );
  }

  void _replace(int start, int end, String text, int caret) {
    final controller = widget.controller;
    final from = _position(start), to = _position(end);
    controller.runRevocableOp(() {
      controller.replaceSelection(
        text,
        CodeLineSelection(
          baseIndex: from.index,
          baseOffset: from.offset,
          extentIndex: to.index,
          extentOffset: to.offset,
        ),
      );
      controller.selection = CodeLineSelection.fromPosition(
        position: _position(caret.clamp(0, controller.text.length)),
      );
    });
    controller.makeCursorVisible();
  }

  Rect? _caret() {
    final gutter = _gutter.currentContext?.findRenderObject() as RenderBox?;
    final selection = widget.controller.selection;
    final line = _lines?.value?.paragraphs
        .where((line) => line.index == selection.extentIndex)
        .firstOrNull;
    final offset = line?.getOffset(
      TextPosition(offset: selection.extentOffset),
    );
    if (gutter == null || !gutter.hasSize || line == null || offset == null) {
      return null;
    }
    final point = gutter.localToGlobal(
      Offset(gutter.size.width, 0) + line.offset + offset,
    );
    final viewport = gutter.localToGlobal(Offset.zero) & gutter.size;
    if (point.dy < viewport.top || point.dy > viewport.bottom) return null;
    return point & Size(1, line.preferredLineHeight);
  }

  @override
  Widget build(BuildContext context) => CssCompletionOverlay(
    editing: widget.controller,
    focusNode: widget.focusNode,
    read: _read,
    replace: _replace,
    caretRect: _caret,
    mode: widget.mode,
    enabled: !widget.readOnly,
    child: widget.builder((_, editing, chunks, notifier) {
      _lines = notifier;
      return Row(
        key: _gutter,
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultCodeLineNumber(controller: editing, notifier: notifier),
          DefaultCodeChunkIndicator(
            width: 16,
            controller: chunks,
            notifier: notifier,
          ),
        ],
      );
    }),
  );
}

/// 样式规则与属性表单保留 TextField，复用相同的上下文与键盘补全。
class CssTextCompletion extends StatefulWidget {
  const CssTextCompletion({
    super.key,
    required this.controller,
    required this.builder,
    this.mode = CssCompletionMode.stylesheet,
    this.property,
    this.readOnly = false,
    this.onAccepted,
  });
  final TextEditingController controller;
  final Widget Function(FocusNode focus) builder;
  final CssCompletionMode mode;
  final String? property;
  final bool readOnly;
  final VoidCallback? onAccepted;

  @override
  State<CssTextCompletion> createState() => _CssTextCompletionState();
}

class _CssTextCompletionState extends State<CssTextCompletion> {
  final _field = GlobalKey();
  final _focus = FocusNode();

  RenderEditable? _editable(RenderObject? render) {
    if (render is RenderEditable) return render;
    RenderEditable? found;
    render?.visitChildren((child) {
      found ??= _editable(child);
    });
    return found;
  }

  Rect? _caret() {
    final editable = _editable(_field.currentContext?.findRenderObject());
    if (editable == null || !editable.hasSize) return null;
    final selection = widget.controller.selection;
    if (!selection.isValid) return null;
    final caret = editable.getLocalRectForCaret(selection.extent);
    return editable.localToGlobal(caret.topLeft) & caret.size;
  }

  void _replace(int start, int end, String text, int caret) {
    final next = widget.controller.text.replaceRange(start, end, text);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret.clamp(0, next.length)),
    );
    widget.onAccepted?.call();
  }

  @override
  Widget build(BuildContext context) => CssCompletionOverlay(
    editing: widget.controller,
    focusNode: _focus,
    read: () => widget.controller.value,
    replace: _replace,
    caretRect: _caret,
    mode: widget.mode,
    property: widget.property,
    enabled: !widget.readOnly,
    child: KeyedSubtree(key: _field, child: widget.builder(_focus)),
  );

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
}
