import 'package:flutter/material.dart';

import '../icons/app_icon.dart';

/// 抽屉表单的标题、滚动内容与操作区；键盘出现时只占用可见空间。
class ReaderSheetForm extends StatefulWidget {
  const ReaderSheetForm({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.onClose,
    this.closeEnabled = true,
    this.showCloseButton = true,
    this.contentPadding = const EdgeInsets.all(16),
    this.scrollContent = true,
  });

  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final VoidCallback? onClose;

  /// 控制标题栏关闭按钮；未提供回调时仍沿用默认的返回操作。
  final bool closeEnabled;
  final bool showCloseButton;
  final EdgeInsetsGeometry contentPadding;

  /// 普通表单由骨架滚动；已有 ListView 等内容可直接使用有界视口。
  final bool scrollContent;

  @override
  State<ReaderSheetForm> createState() => _ReaderSheetFormState();
}

class _ReaderSheetFormState extends State<ReaderSheetForm> {
  final _headerKey = GlobalKey();
  final _actionsKey = GlobalKey();
  final _bodyKey = GlobalKey();
  double? _headerHeight;
  double? _actionsHeight;
  bool _measurePending = false;

  void _measureChrome() {
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (!mounted) return;
      final headerHeight = _headerKey.currentContext?.size?.height;
      final actionsHeight = _actionsKey.currentContext?.size?.height ?? 0;
      if (headerHeight == _headerHeight && actionsHeight == _actionsHeight) {
        return;
      }
      setState(() {
        _headerHeight = headerHeight;
        _actionsHeight = actionsHeight;
      });
    });
  }

  Widget _observeChrome(Widget child) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _measureChrome();
          return false;
        },
        child: SizeChangedLayoutNotifier(child: child),
      );

  // 内容变化先按上次尺寸裁切一帧，再使用实际测量切换布局，避免布局溢出。
  Widget _fixedChrome(Widget child, double height) => SizedBox(
    height: height,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: _observeChrome(child),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: _headerKey,
      padding: EdgeInsets.fromLTRB(
        20,
        6,
        widget.showCloseButton ? 8 : 20,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(
              style: theme.textTheme.titleMedium!.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              child: widget.title,
            ),
          ),
          if (widget.showCloseButton)
            IconButton(
              tooltip: '关闭',
              color: theme.colorScheme.onSurfaceVariant,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: widget.closeEnabled
                  ? widget.onClose ?? () => Navigator.maybePop(context)
                  : null,
              icon: const AppIcon(AppGlyph.close, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _actions() => Padding(
    key: _actionsKey,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 8,
      overflowSpacing: 8,
      children: widget.actions,
    ),
  );

  bool _needsScrolling(BoxConstraints constraints) {
    final hasActions = widget.actions.isNotEmpty;
    final fixedHeight =
        (_headerHeight ?? 0) + (hasActions ? (_actionsHeight ?? 0) + 1 : 0) + 1;
    final measured =
        _headerHeight != null && (!hasActions || _actionsHeight != null);
    // 标题与操作占用实际高度；输入区至少留出一行可操作空间。
    final minimumBodyHeight = widget.content == null ? 0 : 64;
    return !measured || fixedHeight + minimumBodyHeight > constraints.maxHeight;
  }

  Widget _scrollingLayout(
    Widget header,
    Widget body,
    Widget buttons,
    BoxConstraints constraints,
  ) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _observeChrome(header),
        const Divider(height: 1),
        if (widget.scrollContent)
          body
        else
          SizedBox(height: constraints.maxHeight, child: body),
        if (widget.actions.isNotEmpty) _observeChrome(buttons),
      ],
    ),
  );

  Widget _fixedLayout(Widget header, Widget body, Widget buttons) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _fixedChrome(header, _headerHeight!),
      const Divider(height: 1),
      if (widget.content != null)
        Flexible(
          child: widget.scrollContent
              ? SingleChildScrollView(child: body)
              : body,
        ),
      if (widget.actions.isNotEmpty) ...[
        const Divider(height: 1),
        _fixedChrome(buttons, _actionsHeight!),
      ],
    ],
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final header = _header(context);
    final body = KeyedSubtree(
      key: _bodyKey,
      child: Padding(
        padding: widget.contentPadding,
        child: widget.content ?? const SizedBox.shrink(),
      ),
    );
    final buttons = _actions();
    return _needsScrolling(constraints)
        ? _scrollingLayout(header, body, buttons, constraints)
        : _fixedLayout(header, body, buttons);
  }

  @override
  Widget build(BuildContext context) {
    _measureChrome();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: double.infinity,
            child: LayoutBuilder(builder: _layout),
          ),
        ),
      ),
    );
  }
}
