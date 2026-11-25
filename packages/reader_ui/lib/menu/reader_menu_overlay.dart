import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/reader_ink.dart';
import '../theme/reader_panel_theme.dart';
import '../theme/reader_theme.dart';
import '../theme/reader_frosted_surface.dart';

const _fallbackTheme = ReaderTheme(
  id: 'fallback',
  name: '默认',
  background: Color(0xFFF5EFE0),
  text: Color(0xFF3B3228),
);

const double _topRowHeight = 48;
const double _dividerHeight = .5;
const double _progressTopPadding = 6;
const double _progressRowHeight = 34;

/// 底部菜单栏的实际高度（含安全区），供宿主把底部悬浮控件摆在菜单栏上方。
double readerMenuBarHeight(BuildContext context, {double safeBottom = 0}) {
  final viewBottom = MediaQuery.paddingOf(context).bottom;
  final bottomInset = viewBottom > safeBottom ? viewBottom : safeBottom;
  return _topRowHeight +
      _dividerHeight +
      _progressTopPadding +
      _progressRowHeight +
      _EntriesRow.padding.vertical +
      _EntriesRow.itemHeight +
      bottomInset;
}

/// 抽屉面板类型（设计稿底部四个入口）。
enum ReaderMenuEntry {
  /// 目录。
  toc,

  /// 主题与背景。
  theme,

  /// 排版（字号/行高/段距/边距）。
  type,

  /// 其它设置。
  settings,
}

/// 沉浸式阅读菜单（样式对齐设计稿 `.menu-top` / `.menu-bottom` / `.drawer`）。
///
/// 顶部栏：返回 + 书名 + 日夜切换（+ 听书）；底部栏：进度滑杆 + 四入口 +
/// Home 指示条；点抽屉外区域关闭抽屉，再点关闭菜单（由调用方处理）。
class ReaderMenuOverlay extends StatelessWidget {
  /// 创建菜单层。
  const ReaderMenuOverlay({
    super.key,
    required this.open,
    required this.theme,
    required this.bookTitle,
    required this.progress,
    required this.chapterLabel,
    required this.onBack,
    required this.onToggleDayNight,
    required this.nightMode,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onSeek,
    required this.onEntry,
    required this.drawerTitle,
    required this.drawerChild,
    required this.onCloseDrawer,
    this.drawerEntry,
    this.inkMode = false,
    this.safeBottom = 0,
    this.onTts,
    this.onEdit,
    this.onAddBookmark,
    this.bookmarked = false,
    this.onShowShortcuts,
  });

  /// 菜单是否展开（设计稿 `.menu-open`）。
  final bool open;

  /// 当前阅读主题（取背景/文字/分隔线色）。
  final ReaderTheme? theme;

  /// 书名。
  final String bookTitle;

  /// 全书进度 0..1（滑杆位置）。
  final double progress;

  /// 滑杆气泡文案（如「第 7 章 · 3/12 页」）。
  final String chapterLabel;

  /// 返回书架。
  final VoidCallback onBack;

  /// 切换日间/夜间。
  final VoidCallback onToggleDayNight;

  /// 当前页书签入口，所有阅读模式共用。
  final VoidCallback? onAddBookmark;
  final bool bookmarked;

  /// 当前是否夜间（决定图标）。
  final bool nightMode;

  /// 上一章 / 下一章；无相邻章节时传 null，按钮禁用。
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  /// 拖动滑杆（0..1）。
  final ValueChanged<double> onSeek;

  /// 点击四入口。
  final ValueChanged<ReaderMenuEntry> onEntry;

  /// 抽屉名称，用于下拉把手的无障碍标签。
  final String drawerTitle;

  /// 抽屉内容。
  final Widget? drawerChild;

  /// 关闭抽屉。
  final VoidCallback onCloseDrawer;

  /// 抽屉底部固定导航的当前项。
  final ReaderMenuEntry? drawerEntry;

  /// 墨水屏模式：主题固定为纯黑白，禁用日夜切换。
  final bool inkMode;

  /// 底部安全区。
  final double safeBottom;

  /// 听书（为 null 时不显示入口图标）。
  final VoidCallback? onTts;

  /// 宿主原文编辑器入口。
  final VoidCallback? onEdit;

  final VoidCallback? onShowShortcuts;

  static const Duration _enter = Duration(milliseconds: 280);
  static const Duration _exit = Duration(milliseconds: 200);
  static const Curve _ease = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final panelTheme = theme ?? _fallbackTheme;
    final fg = panelTheme.text;
    final line = theme?.line ?? fg.withValues(alpha: 0.12);
    final fill = theme?.fill ?? fg.withValues(alpha: 0.08);
    final reduceMotion = inkMode || MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : (open ? _enter : _exit);

    final bottomBar = Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _SlidingMenuBar(
        open: open,
        closedOffset: const Offset(0, 1.01),
        duration: duration,
        child: IgnorePointer(
          ignoring: !open,
          child: ExcludeFocus(
            excluding: drawerChild != null,
            child: ReaderFrostedSurface(
              key: const ValueKey('reader-menu-bottom-surface'),
              radius: 0,
              inkMode: inkMode,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: _topRowHeight,
                      child: Row(
                        children: <Widget>[
                          _IconButton(
                            icon: AppGlyph.arrowBack,
                            iconSize: 22,
                            color: fg,
                            onTap: onBack,
                            tooltip: '返回书架',
                            buttonKey: const ValueKey<String>('menu-back'),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              bookTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: fg),
                            ),
                          ),
                          const Spacer(),
                          if (onShowShortcuts != null)
                            _IconButton(
                              icon: AppGlyph.info,
                              color: fg,
                              onTap: onShowShortcuts,
                              tooltip: '桌面操作与快捷键（F1）',
                            ),
                          _IconButton(
                            icon: nightMode
                                ? AppGlyph.lightMode
                                : AppGlyph.darkMode,
                            iconSize: 19,
                            color: fg,
                            onTap: inkMode ? null : onToggleDayNight,
                            tooltip: inkMode
                                ? '墨水屏模式固定纯黑白'
                                : nightMode
                                ? '日间'
                                : '夜间',
                            buttonKey: const ValueKey<String>('menu-daynight'),
                          ),
                          if (onAddBookmark != null)
                            _IconButton(
                              icon: bookmarked
                                  ? AppGlyph.bookmark
                                  : AppGlyph.bookmarkAdd,
                              color: fg,
                              onTap: onAddBookmark,
                              tooltip: bookmarked ? '当前页已有书签' : '添加书签',
                              buttonKey: const ValueKey('menu-add-bookmark'),
                            ),
                          if (onEdit != null)
                            _IconButton(
                              icon: AppGlyph.editNote,
                              iconSize: 22,
                              color: fg,
                              onTap: onEdit,
                              tooltip: '编辑书籍',
                              buttonKey: const ValueKey<String>('menu-edit'),
                            ),
                          if (onTts != null)
                            _IconButton(
                              icon: AppGlyph.headphones,
                              iconSize: 19,
                              color: fg,
                              onTap: onTts!,
                              tooltip: '听书',
                              buttonKey: const ValueKey<String>('menu-tts'),
                            ),
                        ],
                      ),
                    ),
                    Container(height: _dividerHeight, color: line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        14,
                        _progressTopPadding,
                        14,
                        0,
                      ),
                      child: _ProgressRow(
                        fg: fg,
                        fill: fill,
                        progress: progress,
                        label: chapterLabel,
                        onPrevious: onPreviousChapter,
                        onNext: onNextChapter,
                        onSeek: onSeek,
                      ),
                    ),
                    _EntriesRow(
                      fg: fg,
                      onEntry: onEntry,
                      safeBottom: safeBottom,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 透明 Material：InkWell/InkResponse 需要 Material 祖先（阅读页本身没有）。
    final overlay = ExcludeFocus(
      excluding: !open,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: <Widget>[
            // 抽屉
            Positioned.fill(
              key: const ValueKey('reader-drawer-host'),
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : _enter,
                reverseDuration: reduceMotion ? Duration.zero : _exit,
                switchInCurve: _ease,
                switchOutCurve: _ease,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [
                    if (current == null && previous.isEmpty) bottomBar,
                    ...previous,
                    ?current,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  final drawer = child as _DrawerLayer;
                  return _DrawerLayer(
                    title: drawer.title,
                    theme: drawer.theme,
                    onClose: drawer.onClose,
                    inkMode: drawer.inkMode,
                    safeBottom: drawer.safeBottom,
                    entry: drawer.entry,
                    onEntry: drawer.onEntry,
                    animation: animation,
                    child: drawer.child,
                  );
                },
                child: drawerChild == null
                    ? null
                    : _DrawerLayer(
                        key: const ValueKey('reader-drawer'),
                        title: drawerTitle,
                        theme: theme,
                        onClose: onCloseDrawer,
                        inkMode: inkMode,
                        safeBottom: safeBottom,
                        entry: drawerEntry,
                        onEntry: onEntry,
                        child: drawerChild!,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    // 菜单与遮罩动画只重绘自身，不让静止的正文和背景重复录制绘图。
    return ReaderPanelTheme(
      theme: panelTheme,
      child: RepaintBoundary(child: overlay),
    );
  }
}

/// 磨砂底板直接采样正文，避免整体淡入的离屏层在末帧撤销时突变。
class _SlidingMenuBar extends StatelessWidget {
  const _SlidingMenuBar({
    required this.open,
    required this.closedOffset,
    required this.duration,
    required this.child,
  });

  final bool open;
  final Offset closedOffset;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Offset>(
    tween: Tween(end: open ? Offset.zero : closedOffset),
    duration: duration,
    curve: ReaderMenuOverlay._ease,
    child: child,
    builder: (context, offset, child) => Offstage(
      // 完全收起后停止绘制，防止屏外阴影和模糊继续影响正文。
      offstage: offset == closedOffset,
      child: FractionalTranslation(translation: offset, child: child),
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.iconSize = 19,
    this.buttonKey,
  });

  final AppGlyph icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;
  final double iconSize;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // 顶部图标不显示点击高亮与水波。
      data: quietInk(Theme.of(context)),
      child: IconButton(
        key: buttonKey,
        icon: AppIcon(
          icon,
          size: iconSize,
          color: color.withValues(alpha: onTap == null ? 0.3 : 0.9),
        ),
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}

/// 进度滑杆行（设计稿 `.slider-row` + `.track` + `.thumb` + `.bubble`）。
class _ProgressRow extends StatefulWidget {
  const _ProgressRow({
    required this.fg,
    required this.fill,
    required this.progress,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  final Color fg;
  final Color fill;
  final double progress;
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<double> onSeek;

  @override
  State<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends State<_ProgressRow> {
  bool _dragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ? _dragValue : widget.progress.clamp(0.0, 1.0);
    return SizedBox(
      height: _progressRowHeight,
      child: Row(
        children: <Widget>[
          _NavButton(
            icon: AppGlyph.skipPrevious,
            label: '上一章',
            color: widget.fg,
            onTap: widget.onPrevious,
            buttonKey: const ValueKey<String>('menu-prev-chapter'),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  key: const ValueKey<String>('menu-progress-slider'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    _seekTo(details.localPosition.dx / width);
                  },
                  onHorizontalDragStart: (details) {
                    setState(() {
                      _dragging = true;
                      _dragValue = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragValue = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final target = _dragValue;
                    setState(() => _dragging = false);
                    widget.onSeek(target);
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      // 轨道
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.fill,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 已读填充
                      FractionallySizedBox(
                        widthFactor: value,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: widget.fg.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 滑块
                      Positioned(
                        left: (width * value - 7).clamp(0.0, width - 14),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: widget.fg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // 气泡
                      if (_dragging)
                        Positioned(
                          left: (width * value - 80).clamp(0.0, width - 160),
                          bottom: 26,
                          child: Container(
                            width: 160,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: widget.fg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          _NavButton(
            icon: AppGlyph.skipNext,
            label: '下一章',
            color: widget.fg,
            onTap: widget.onNext,
            buttonKey: const ValueKey<String>('menu-next-chapter'),
          ),
        ],
      ),
    );
  }

  void _seekTo(double value) {
    widget.onSeek(value.clamp(0.0, 1.0));
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.buttonKey,
  });

  final AppGlyph icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkResponse(
          key: buttonKey,
          onTap: onTap,
          radius: 20,
          child: SizedBox(
            width: 32,
            height: 32,
            child: AppIcon(
              icon,
              size: 22,
              color: color.withValues(alpha: onTap == null ? 0.2 : 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部四入口（设计稿 `.entries`）。
class _EntriesRow extends StatelessWidget {
  const _EntriesRow({
    required this.fg,
    required this.onEntry,
    this.selected,
    this.safeBottom = 0,
    this.keyPrefix = 'menu-entry',
  });

  final Color fg;
  final ValueChanged<ReaderMenuEntry> onEntry;
  final ReaderMenuEntry? selected;
  final double safeBottom;
  final String keyPrefix;

  static const double itemHeight = 48;
  static const padding = EdgeInsets.fromLTRB(0, 6, 0, 22);

  static const Map<ReaderMenuEntry, ({AppGlyph icon, String label})> items =
      <ReaderMenuEntry, ({AppGlyph icon, String label})>{
        ReaderMenuEntry.toc: (icon: AppGlyph.listBulleted, label: '目录'),
        ReaderMenuEntry.theme: (icon: AppGlyph.palette, label: '主题'),
        ReaderMenuEntry.type: (icon: AppGlyph.textFields, label: '排版'),
        ReaderMenuEntry.settings: (icon: AppGlyph.settings, label: '设置'),
      };

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: EdgeInsets.only(bottom: safeBottom),
    child: Padding(
      padding: padding,
      child: Row(
        children: [
          for (final entry in items.entries)
            Expanded(
              child: Semantics(
                selected: selected == entry.key,
                child: InkWell(
                  key: ValueKey<String>('$keyPrefix-${entry.key.name}'),
                  borderRadius: BorderRadius.circular(4),
                  // 底栏入口不显示点击高亮与水波。
                  splashFactory: NoSplash.splashFactory,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  onTap: () => onEntry(entry.key),
                  child: _buildItem(entry.key, entry.value),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildItem(
    ReaderMenuEntry entry,
    ({AppGlyph icon, String label}) item,
  ) {
    final active = selected == null || selected == entry;
    return SizedBox(
      height: itemHeight,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                item.icon,
                size: 20,
                color: fg.withValues(alpha: active ? 1 : 0.65),
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  color: fg.withValues(alpha: active ? 1 : 0.65),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 四个阅读面板共用的凝光抽屉；顶部把手与滚到顶部的内容均可下拉收起。
class _DrawerLayer extends StatefulWidget {
  const _DrawerLayer({
    super.key,
    required this.title,
    required this.theme,
    required this.child,
    required this.onClose,
    required this.inkMode,
    required this.entry,
    required this.onEntry,
    required this.safeBottom,
    this.animation = const AlwaysStoppedAnimation(1),
  });

  final String title;
  final ReaderTheme? theme;
  final Widget child;
  final VoidCallback onClose;
  final bool inkMode;
  final ReaderMenuEntry? entry;
  final ValueChanged<ReaderMenuEntry> onEntry;
  final double safeBottom;
  final Animation<double> animation;

  @override
  State<_DrawerLayer> createState() => _DrawerLayerState();
}

class _DrawerLayerState extends State<_DrawerLayer>
    with SingleTickerProviderStateMixin {
  late final _drag = AnimationController.unbounded(vsync: this);
  double _height = 0;
  bool _closing = false;

  bool get _reduceMotion =>
      widget.inkMode || MediaQuery.disableAnimationsOf(context);

  void _switchEntry(ReaderMenuEntry entry) {
    FocusScope.of(context).unfocus();
    if (entry == widget.entry) {
      _close();
      return;
    }
    _drag.stop();
    _drag.value = 0;
    widget.onEntry(entry);
  }

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  double _move(double delta) {
    if (_closing) return 0;
    _drag.stop();
    final before = _drag.value;
    _drag.value = (before + delta).clamp(0.0, _height);
    return _drag.value - before;
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    widget.onClose();
  }

  void _release(double velocity) {
    if (_closing || _drag.value == 0) return;
    final threshold = (_height * 0.22).clamp(56.0, 120.0);
    if (_drag.value >= threshold || (velocity > 700 && _drag.value > 12)) {
      _close();
    } else {
      _drag.animateTo(
        0,
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      // 抽屉固定在屏幕底部，输入法覆盖底栏而不抬升整块面板。
      const bottom = 0.0;
      _height = (constraints.maxHeight - media.padding.top) * 0.75;
      final bottomInset = media.padding.bottom.clamp(
        widget.safeBottom,
        double.infinity,
      );
      final navigationHeight =
          _EntriesRow.itemHeight + _EntriesRow.padding.vertical + bottomInset;
      final contentHeight = _height - navigationHeight;
      return AnimatedBuilder(
        animation: Listenable.merge([widget.animation, _drag]),
        builder: (context, panel) {
          final exiting = widget.animation.status == AnimationStatus.reverse;
          return IgnorePointer(
            ignoring: exiting || _closing,
            child: ExcludeFocus(
              excluding: exiting || _closing,
              child: ExcludeSemantics(
                excluding: exiting || _closing,
                child: _buildLayers(
                  panel!,
                  bottom,
                  navigationHeight,
                  contentHeight,
                ),
              ),
            ),
          );
        },
        // 动画只更新遮罩和露出高度，主题、导航与面板内容复用同一棵子树。
        child: _buildPanel(
          Column(
            children: [
              _buildHandle(),
              Expanded(child: _buildScrollableContent()),
            ],
          ),
          contentHeight,
        ),
      );
    },
  );

  Widget _buildLayers(
    Widget panel,
    double bottom,
    double navigationHeight,
    double contentHeight,
  ) {
    final progress = widget.animation.value;
    final revealedHeight =
        (contentHeight - _drag.value).clamp(0.0, contentHeight) * progress;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('menu-drawer-mask'),
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha: 0.2 * progress * (1 - _drag.value / _height),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          height: navigationHeight + revealedHeight,
          child: panel,
        ),
      ],
    );
  }

  Widget _buildPanel(Widget content, double contentHeight) => FocusScope(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _drag.stop(),
      onVerticalDragUpdate: (details) => _move(details.primaryDelta ?? 0),
      onVerticalDragEnd: (details) => _release(details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _release(0),
      child: ReaderPanelTheme(
        theme: widget.theme ?? _fallbackTheme,
        child: ReaderFrostedSurface(
          key: const ValueKey<String>('reader-drawer-surface'),
          radius: 24,
          bottomRadius: 0,
          inkMode: widget.inkMode,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _buildRevealContent(content, contentHeight),
          ),
        ),
      ),
    ),
  );

  Widget _buildRevealContent(Widget content, double contentHeight) => Column(
    children: [
      Expanded(
        child: ClipRect(
          // 内容保持最终高度，只露出导航上方的区域，动画期间不挤压控件。
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: contentHeight,
            maxHeight: contentHeight,
            child: RepaintBoundary(child: content),
          ),
        ),
      ),
      RepaintBoundary(child: _buildNavigation()),
    ],
  );

  Widget _buildScrollableContent() => Builder(
    builder: (context) => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        overscroll: false,
        physics: _DrawerScrollPhysics(
          move: _move,
          release: _release,
          isDragging: () => _drag.value > 0,
          parent: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
        ),
      ),
      child: KeyedSubtree(key: ValueKey(widget.entry), child: widget.child),
    ),
  );

  Widget _buildNavigation() => Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return DecoratedBox(
        key: const ValueKey('reader-drawer-navigation'),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: _EntriesRow(
          fg: scheme.onSurface,
          selected: widget.entry,
          safeBottom: widget.safeBottom,
          keyPrefix: 'drawer-entry',
          onEntry: _switchEntry,
        ),
      );
    },
  );

  Widget _buildHandle() => Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Semantics(
        label: '收起${widget.title}抽屉',
        button: true,
        onTap: _close,
        child: SizedBox(
          key: const ValueKey('reader-drawer-handle'),
          height: 28,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 内容优先滚动，到顶部后才把向下位移交给抽屉；回拉时先归位再滚动。
class _DrawerScrollPhysics extends ScrollPhysics {
  const _DrawerScrollPhysics({
    required this.move,
    required this.release,
    required this.isDragging,
    super.parent,
  });

  final double Function(double) move;
  final ValueChanged<double> release;
  final bool Function() isDragging;

  @override
  _DrawerScrollPhysics applyTo(ScrollPhysics? ancestor) => _DrawerScrollPhysics(
    move: move,
    release: release,
    isDragging: isDragging,
    parent: buildParent(ancestor),
  );

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.axis != Axis.vertical) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    if (isDragging()) return offset - move(offset);
    final remaining = offset - (position.pixels - position.minScrollExtent);
    if (remaining > 0) return offset - move(remaining);
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.axis == Axis.vertical && isDragging()) {
      release(-velocity);
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
