import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面书籍共用键盘焦点、悬停反馈与键盘菜单，封面尺寸不随状态变化。
class DesktopBookInteraction extends StatefulWidget {
  const DesktopBookInteraction({
    super.key,
    required this.onActivate,
    required this.onSelect,
    required this.onMenu,
    required this.child,
  });

  final VoidCallback onActivate;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  State<DesktopBookInteraction> createState() => _DesktopBookInteractionState();
}

class _DesktopBookInteractionState extends State<DesktopBookInteraction> {
  final _focus = FocusNode(debugLabel: 'desktop-book');
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _menu() {
    final box = context.findRenderObject()! as RenderBox;
    widget.onMenu(box.localToGlobal(Offset(box.size.width / 2, 24)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
            widget.onActivate,
        const SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          includeRepeats: false,
        ): widget.onActivate,
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
            widget.onSelect,
        const SingleActivator(
          LogicalKeyboardKey.space,
          shift: true,
          includeRepeats: false,
        ): widget.onSelect,
        const SingleActivator(
          LogicalKeyboardKey.f10,
          shift: true,
          includeRepeats: false,
        ): _menu,
        const SingleActivator(
          LogicalKeyboardKey.contextMenu,
          includeRepeats: false,
        ): _menu,
      },
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          child: Container(
            foregroundDecoration: BoxDecoration(
              color: _hovered ? colors.primary.withValues(alpha: .05) : null,
              borderRadius: BorderRadius.circular(4),
              border: _focused
                  ? Border.all(color: colors.primary, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
