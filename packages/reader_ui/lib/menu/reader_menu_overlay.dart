import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/reader_drawer_style.dart';
import '../theme/reader_panel_theme.dart';
import '../theme/reader_theme.dart';

const _fallbackTheme = ReaderTheme(
  id: 'fallback',
  name: '默认',
  background: Color(0xFFF5EFE0),
  text: Color(0xFF3B3228),
);

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
    this.inkMode = false,
    this.safeTop = 0,
    this.safeBottom = 0,
    this.onTts,
    this.onEdit,
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

  /// 当前是否夜间（决定图标）。
  final bool nightMode;

  /// 上一章 / 下一章；无相邻章节时传 null，按钮禁用。
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  /// 拖动滑杆（0..1）。
  final ValueChanged<double> onSeek;

  /// 点击四入口。
  final ValueChanged<ReaderMenuEntry> onEntry;

  /// 抽屉标题（为空表示抽屉关闭）。
  final String drawerTitle;

  /// 抽屉内容。
  final Widget? drawerChild;

  /// 关闭抽屉。
  final VoidCallback onCloseDrawer;

  /// 墨水屏模式：主题固定为纯黑白，禁用日夜切换。
  final bool inkMode;

  /// 顶部安全区，随状态栏显隐更新，不改变正文的缓存边距。
  final double safeTop;

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
    final bg = panelTheme.background;
    final fg = panelTheme.text;
    final line = theme?.line ?? fg.withValues(alpha: 0.12);
    final fill = theme?.fill ?? fg.withValues(alpha: 0.08);
    final topInset = safeTop;
    final bottomInset = safeBottom;
    final reduceMotion = inkMode || MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : (open ? _enter : _exit);

    // 透明 Material：InkWell/InkResponse 需要 Material 祖先（阅读页本身没有）。
    return ExcludeFocus(
      excluding: !open,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: <Widget>[
            // 顶部栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                offset: open ? Offset.zero : const Offset(0, -1.01),
                duration: duration,
                curve: _ease,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: duration,
                  child: IgnorePointer(
                    ignoring: !open,
                    child: ExcludeFocus(
                      excluding: drawerChild != null,
                      child: Container(
                        padding: EdgeInsets.only(top: topInset),
                        decoration: BoxDecoration(
                          color: bg,
                          border: Border(bottom: BorderSide(color: line)),
                        ),
                        child: SizedBox(
                          height: 56,
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: fg,
                                  ),
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
                                buttonKey: const ValueKey<String>(
                                  'menu-daynight',
                                ),
                              ),
                              if (onEdit != null)
                                _IconButton(
                                  icon: AppGlyph.editNote,
                                  iconSize: 22,
                                  color: fg,
                                  onTap: onEdit,
                                  tooltip: '编辑书籍',
                                  buttonKey: const ValueKey<String>(
                                    'menu-edit',
                                  ),
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
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 底部栏
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: open ? Offset.zero : const Offset(0, 1.01),
                duration: duration,
                curve: _ease,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: duration,
                  child: IgnorePointer(
                    ignoring: !open,
                    child: ExcludeFocus(
                      excluding: drawerChild != null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: bg,
                          border: Border(top: BorderSide(color: line)),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _ProgressRow(
                              fg: fg,
                              fill: fill,
                              progress: progress,
                              label: chapterLabel,
                              onPrevious: onPreviousChapter,
                              onNext: onNextChapter,
                              onSeek: onSeek,
                            ),
                            _EntriesRow(fg: fg, fill: fill, onEntry: onEntry),
                            SizedBox(height: 22 + bottomInset),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 抽屉
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : _enter,
                reverseDuration: reduceMotion ? Duration.zero : _exit,
                switchInCurve: _ease,
                switchOutCurve: _ease,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) {
                  final drawer = child as _DrawerLayer;
                  return _DrawerLayer(
                    title: drawer.title,
                    theme: drawer.theme,
                    onClose: drawer.onClose,
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
                        child: drawerChild!,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    return IconButton(
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
      height: 34,
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
    required this.fill,
    required this.onEntry,
  });

  final Color fg;
  final Color fill;
  final ValueChanged<ReaderMenuEntry> onEntry;

  static const Map<ReaderMenuEntry, ({AppGlyph icon, String label})> items =
      <ReaderMenuEntry, ({AppGlyph icon, String label})>{
        ReaderMenuEntry.toc: (icon: AppGlyph.listBulleted, label: '目录'),
        ReaderMenuEntry.theme: (icon: AppGlyph.palette, label: '主题'),
        ReaderMenuEntry.type: (icon: AppGlyph.textFields, label: '排版'),
        ReaderMenuEntry.settings: (icon: AppGlyph.settings, label: '设置'),
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          for (final entry in items.entries)
            Expanded(
              child: InkWell(
                key: ValueKey<String>('menu-entry-${entry.key.name}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => onEntry(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppIcon(
                        entry.value.icon,
                        size: 19,
                        color: fg.withValues(alpha: 0.85),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        entry.value.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.35,
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 抽屉（设计稿 `.drawer`：圆角 20 顶、grip、标题 + 内容）。
class _DrawerLayer extends StatelessWidget {
  const _DrawerLayer({
    super.key,
    required this.title,
    required this.theme,
    required this.child,
    required this.onClose,
    this.animation = const AlwaysStoppedAnimation(1),
  });

  final String title;
  final ReaderTheme? theme;
  final Widget child;
  final VoidCallback onClose;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final panelTheme = theme ?? _fallbackTheme;
    final dark = panelTheme.background.computeLuminance() < 0.35;
    final bg = dark ? panelTheme.background : ReaderDrawerStyle.surface;
    final fg = dark ? panelTheme.text : ReaderDrawerStyle.text;
    final handle = dark
        ? panelTheme.text.withValues(alpha: 0.22)
        : ReaderDrawerStyle.handle;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => IgnorePointer(
        ignoring: animation.status == AnimationStatus.reverse,
        child: ExcludeFocus(
          excluding: animation.status == AnimationStatus.reverse,
          child: ExcludeSemantics(
            excluding: animation.status == AnimationStatus.reverse,
            child: child,
          ),
        ),
      ),
      child: FocusScope(
        child: Stack(
          children: <Widget>[
            // 遮罩：点一下关闭抽屉
            Positioned.fill(
              child: FadeTransition(
                opacity: animation,
                child: GestureDetector(
                  key: const ValueKey<String>('menu-drawer-mask'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(animation),
                child: Container(
                  key: const ValueKey<String>('reader-drawer-surface'),
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      GestureDetector(
                        key: const ValueKey('reader-drawer-handle'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 150) onClose();
                        },
                        child: SizedBox(
                          height: 24,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: handle,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                key: const ValueKey<String>(
                                  'reader-drawer-title',
                                ),
                                title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('reader-drawer-close'),
                              tooltip: '关闭$title',
                              onPressed: onClose,
                              icon: AppIcon(
                                AppGlyph.close,
                                color: fg,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ReaderPanelTheme(
                          theme: panelTheme,
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
