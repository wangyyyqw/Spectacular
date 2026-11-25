import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import 'css_completion.dart';
import 'editor_icon.dart';

typedef CssCompletionReplace = void Function(
  int start,
  int end,
  String text,
  int caret,
);

/// 两种编辑输入共用候选列表；仅处理当前焦点内的补全按键。
class CssCompletionOverlay extends StatefulWidget {
  const CssCompletionOverlay({
    super.key,
    required this.editing,
    required this.focusNode,
    required this.read,
    required this.replace,
    required this.caretRect,
    required this.child,
    this.mode = CssCompletionMode.stylesheet,
    this.property,
    this.enabled = true,
  });

  final Listenable editing;
  final FocusNode focusNode;
  final TextEditingValue Function() read;
  final CssCompletionReplace replace;
  final Rect? Function() caretRect;
  final Widget child;
  final CssCompletionMode mode;
  final String? property;
  final bool enabled;

  @override
  State<CssCompletionOverlay> createState() => _CssCompletionOverlayState();
}

class _CssCompletionOverlayState extends State<CssCompletionOverlay>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _tapGroup = Object();
  late TextEditingValue _previous;
  CssCompletionRequest? _request;
  OverlayEntry? _overlay;
  int _index = 0;
  bool _scheduled = false;
  static const _rowHeight = 38.0;

  @override
  void initState() {
    super.initState();
    _previous = widget.read();
    widget.editing.addListener(_changed);
    widget.focusNode.addListener(_focusChanged);
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CssCompletionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing != widget.editing) {
      oldWidget.editing.removeListener(_changed);
      widget.editing.addListener(_changed);
      _previous = widget.read();
      _dismiss();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
    if (!widget.enabled ||
        oldWidget.mode != widget.mode ||
        oldWidget.property != widget.property) {
      _dismiss();
    }
  }

  @override
  void didChangeMetrics() => _dismiss();

  void _focusChanged() {
    if (!widget.focusNode.hasFocus) _dismiss();
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final value = widget.read();
      if (value == _previous) return;
      final changed = value.text != _previous.text;
      _previous = value;
      if (changed) {
        _show();
      } else {
        _dismiss();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool get _canComplete {
    if (!widget.enabled || !widget.focusNode.hasFocus) return false;
    final value = widget.read();
    return value.selection.isValid &&
        value.selection.isCollapsed &&
        (!value.composing.isValid || value.composing.isCollapsed);
  }

  void _show({bool explicit = false}) {
    _dismiss();
    if (!_canComplete) return;
    final value = widget.read();
    _previous = value;
    _request = completeCss(
      value.text,
      value.selection.extentOffset,
      mode: widget.mode,
      property: widget.property,
      explicit: explicit,
    );
    if (_request == null ||
        _request!.items.isEmpty ||
        widget.caretRect() == null) {
      _request = null;
      return;
    }
    _index = 0;
    _overlay = OverlayEntry(builder: _panel);
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  void _dismiss() {
    _request = null;
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is KeyUpEvent || !_canComplete) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.space &&
        keys.isControlPressed &&
        !keys.isAltPressed &&
        !keys.isMetaPressed) {
      _show(explicit: true);
      return KeyEventResult.handled;
    }
    if (_request == null ||
        keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed ||
        keys.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.tab:
        _accept(_index);
      case LogicalKeyboardKey.escape:
        _dismiss();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _move(int direction) {
    _index = (_index + direction) % _request!.items.length;
    _overlay?.markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final top = _index * _rowHeight;
      final end = top + _rowHeight - _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (end > _scroll.offset) {
        _scroll.jumpTo(end.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  void _accept(int index) {
    if (!_canComplete || _request == null) return;
    if (widget.read() != _previous) {
      _show();
      return;
    }
    final request = _request!;
    final item = request.items[index];
    _dismiss();
    widget.replace(
      request.start,
      request.end,
      item.insertText,
      request.start + item.caretOffset,
    );
    _previous = widget.read();
    if (item.continueValues) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(explicit: true);
      });
    }
  }

  Widget _panel(BuildContext overlayContext) {
    final request = _request;
    final caret = widget.caretRect();
    if (request == null || caret == null) return const SizedBox();
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final point = overlay.globalToLocal(caret.topLeft);
    final width = math.min(380.0, overlay.size.width - 16);
    final desiredHeight = math.min(request.items.length, 6) * _rowHeight + 52;
    final below = overlay.size.height - point.dy - caret.height - 12;
    final above = point.dy - 12;
    final upwards = below < desiredHeight && above > below;
    final height = math.min(
      desiredHeight,
      math.max(60.0, upwards ? above : below),
    );
    final x = point.dx.clamp(
      8.0,
      math.max(8.0, overlay.size.width - width - 8),
    );
    final y = upwards ? point.dy - height - 4 : point.dy + caret.height + 4;
    return Positioned(
      left: x.toDouble(),
      top: y.clamp(8.0, overlay.size.height - height),
      width: width,
      height: height,
      child: ExcludeFocus(
        child: TextFieldTapRegion(
          child: CodeEditorTapRegion(
            child: TapRegion(groupId: _tapGroup, child: _content(request)),
          ),
        ),
      ),
    );
  }

  Widget _content(CssCompletionRequest request) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: const ValueKey('css-completion-menu'),
      color: colors.surface,
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                EditorIcon(
                  EditorGlyph.code,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    request.label,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                Text(
                  '${request.items.length}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: request.items.length,
              itemBuilder: (_, index) => _option(request.items[index], index),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '↑↓ 选择   Tab / Enter 接受   Esc 关闭',
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(CssCompletionItem item, int index) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: _index == index,
      button: true,
      child: InkWell(
        key: ValueKey('css-completion-${item.label}'),
        onTap: () => _accept(index),
        child: Container(
          color: _index == index ? colors.primaryContainer : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _index == index
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  item.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: _tapGroup,
    onTapOutside: (_) => _dismiss(),
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        _dismiss();
        return false;
      },
      child: widget.child,
    ),
  );

  @override
  void dispose() {
    _dismiss();
    widget.editing.removeListener(_changed);
    widget.focusNode.removeListener(_focusChanged);
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }
}
