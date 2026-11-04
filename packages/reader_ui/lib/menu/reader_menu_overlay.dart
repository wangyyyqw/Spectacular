import 'package:flutter/material.dart';

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

  /// 顶部安全区（由阅读页缓存后注入，保证菜单与正文用同一份值）。
  final double safeTop;

  /// 底部安全区。
  final double safeBottom;

  /// 听书（为 null 时不显示入口图标）。
  final VoidCallback? onTts;

  static const Duration _slide = Duration(milliseconds: 180);
  static const Curve _ease = Cubic(0.32, 0.72, 0, 1);

  @override
  Widget build(BuildContext context) {
    final panelTheme = theme ?? _fallbackTheme;
    final bg = panelTheme.background;
    final fg = panelTheme.text;
    final line = theme?.line ?? fg.withValues(alpha: 0.12);
    final fill = theme?.fill ?? fg.withValues(alpha: 0.08);
    final topInset = safeTop;
    final bottomInset = safeBottom;

    // 透明 Material：InkWell/InkResponse 需要 Material 祖先（阅读页本身没有）。
    return Material(
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
              duration: _slide,
              curve: _ease,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: _slide,
                child: IgnorePointer(
                  ignoring: !open,
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
                            icon: Icons.arrow_back_ios_new,
                            iconSize: 18,
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
                          _IconButton(
                            icon: nightMode
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
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
                          if (onTts != null)
                            _IconButton(
                              icon: Icons.headphones_outlined,
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
          // 底部栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: open ? Offset.zero : const Offset(0, 1.01),
              duration: _slide,
              curve: _ease,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: _slide,
                child: IgnorePointer(
                  ignoring: !open,
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
                        SizedBox(
                          height: 22 + bottomInset,
                          child: Center(
                            child: Container(
                              width: 118,
                              height: 4.5,
                              decoration: BoxDecoration(
                                color: fg.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 抽屉
          if (drawerChild != null)
            Positioned.fill(
              child: _DrawerLayer(
                title: drawerTitle,
                theme: theme,
                onClose: onCloseDrawer,
                child: drawerChild!,
              ),
            ),
        ],
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

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;
  final double iconSize;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      icon: Icon(
        icon,
        size: iconSize,
        color: color.withValues(alpha: onTap == null ? 0.3 : 0.9),
      ),
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
            icon: Icons.skip_previous,
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
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
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
                              borderRadius: BorderRadius.circular(8),
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
            icon: Icons.skip_next,
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

  final IconData icon;
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
            child: Icon(
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

  static const Map<ReaderMenuEntry, ({IconData icon, String label})> items =
      <ReaderMenuEntry, ({IconData icon, String label})>{
        ReaderMenuEntry.toc: (icon: Icons.menu_book_outlined, label: '目录'),
        ReaderMenuEntry.theme: (icon: Icons.palette_outlined, label: '主题'),
        ReaderMenuEntry.type: (icon: Icons.format_size, label: '排版'),
        ReaderMenuEntry.settings: (icon: Icons.settings_outlined, label: '设置'),
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
                borderRadius: BorderRadius.circular(12),
                onTap: () => onEntry(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
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
    required this.title,
    required this.theme,
    required this.child,
    required this.onClose,
  });

  final String title;
  final ReaderTheme? theme;
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final panelTheme = theme ?? _fallbackTheme;
    final bg = panelTheme.background;
    final fg = panelTheme.text;
    return Stack(
      children: <Widget>[
        // 遮罩：点一下关闭抽屉
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('menu-drawer-mask'),
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: const Cubic(0.32, 0.72, 0, 1),
            builder: (context, value, child) => FractionalTranslation(
              translation: Offset(0, 1 - value),
              child: child,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 40,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 4),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 8, 0),
                    child: Row(
                      children: <Widget>[
                        Text(
                          key: const ValueKey<String>('reader-drawer-title'),
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey<String>('menu-drawer-close'),
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: fg.withValues(alpha: 0.7),
                          ),
                          onPressed: onClose,
                          visualDensity: VisualDensity.compact,
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ReaderPanelTheme(theme: panelTheme, child: child),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
