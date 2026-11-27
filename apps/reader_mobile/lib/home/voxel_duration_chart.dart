import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_duration_summary.dart';
import 'reading_insights.dart';

typedef DurationBarData = ({
  String key,
  String? id,
  String title,
  String shortTitle,
  String share,
  Duration duration,
  Color color,
});

typedef DurationBarSegment = ({
  String key,
  String title,
  Color color,
  Duration duration,
});

typedef TimeOfDayBarData = ({
  String key,
  String label,
  Duration duration,
  List<DurationBarSegment> segments,
});

/// 图书时长的 2.5D 像素柱；可切换为时段、星期、日期或月份分布。
class VoxelDurationChart extends StatefulWidget {
  const VoxelDurationChart({
    super.key,
    required this.bars,
    required this.timeBars,
    required this.total,
    required this.bookCount,
    required this.selectedBookId,
    required this.onSelected,
    this.showRooftops = true,
    this.controls,
    this.footer,
    this.top,
    this.period = BookDurationPeriod.day,
    this.startWithTimeOfDay = false,
  });

  final List<DurationBarData> bars;
  final List<TimeOfDayBarData> timeBars;
  final Duration total;
  final int bookCount;
  final String? selectedBookId;
  final ValueChanged<DurationBarData> onSelected;

  /// 柱顶是否绘制装饰；时段图使用更紧凑的比例。
  final bool showRooftops;

  /// 放在卡片顶部边框内的日期与前后周期控件。
  final Widget? controls;

  /// 图表下方的书目列表，与图表共用同一张卡片。
  final Widget? footer;

  /// 卡片最顶部的统计周期滑块。
  final Widget? top;

  /// 决定时间分布的标题、计数单位和读屏标签。
  final BookDurationPeriod period;

  /// 首次显示时段分布，点击后切换到按书统计。
  final bool startWithTimeOfDay;

  @override
  State<VoxelDurationChart> createState() => _VoxelDurationChartState();
}

enum _VoxelChartMode { books, timeOfDay }

const _morphAssemblyStart = .42;
const _morphAssemblyEnd = .9;

class _VoxelDurationChartState extends State<VoxelDurationChart>
    with TickerProviderStateMixin {
  static const _plotHeight = 200.0;

  late final AnimationController _revealController;
  late final AnimationController _morphController;
  late final AnimationController _lightController;
  late final Animation<double> _morphLights;
  late _VoxelChartMode _mode;
  _VoxelChartMode? _fromMode;
  bool _morphing = false;
  bool _started = false;
  bool _reduceMotion = false;
  bool _morphLightsActive = false;

  String get _timeTitle => switch (widget.period) {
    BookDurationPeriod.day => '一天时段',
    BookDurationPeriod.week => '一周分布',
    BookDurationPeriod.month => '月内分布',
    BookDurationPeriod.quarter => '季度分布',
    BookDurationPeriod.year => '全年分布',
  };

  String get _timeUnit => switch (widget.period) {
    BookDurationPeriod.day => '个时段',
    BookDurationPeriod.week || BookDurationPeriod.month => '天',
    BookDurationPeriod.quarter || BookDurationPeriod.year => '个月',
  };

  String get _timeModeTooltip => switch (widget.period) {
    BookDurationPeriod.day => '切换为一天时段分布',
    BookDurationPeriod.week => '切换为按星期分布',
    BookDurationPeriod.month => '切换为按日期分布',
    BookDurationPeriod.quarter || BookDurationPeriod.year => '切换为按月份分布',
  };

  @override
  void initState() {
    super.initState();
    _mode = widget.startWithTimeOfDay
        ? _VoxelChartMode.timeOfDay
        : _VoxelChartMode.books;
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )..addStatusListener(_handleRevealStatus);
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener(_handleMorphStatus);
    _lightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    // 点灯波比真实格块重组晚 0.2 秒，重组结束后继续补亮顶层。
    _morphLights = _lightController.drive(
      CurveTween(curve: const Interval((_morphAssemblyStart + .2) / 1.2, 1)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _morphing = false;
      _fromMode = null;
      _morphController
        ..stop()
        ..value = 1;
      _revealController
        ..stop()
        ..value = 1;
      _lightController
        ..stop()
        ..value = 1;
    } else if (!_started) {
      _revealController.forward();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(VoxelDurationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        !_sameBars(oldWidget.bars, widget.bars) ||
        !_sameTimeBars(oldWidget.timeBars, widget.timeBars);
    if (!changed) return;
    if (_morphing) {
      _morphController.stop();
      _morphing = false;
      _fromMode = null;
    }
    // 日期或数据切换不清空柱体，只重播点灯；打断重组时显示最新数据。
    final wasRevealed = _revealController.isCompleted;
    _revealController
      ..stop()
      ..value = 1;
    if (wasRevealed) _startLights();
  }

  void _handleRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_morphing) _startLights();
  }

  void _startLights() {
    _morphLightsActive = false;
    if (_reduceMotion) {
      _lightController
        ..stop()
        ..value = 1;
    } else {
      _lightController
        ..duration = const Duration(milliseconds: 780)
        ..forward(from: 0);
    }
  }

  void _handleMorphStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_morphing || !mounted) return;
    setState(() {
      _morphing = false;
      _fromMode = null;
    });
  }

  void _toggleMode() {
    if (_morphing) return;
    final next = _mode == _VoxelChartMode.books
        ? _VoxelChartMode.timeOfDay
        : _VoxelChartMode.books;
    if (_reduceMotion) {
      setState(() {
        _mode = next;
        _fromMode = null;
      });
      return;
    }
    setState(() {
      _fromMode = _mode;
      _mode = next;
      _morphing = true;
      _morphLightsActive = true;
    });
    _revealController
      ..stop()
      ..value = 1;
    _lightController
      ..stop()
      ..duration = const Duration(milliseconds: 1200)
      ..forward(from: 0);
    _morphController.forward(from: 0);
  }

  @override
  void dispose() {
    _morphController
      ..removeStatusListener(_handleMorphStatus)
      ..dispose();
    _revealController
      ..removeStatusListener(_handleRevealStatus)
      ..dispose();
    _lightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final showBookLabel = textScale <= 1.6;
    final labelHeight = (34 * textScale).clamp(34.0, 76.0).toDouble();
    final selected = widget.bars
        .where((bar) => bar.id != null && bar.id == widget.selectedBookId)
        .firstOrNull;
    final activeBuckets = widget.timeBars
        .where((bar) => bar.duration > Duration.zero)
        .length;
    final switchingToTime = _mode == _VoxelChartMode.books;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: ReaderUiStyle.cardDecorationOf(Theme.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            key: const ValueKey('stats-book-duration-bars'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.top != null) ...[
                widget.top!,
                const SizedBox(height: 6),
              ],
              if (widget.controls != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: widget.controls!),
                    const SizedBox(width: 4),
                    _modeButton(context, switchingToTime: switchingToTime),
                  ],
                ),
                const SizedBox(height: 6),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: _modeButton(context, switchingToTime: switchingToTime),
                ),
              _header(
                context,
                selected: selected,
                activeBuckets: activeBuckets,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => _chartBody(
                  context,
                  width: constraints.maxWidth,
                  labelHeight: labelHeight,
                  showBookLabel: showBookLabel,
                  showRooftops: widget.showRooftops,
                ),
              ),
            ],
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            widget.footer!,
          ],
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required DurationBarData? selected,
    required int activeBuckets,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chartValue = selected != null
        ? '本书占比 ${selected.share}'
        : _mode == _VoxelChartMode.books
        ? widget.bookCount > widget.bars.length
              ? '前 ${widget.bars.length} 本 · 共 ${widget.bookCount} 本'
              : '${widget.bookCount} 本书'
        : '$activeBuckets $_timeUnit'
              '${widget.bookCount > widget.bars.length ? ' · 前 ${widget.bars.length} 本' : ''}';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mode == _VoxelChartMode.books ? '总阅读时长' : _timeTitle,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              formatReadingDuration(widget.total),
              key: const ValueKey('stats-book-duration-total'),
              style: const TextStyle(
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -.2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Text(
          chartValue,
          key: const ValueKey('stats-book-duration-chart-value'),
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _modeButton(BuildContext context, {required bool switchingToTime}) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: switchingToTime ? _timeModeTooltip : '切换为按书统计',
      child: IconButton(
        key: const ValueKey('stats-book-duration-chart-mode'),
        onPressed: _morphing ? null : _toggleMode,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          shape: ReaderUiStyle.controlShapeOf(Theme.of(context)),
        ),
        icon: AppIcon(
          switchingToTime ? AppGlyph.stats : AppGlyph.menuBook,
          size: 20,
        ),
      ),
    );
  }

  Widget _chartBody(
    BuildContext context, {
    required double width,
    required double labelHeight,
    required bool showBookLabel,
    required bool showRooftops,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final axisWidth = math.min(width * .18, (14 * textScale).clamp(14.0, 28.0));
    final plotWidth = width - axisWidth;
    final targetScene = _sceneFor(_mode, plotWidth);
    final lights = _morphLightsActive ? _morphLights : _lightController;
    final fromScene = _morphing
        ? _sceneFor(_fromMode ?? _VoxelChartMode.books, plotWidth)
        : null;
    final painter = fromScene == null
        ? _ScenePainter(
            scene: targetScene,
            reveal: _revealController,
            lights: lights,
            rooftops: showRooftops,
            selectedBookId: widget.selectedBookId,
            shadowColor: scheme.shadow,
            baseColor: scheme.surfaceContainerHighest,
            gridColor: scheme.outlineVariant.withValues(alpha: .6),
          )
        : _MorphPainter(
            fromScene: fromScene,
            targetScene: targetScene,
            particles: _buildMorphParticles(fromScene, targetScene),
            animation: _morphController,
            lights: lights,
            rooftops: showRooftops,
            selectedBookId: widget.selectedBookId,
            shadowColor: scheme.shadow,
            baseColor: scheme.surfaceContainerHighest,
            gridColor: scheme.outlineVariant.withValues(alpha: .6),
          );
    final chart = _StaticVoxelChart(
      scene: targetScene,
      width: plotWidth,
      plotHeight: _plotHeight,
      labelHeight: labelHeight,
      selectedBookId: widget.selectedBookId,
      showBookLabel: showBookLabel,
      painter: painter,
      morphing: _morphing,
      labelOpacity: _morphing
          ? _morphController.drive(
              CurveTween(
                curve: const Interval(.48, .94, curve: Curves.easeOut),
              ),
            )
          : null,
      onBookSelected: widget.onSelected,
      books: widget.bars,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DurationAxis(
          scene: targetScene,
          width: axisWidth,
          height: _plotHeight,
        ),
        Expanded(child: chart),
      ],
    );
  }

  _VoxelScene _sceneFor(_VoxelChartMode mode, double width) =>
      mode == _VoxelChartMode.books
      ? _bookScene(width: width, plotHeight: _plotHeight, bars: widget.bars)
      : _timeScene(
          width: width,
          plotHeight: _plotHeight,
          bars: widget.timeBars,
          labelSuffix: widget.period == BookDurationPeriod.day ? ' 时' : '',
        );
}

class _DurationAxis extends StatelessWidget {
  const _DurationAxis({
    required this.scene,
    required this.width,
    required this.height,
  });

  final _VoxelScene scene;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lineHeight = math.min(
      MediaQuery.textScalerOf(context).scale(10) * 1.3,
      scene.scale.height / 6 - 2,
    );
    return Semantics(
      container: true,
      label: '阅读时长纵轴',
      child: SizedBox(
        key: const ValueKey('stats-book-duration-y-axis'),
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index <= 3; index++)
              Positioned(
                left: 0,
                right: 2,
                top: scene.tickY(index) - lineHeight * (index == 0 ? .5 : 1),
                height: lineHeight * (index == 0 ? 1 : 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    scene.scale.label(index),
                    key: ValueKey('stats-book-duration-y-tick-$index'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _StaticVoxelChart extends StatelessWidget {
  const _StaticVoxelChart({
    required this.scene,
    required this.width,
    required this.plotHeight,
    required this.labelHeight,
    required this.selectedBookId,
    required this.showBookLabel,
    required this.painter,
    required this.morphing,
    required this.labelOpacity,
    required this.onBookSelected,
    required this.books,
  });

  final _VoxelScene scene;
  final double width;
  final double plotHeight;
  final double labelHeight;
  final String? selectedBookId;
  final bool showBookLabel;
  final CustomPainter painter;
  final bool morphing;
  final Animation<double>? labelOpacity;
  final ValueChanged<DurationBarData> onBookSelected;
  final List<DurationBarData> books;

  @override
  Widget build(BuildContext context) {
    final slotWidth = scene.bars.isEmpty ? width : width / scene.bars.length;
    final labels = _labels(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: plotHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: ValueKey(
                      morphing
                          ? 'stats-book-duration-morph'
                          : 'stats-book-duration-plot',
                    ),
                    painter: painter,
                  ),
                ),
              ),
              for (var index = 0; index < scene.bars.length; index++)
                Positioned(
                  left: slotWidth * index,
                  width: slotWidth,
                  top: 0,
                  height: plotHeight,
                  child: IgnorePointer(
                    ignoring: morphing,
                    child: ExcludeSemantics(
                      excluding: morphing,
                      child: _barInteraction(scene.bars[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: labelHeight,
          child: labelOpacity == null
              ? labels
              : FadeTransition(opacity: labelOpacity!, child: labels),
        ),
      ],
    );
  }

  Widget _barInteraction(_VoxelSceneBar bar) {
    if (scene.isTime) {
      return Semantics(
        label: bar.semanticsLabel,
        child: ExcludeSemantics(
          child: SizedBox.expand(
            key: ValueKey('stats-book-duration-time-bar-${bar.key}'),
          ),
        ),
      );
    }
    final book = books[bar.index];
    final selected = book.id != null && book.id == selectedBookId;
    return Semantics(
      label: bar.semanticsLabel,
      button: true,
      selected: selected,
      onTap: () => onBookSelected(book),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('stats-book-duration-bar-${bar.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onBookSelected(book),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _labels(BuildContext context) {
    if (scene.bars.isEmpty) return const SizedBox.shrink();
    if (scene.isTime && scene.bars.length > 12) {
      return _dailyLabels(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final bar in scene.bars)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: scene.isTime
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          bar.label.startsWith('周')
                              ? bar.label.substring(1)
                              : bar.label.replaceFirst(RegExp(r'[日月]$'), ''),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: scene.bars.length <= 7 ? 10 : 8.5,
                            height: 1.2,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    )
                  : showBookLabel
                  ? Text(
                      bar.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.25,
                        fontWeight: bar.bookId == selectedBookId
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color:
                            selectedBookId == null ||
                                bar.bookId == selectedBookId
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  /// 月内每天保留柱体与读屏信息，刻度每五天显示一次并保留首尾日期。
  Widget _dailyLabels(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = scene.bars.length;
    final labelWidth = math.min(32.0, width / count * 3);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final bar in scene.bars)
          if (bar.index == 0 ||
              bar.index == count - 1 ||
              ((bar.index + 1) % 5 == 0 && bar.index < count - 4))
            Positioned(
              left: width * (bar.index + .5) / count - labelWidth / 2,
              top: 4,
              width: labelWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  bar.label.replaceAll(RegExp('[日月]'), ''),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8.5,
                    height: 1.2,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _VoxelScene {
  const _VoxelScene({
    required this.bars,
    required this.isTime,
    required this.scale,
  });

  final List<_VoxelSceneBar> bars;
  final bool isTime;
  final _DurationScale scale;

  double tickY(int index) =>
      (bars.firstOrNull?.baseY ?? 188) - scale.height * index / 3;

  double get maximumHeight =>
      bars.fold(0.0, (height, bar) => math.max(height, bar.height));
}

/// 柱高与纵轴共用线性比例，三个等间隔刻度使用同一种时长单位。
class _DurationScale {
  _DurationScale(Duration maximum, {required this.height}) {
    final (unit, label) = maximum >= const Duration(hours: 3)
        ? (const Duration(hours: 1), '时')
        : maximum >= const Duration(minutes: 3)
        ? (const Duration(minutes: 1), '分')
        : (const Duration(seconds: 1), '秒');
    unitLabel = label;
    step = math.max(
      1,
      (maximum.inMicroseconds / unit.inMicroseconds / 3).ceil(),
    );
    limit = unit * (step * 3);
  }

  final double height;
  late final int step;
  late final String unitLabel;
  late final Duration limit;

  String label(int index) => index == 0 ? '0' : '${step * index}\n$unitLabel';

  double heightFor(Duration duration) =>
      height * duration.inMicroseconds / limit.inMicroseconds;
}

class _VoxelSceneBar {
  const _VoxelSceneBar({
    required this.index,
    required this.key,
    required this.bookId,
    required this.label,
    required this.semanticsLabel,
    required this.share,
    required this.duration,
    required this.height,
    required this.blockHeight,
    required this.segments,
    required this.cells,
    required this.centerX,
    required this.halfWidth,
    required this.depth,
    required this.baseY,
  });

  final int index;
  final String key;
  final String? bookId;
  final String label;
  final String semanticsLabel;
  final String? share;
  final Duration duration;
  final double height;
  final double blockHeight;
  final List<_VoxelSceneSegment> segments;
  final List<_VoxelCell> cells;
  final double centerX;
  final double halfWidth;
  final double depth;
  final double baseY;
}

class _VoxelSceneSegment {
  const _VoxelSceneSegment({
    required this.key,
    required this.title,
    required this.color,
    required this.duration,
    required this.height,
  });

  final String key;
  final String title;
  final Color color;
  final Duration duration;
  final double height;
}

class _VoxelCell {
  const _VoxelCell({
    required this.key,
    required this.color,
    required this.centerX,
    required this.yTop,
    required this.yBottom,
    required this.halfWidth,
    required this.depth,
    required this.floor,
    required this.seed,
  });

  final String key;
  final Color color;
  final double centerX;
  final double yTop;
  final double yBottom;
  final double halfWidth;
  final double depth;
  final int floor;
  final int seed;

  double get height => yBottom - yTop;
}

_VoxelScene _bookScene({
  required double width,
  required double plotHeight,
  required List<DurationBarData> bars,
}) {
  const blockHeight = 12.0;
  final scale = _DurationScale(
    _maximumDuration(bars.map((bar) => bar.duration)),
    height: blockHeight * 11,
  );
  final slotWidth = bars.isEmpty ? width : width / bars.length;
  return _VoxelScene(
    isTime: false,
    scale: scale,
    bars: [
      for (var index = 0; index < bars.length; index++)
        _bookSceneBar(
          bars[index],
          index,
          slotWidth,
          plotHeight,
          scale,
          blockHeight,
        ),
    ],
  );
}

_VoxelSceneBar _bookSceneBar(
  DurationBarData bar,
  int index,
  double slotWidth,
  double plotHeight,
  _DurationScale scale,
  double blockHeight,
) {
  final halfWidth = math.min(slotWidth * .32, 24.0);
  final depth = halfWidth * .5;
  final height = scale.heightFor(bar.duration);
  final segments = [
    _VoxelSceneSegment(
      key: bar.key,
      title: bar.title,
      color: bar.color,
      duration: bar.duration,
      height: height,
    ),
  ];
  final centerX = slotWidth * (index + .5);
  final baseY = plotHeight - depth - 6;
  return _VoxelSceneBar(
    index: index,
    key: bar.key,
    bookId: bar.id,
    label: bar.shortTitle,
    semanticsLabel:
        '柱状图，${bar.title}，${formatReadingDuration(bar.duration)}，'
        '占比 ${bar.share}${bar.id == null ? '，打开图书时长列表' : ''}',
    share: bar.share,
    duration: bar.duration,
    height: height,
    blockHeight: blockHeight,
    segments: segments,
    cells: _buildVoxelCells(
      barKey: bar.key,
      centerX: centerX,
      halfWidth: halfWidth,
      depth: depth,
      baseY: baseY,
      blockHeight: blockHeight,
      segments: segments,
    ),
    centerX: centerX,
    halfWidth: halfWidth,
    depth: depth,
    baseY: baseY,
  );
}

_VoxelScene _timeScene({
  required double width,
  required double plotHeight,
  required List<TimeOfDayBarData> bars,
  required String labelSuffix,
}) {
  const blockHeight = 8.0;
  final scale = _DurationScale(
    _maximumDuration(bars.map((bar) => bar.duration)),
    height: blockHeight * 19,
  );
  final slotWidth = bars.isEmpty ? width : width / bars.length;
  return _VoxelScene(
    isTime: true,
    scale: scale,
    bars: [
      for (var index = 0; index < bars.length; index++)
        _timeSceneBar(
          bars[index],
          index,
          slotWidth,
          plotHeight,
          scale,
          blockHeight,
          labelSuffix,
        ),
    ],
  );
}

_VoxelSceneBar _timeSceneBar(
  TimeOfDayBarData bar,
  int index,
  double slotWidth,
  double plotHeight,
  _DurationScale scale,
  double blockHeight,
  String labelSuffix,
) {
  final halfWidth = math.min(slotWidth * .38, 13.0);
  final depth = halfWidth * .5;
  final height = scale.heightFor(bar.duration);
  final segments = _timeSegments(bar, height);
  final centerX = slotWidth * (index + .5);
  final baseY = plotHeight - depth - 6;
  return _VoxelSceneBar(
    index: index,
    key: bar.key,
    bookId: null,
    label: bar.label,
    semanticsLabel: _timeBarSemantics(bar, labelSuffix: labelSuffix),
    share: null,
    duration: bar.duration,
    height: height,
    blockHeight: blockHeight,
    segments: segments,
    cells: _buildVoxelCells(
      barKey: bar.key,
      centerX: centerX,
      halfWidth: halfWidth,
      depth: depth,
      baseY: baseY,
      blockHeight: blockHeight,
      segments: segments,
    ),
    centerX: centerX,
    halfWidth: halfWidth,
    depth: depth,
    baseY: baseY,
  );
}

List<_VoxelCell> _buildVoxelCells({
  required String barKey,
  required double centerX,
  required double halfWidth,
  required double depth,
  required double baseY,
  required double blockHeight,
  required List<_VoxelSceneSegment> segments,
}) {
  if (halfWidth <= 0 || segments.isEmpty) return const [];
  final cells = <_VoxelCell>[];
  var segmentBottom = baseY;
  for (var segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final segment = segments[segmentIndex];
    final seed = _seedForKey('$barKey:${segment.key}');
    final segmentTop = segmentBottom - segment.height;
    var cursor = segmentBottom;
    var guard = 0;
    while (cursor > segmentTop + .1 && guard++ < 80) {
      final floor = ((baseY - cursor) / blockHeight).floor();
      final bandBottom = baseY - floor * blockHeight;
      final bandTop = bandBottom - blockHeight;
      final cellBottom = math.min(cursor, bandBottom);
      final cellTop = math.max(segmentTop, bandTop);
      if (cellBottom > cellTop) {
        cells.add(
          _VoxelCell(
            key: segment.key,
            color: segment.color,
            centerX: centerX,
            yTop: cellTop,
            yBottom: cellBottom,
            halfWidth: halfWidth,
            depth: depth,
            floor: floor,
            seed: seed + floor * 97,
          ),
        );
      }
      if (cellTop >= cursor - .01) break;
      cursor = cellTop;
    }
    segmentBottom = segmentTop;
  }
  return cells;
}

List<_VoxelSceneSegment> _timeSegments(TimeOfDayBarData bar, double height) {
  if (height <= 0 || bar.duration <= Duration.zero || bar.segments.isEmpty) {
    return const [];
  }
  return [
    for (var index = 0; index < bar.segments.length; index++)
      _VoxelSceneSegment(
        key: bar.segments[index].key,
        title: bar.segments[index].title,
        color: bar.segments[index].color,
        duration: bar.segments[index].duration,
        height:
            height *
            bar.segments[index].duration.inMicroseconds /
            bar.duration.inMicroseconds,
      ),
  ];
}

String _timeBarSemantics(TimeOfDayBarData bar, {required String labelSuffix}) {
  if (bar.duration <= Duration.zero) {
    return '${bar.label}$labelSuffix，没有阅读记录';
  }
  final contributions = bar.segments
      .map(
        (segment) =>
            '${segment.title} ${formatReadingDuration(segment.duration)}',
      )
      .join('，');
  return '${bar.label}$labelSuffix，共 ${formatReadingDuration(bar.duration)}，'
      '$contributions';
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.reveal,
    required this.lights,
    required this.rooftops,
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
    required this.gridColor,
  }) : super(repaint: Listenable.merge([reveal, lights]));

  final _VoxelScene scene;
  final Animation<double> reveal;
  final Animation<double> lights;
  final bool rooftops;
  final String? selectedBookId;
  final Color shadowColor;
  final Color baseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDurationGrid(canvas, size, scene, gridColor);
    if (scene.bars.isEmpty) return;
    _paintScene(
      canvas,
      scene,
      reveals: [
        for (var index = 0; index < scene.bars.length; index++)
          _revealValue(index, scene.bars.length, reveal.value),
      ],
      lights: lights.value,
      rooftops: rooftops,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.reveal != reveal ||
      oldDelegate.lights != lights ||
      oldDelegate.rooftops != rooftops ||
      oldDelegate.selectedBookId != selectedBookId ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.gridColor != gridColor;
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.fromScene,
    required this.targetScene,
    required this.particles,
    required this.rooftops,
    required this.animation,
    required this.lights,
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
    required this.gridColor,
  }) : super(repaint: Listenable.merge([animation, lights]));

  final _VoxelScene fromScene;
  final _VoxelScene targetScene;
  final List<_MorphParticle> particles;
  final bool rooftops;
  final Animation<double> animation;
  final Animation<double> lights;
  final String? selectedBookId;
  final Color shadowColor;
  final Color baseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDurationGrid(canvas, size, targetScene, gridColor);
    final progress = animation.value;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // 旧柱体按各自错峰节奏先后瓦解，阁楼各自提前收起，避免齐刷刷下降。
    final fromReveals = <double>[
      for (final bar in fromScene.bars) _fromBarReveal(bar, progress),
    ];
    final fromRoofReveals = <double>[
      for (final bar in fromScene.bars) _fromRoofReveal(bar, progress),
    ];
    _paintScene(
      canvas,
      fromScene,
      reveals: fromReveals,
      lights: 0,
      rooftops: rooftops,
      roofReveals: fromRoofReveals,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
    // 目标柱体带微错峰与柔和缓动从底部生长，打破水平扫描线般的整齐感。
    final targetReveals = <double>[
      for (final bar in targetScene.bars)
        _targetBarReveal(bar, targetScene.maximumHeight, progress),
    ];
    final targetRoofReveals = <double>[
      for (final bar in targetScene.bars) _targetRoofReveal(bar, progress),
    ];
    _paintScene(
      canvas,
      targetScene,
      reveals: targetReveals,
      lights: lights.value,
      rooftops: rooftops,
      roofReveals: targetRoofReveals,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
    _paintParticles(canvas, progress);
    canvas.restore();
  }

  double _fromBarReveal(_VoxelSceneBar bar, double progress) {
    final seed = _seedForKey(bar.key) + bar.index * 31;
    final start = .03 + _random(seed + 1) * .07;
    final span = .15 + _random(seed + 2) * .06;
    final t = ((progress - start) / span).clamp(0.0, 1.0).toDouble();
    return 1 - Curves.easeInCubic.transform(t);
  }

  double _fromRoofReveal(_VoxelSceneBar bar, double progress) {
    final seed = _seedForKey(bar.key) + bar.index * 37;
    final start = _random(seed + 3) * .04;
    final span = .07 + _random(seed + 4) * .04;
    return 1 - _smooth01((progress - start) / span);
  }

  double _targetBarReveal(
    _VoxelSceneBar bar,
    double maxHeight,
    double progress,
  ) {
    if (bar.height <= 0 || maxHeight <= 0) return 0;
    final seed = _seedForKey(bar.key) + bar.index * 43;
    // 每根柱子略微错开起步与增速，同时保证在重组结束前全部稳妥落位。
    final jitterStart = (_random(seed + 5) - .5) * .06;
    final start = (_morphAssemblyStart + jitterStart).clamp(.38, .47);
    final end = (_morphAssemblyEnd - .04 + _random(seed + 6) * .04).clamp(
      start + .32,
      _morphAssemblyEnd,
    );
    final raw = ((progress - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    final eased = Curves.easeOutCubic.transform(raw);
    final assembledHeight = maxHeight * eased;
    return (assembledHeight / bar.height).clamp(0.0, 1.0);
  }

  double _targetRoofReveal(_VoxelSceneBar bar, double progress) {
    final seed = _seedForKey(bar.key) + bar.index * 53;
    final start = _morphAssemblyEnd - .04 + _random(seed + 7) * .05;
    final span = (1.0 - start).clamp(.05, .14);
    final t = ((progress - start) / span).clamp(0.0, 1.0).toDouble();
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // 轻微弹跳弹出，各柱阁楼错落现身。
    return Curves.easeOutBack.transform(t).clamp(0.0, 1.12);
  }

  void _paintParticles(Canvas canvas, double progress) {
    for (final particle in particles) {
      final start = .02 + particle.delay * .22;
      final span = math.max(.18, particle.arrival - start);
      final local = ((progress - start) / span).clamp(0.0, 1.0).toDouble();
      if (local <= 0 || local >= 1) continue;
      final eased = Curves.easeInOutCubic.transform(local);
      // 非对称弧线 + 轻微横向 S 型飘移，让体素碎片像自由散落再汇聚。
      final arc = math.sin(math.pi * math.pow(local, particle.arcBias));
      final drift = math.sin(math.pi * 2 * local + particle.phase) * .28;
      var center = Offset.lerp(particle.start, particle.end, eased)!;
      center += Offset(
        particle.sway * (arc + drift * math.sin(math.pi * local)),
        -particle.spread * arc,
      );
      final dimmed = selectedBookId != null && particle.key != selectedBookId;
      final opacity =
          _smooth01(local / .10) *
          (1 - _smooth01((local - .90) / .10)) *
          (dimmed ? .3 : 1.0);
      final size =
          (particle.startSize +
              (particle.endSize - particle.startSize) * eased) *
          (1 - .26 * arc + particle.sizeJitter * arc);
      _drawParticle(canvas, center, particle.color, size, opacity);
    }
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.lights != lights ||
      oldDelegate.fromScene != fromScene ||
      oldDelegate.targetScene != targetScene ||
      oldDelegate.particles != particles ||
      oldDelegate.rooftops != rooftops ||
      oldDelegate.selectedBookId != selectedBookId ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.gridColor != gridColor;
}

void _paintDurationGrid(
  Canvas canvas,
  Size size,
  _VoxelScene scene,
  Color color,
) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = .7;
  for (var index = 0; index <= 3; index++) {
    final y = scene.tickY(index);
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 3, size.width), y),
        paint,
      );
    }
  }
}

class _MorphParticle {
  const _MorphParticle({
    required this.key,
    required this.color,
    required this.start,
    required this.end,
    required this.delay,
    required this.arrival,
    required this.spread,
    required this.sway,
    required this.arcBias,
    required this.phase,
    required this.sizeJitter,
    required this.startSize,
    required this.endSize,
  });

  final String key;
  final Color color;
  final Offset start;
  final Offset end;
  final double delay;
  final double arrival;
  final double spread;
  final double sway;
  final double arcBias;
  final double phase;
  final double sizeJitter;
  final double startSize;
  final double endSize;
}

typedef _MorphTile = ({Offset center, Color color, double size, double level});

List<_MorphParticle> _buildMorphParticles(
  _VoxelScene fromScene,
  _VoxelScene toScene,
) {
  final fromTiles = _tilesByKey(fromScene);
  final toTiles = _tilesByKey(toScene);
  final particles = <_MorphParticle>[];
  for (final entry in fromTiles.entries) {
    final targets = toTiles[entry.key];
    if (targets == null) continue;
    // 每个真实立面格子参与拆解；格子较少的一侧细分，重组时合回原格子。
    final count = math.max(entry.value.length, targets.length);
    final keySeed = _seedForKey(entry.key);
    final targetOrder = _shuffledTargetOrder(count, keySeed);
    for (var index = 0; index < count; index++) {
      final seed = keySeed + index * 17;
      final from = _splitMorphTile(entry.value, index, count);
      final to = _splitMorphTile(targets, targetOrder[index], count);
      // 保留“由上而下剥落、由下而上落位”的物理秩序，但加入个体随机错峰，打破齐整排布。
      final delay = ((1 - from.level) * .62 + _random(seed + 1) * .38).clamp(
        0.0,
        1.0,
      );
      final arrivalSpan = _morphAssemblyEnd - _morphAssemblyStart - .04;
      final arrival =
          (_morphAssemblyStart +
                  .03 +
                  to.level * arrivalSpan * .82 +
                  _random(seed + 2) * arrivalSpan * .22)
              .clamp(_morphAssemblyStart + .04, _morphAssemblyEnd + .02);
      final dx = to.center.dx - from.center.dx;
      final distanceFactor = (dx.abs() / 180).clamp(.45, 1.35);
      final swayDir = _random(seed + 3) >= .5 ? 1.0 : -1.0;
      particles.add(
        _MorphParticle(
          key: entry.key,
          color: from.color,
          start: from.center,
          end: to.center,
          delay: delay,
          arrival: arrival,
          spread: (14 + _random(seed + 6) * 32) * distanceFactor,
          sway: swayDir * (6 + _random(seed + 7) * 20),
          arcBias: .72 + _random(seed + 8) * .56,
          phase: _random(seed + 9) * math.pi * 2,
          sizeJitter: (_random(seed + 10) - .5) * .22,
          startSize: from.size,
          endSize: to.size,
        ),
      );
    }
  }
  return particles;
}

/// 确定性地打乱同书颗粒的起止配对，让体素碎片交错飞行而非平行排队列队移动。
List<int> _shuffledTargetOrder(int count, int seed) {
  final order = List<int>.generate(count, (i) => i);
  if (count <= 2) return order;
  // 按局部窗口做确定性 Fisher-Yates 洗牌，既打散平行队列，又保持整体顺滑流畅。
  final window = math.min(count, math.max(6, (count * .45).round()));
  for (var i = count - 1; i > 0; i--) {
    final minJ = math.max(0, i - window + 1);
    final span = i - minJ + 1;
    final j = minJ + (_random(seed + i * 29) * span).floor().clamp(0, span - 1);
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  return order;
}

Map<String, List<_MorphTile>> _tilesByKey(_VoxelScene scene) {
  final result = <String, List<_MorphTile>>{};
  final maximum = scene.maximumHeight;
  for (final bar in scene.bars) {
    for (final cell in bar.cells) {
      final columns = _facadeColumns(cell.halfWidth);
      final centerY = (cell.yTop + cell.yBottom) / 2;
      final size = math.min(cell.halfWidth / columns * .8, cell.height * .7);
      for (var side = 0; side < 2; side++) {
        for (var column = 0; column < columns; column++) {
          result.putIfAbsent(cell.key, () => []).add((
            center: _cellFacePoint(
              cell,
              side,
              (column + .5) / columns,
              centerY,
            ),
            color: cell.color,
            size: size,
            level: (bar.baseY - centerY) / maximum,
          ));
        }
      }
    }
  }
  return result;
}

_MorphTile _splitMorphTile(List<_MorphTile> tiles, int index, int count) {
  final tileIndex = index * tiles.length ~/ count;
  final tile = tiles[tileIndex];
  final first = (tileIndex * count / tiles.length).ceil();
  final last = ((tileIndex + 1) * count / tiles.length).ceil();
  final parts = last - first;
  if (parts == 1) return tile;
  final columns = math.sqrt(parts).ceil();
  final rows = (parts / columns).ceil();
  final local = index - first;
  final offset = Offset(
    (local % columns - (columns - 1) / 2) * tile.size / columns,
    (local ~/ columns - (rows - 1) / 2) * tile.size / rows,
  );
  return (
    center: tile.center + offset,
    color: tile.color,
    size: tile.size / math.sqrt(parts),
    level: tile.level,
  );
}

void _paintScene(
  Canvas canvas,
  _VoxelScene scene, {
  required List<double> reveals,
  required double lights,
  required bool rooftops,
  required String? selectedBookId,
  required Color shadowColor,
  required Color baseColor,
  double roofReveal = 1,
  List<double>? roofReveals,
}) {
  final lightLevels = scene.bars.fold(
    0.0,
    (levels, bar) => math.max(levels, bar.height / bar.blockHeight),
  );
  for (var index = 0; index < scene.bars.length; index++) {
    final bar = scene.bars[index];
    final reveal = index < reveals.length ? reveals[index] : 1.0;
    final barRoofReveal =
        roofReveals != null && index < roofReveals.length
        ? roofReveals[index]
        : roofReveal;
    final visibleHeight = _revealedHeight(bar, reveal);
    if (visibleHeight <= 0) continue;
    _paintBar(
      canvas,
      bar,
      visibleHeight,
      lights: lights,
      lightLevels: lightLevels,
      rooftops: rooftops,
      roofScale: scene.isTime ? (bar.height / 32).clamp(.45, .78) : 1,
      roofReveal: barRoofReveal,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
  }
}

void _paintBar(
  Canvas canvas,
  _VoxelSceneBar bar,
  double visibleHeight, {
  required double lights,
  required double lightLevels,
  required bool rooftops,
  required double roofScale,
  required double roofReveal,
  required String? selectedBookId,
  required Color shadowColor,
  required Color baseColor,
}) {
  _paintBarBase(canvas, bar, baseColor);
  if (visibleHeight <= 0) return;
  final clipTop = bar.baseY - visibleHeight;
  _VoxelCell? capCell;
  canvas.save();
  canvas.clipRect(Rect.fromLTRB(-1000, clipTop, 10000, 10000));
  for (final cell in bar.cells) {
    if (cell.yBottom < clipTop) continue;
    capCell ??= cell;
    if (cell.yTop <= clipTop + .05 && cell.yBottom > clipTop) {
      capCell = cell;
    }
    final dimmed = selectedBookId != null && cell.key != selectedBookId;
    _paintFacadeCell(
      canvas,
      cell,
      dimmed: dimmed,
      shadowColor: shadowColor,
      light: _floorLightValue(cell.floor.toDouble(), lightLevels, lights),
    );
  }
  _paintFloorSeams(canvas, bar, clipTop: clipTop, shadowColor: shadowColor);
  canvas.restore();
  // 顶面菱形在柱体显示高度之外，必须画在裁剪区外，否则只剩半个顶面。
  if (capCell != null) {
    _paintBarTop(
      canvas,
      bar,
      yTop: clipTop,
      color: capCell.color,
      dimmed: selectedBookId != null && capCell.key != selectedBookId,
    );
    if (rooftops &&
        bar.height >= bar.blockHeight &&
        visibleHeight >= bar.height - .01 &&
        roofReveal > 0) {
      canvas.save();
      canvas.translate(bar.centerX, clipTop);
      canvas.scale(roofReveal * roofScale);
      canvas.translate(-bar.centerX, -clipTop);
      _paintRooftop(
        canvas,
        bar,
        roofY: clipTop,
        color: capCell.color,
        dimmed: selectedBookId != null && capCell.key != selectedBookId,
        light: _floorLightValue(
          bar.height / bar.blockHeight + .5,
          lightLevels,
          lights,
        ),
      );
      canvas.restore();
    }
  }
}

void _paintBarBase(Canvas canvas, _VoxelSceneBar bar, Color baseColor) {
  canvas.drawPath(
    _diamond(bar.centerX, bar.baseY, bar.halfWidth + 2.4, bar.depth + 1.6),
    Paint()..color = baseColor.withValues(alpha: .7),
  );
}

const _rooftopStyleCount = 8;

/// 按柱子顺序轮换阁楼样式，相邻柱体不会重复。
void _paintRooftop(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required double roofY,
  required Color color,
  required bool dimmed,
  required double light,
}) {
  final tint = dimmed ? color.withValues(alpha: color.a * .3) : color;
  final halfWidth = bar.halfWidth * .66;
  final depth = bar.depth * .66;
  final centerX = bar.centerX;
  final windowLight = _random(_seedForKey(bar.key) + 19) >= .5 ? light : 0.0;
  final painter = switch (bar.index % _rooftopStyleCount) {
    0 => _paintRoofTerrace,
    1 => _paintRoofGreenhouse,
    2 => _paintRoofSpire,
    3 => _paintRoofTwinTowers,
    4 => _paintRoofStepped,
    5 => _paintRoofLeanTo,
    6 => _paintRoofTank,
    _ => _paintRoofCabin,
  };
  painter(canvas, centerX, roofY, halfWidth, depth, tint, windowLight);
}

/// 平顶露台：矮墙、出挑顶板与前侧栏杆。
void _paintRoofTerrace(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 10.5;
  _paintIsoBlock(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    shade: .26,
    lit: .07,
    top: .3,
  );
  final topY = baseY - wall;
  _paintIsoBlock(
    canvas,
    centerX,
    topY,
    halfWidth * 1.12,
    depth * 1.12,
    1.6,
    tint,
    shade: .22,
    lit: .1,
    top: .36,
  );
  final roofY = topY - 1.6;
  final rail = Paint()
    ..color = Color.lerp(tint, Colors.white, .68)!
    ..strokeWidth = 1;
  final rails = <Offset>[
    for (var step = 0; step <= 2; step++)
      Offset(
        centerX - halfWidth * 1.12 * (1 - step / 2),
        roofY + depth * 1.12 * step / 2,
      ),
    for (var step = 1; step <= 2; step++)
      Offset(
        centerX + halfWidth * 1.12 * step / 2,
        roofY + depth * 1.12 * (1 - step / 2),
      ),
  ];
  for (final post in rails) {
    canvas.drawLine(post, post.translate(0, -4), rail);
  }
  for (var index = 0; index < rails.length - 1; index++) {
    canvas.drawLine(
      rails[index].translate(0, -4),
      rails[index + 1].translate(0, -4),
      rail,
    );
  }
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

/// 尖顶塔楼：方屋、四坡尖顶、天线与顶灯。
void _paintRoofSpire(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 9.5;
  _paintIsoBlock(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    shade: .22,
    lit: .08,
    top: .3,
  );
  final topY = baseY - wall;
  final apex = Offset(centerX, topY - 8.5);
  final west = Offset(centerX - halfWidth, topY);
  final south = Offset(centerX, topY + depth);
  final east = Offset(centerX + halfWidth, topY);
  canvas.drawPath(
    _triPath(west, south, apex),
    Paint()..color = Color.lerp(tint, Colors.black, .08)!,
  );
  canvas.drawPath(
    _triPath(south, east, apex),
    Paint()..color = Color.lerp(tint, Colors.white, .2)!,
  );
  final mastTop = Offset(centerX, apex.dy - 5.5);
  canvas.drawLine(
    apex,
    mastTop,
    Paint()
      ..color = Color.lerp(tint, Colors.white, .5)!
      ..strokeWidth = .8,
  );
  const warm = Color(0xFFFFC46E);
  if (light > 0) {
    canvas.drawCircle(
      mastTop,
      2.8,
      Paint()..color = warm.withValues(alpha: tint.a * light * .14),
    );
  }
  canvas.drawCircle(
    mastTop,
    1.2,
    Paint()
      ..color = Color.lerp(
        Color.lerp(tint, Colors.black, .5)!.withValues(alpha: tint.a),
        warm.withValues(alpha: tint.a),
        light,
      )!,
  );
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

/// 退台阁楼：两层收分，顶上放一盆绿植。
void _paintRoofStepped(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const lower = 8.5;
  const upper = 6.5;
  _paintIsoBlock(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    lower,
    tint,
    shade: .24,
    lit: .07,
    top: .28,
  );
  final midY = baseY - lower;
  _paintIsoBlock(
    canvas,
    centerX,
    midY,
    halfWidth * .66,
    depth * .66,
    upper,
    tint,
    shade: .26,
    lit: .08,
    top: .32,
  );
  final topY = midY - upper;
  final green = Color.lerp(const Color(0xFF6F8F5E), tint, .15)!;
  _paintIsoBlock(
    canvas,
    centerX + halfWidth * .14,
    topY,
    halfWidth * .2,
    depth * .2,
    2.6,
    green,
    shade: .1,
    lit: .06,
    top: .1,
  );
  canvas.drawCircle(
    Offset(centerX + halfWidth * .14, topY - 4.2),
    2.1,
    Paint()..color = Color.lerp(green, Colors.white, .18)!,
  );
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    lower,
    tint,
    light,
  );
}

/// 水塔阁楼：设备间与顶部水箱、透气管。
void _paintRoofTank(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 8.5;
  _paintIsoBlock(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    shade: .24,
    lit: .08,
    top: .28,
  );
  final topY = baseY - wall;
  final tank = Rect.fromCenter(
    center: Offset(centerX, topY - 8.5),
    width: halfWidth * 1.2,
    height: 10,
  );
  final leg = Paint()
    ..color = Color.lerp(tint, Colors.black, .32)!
    ..strokeWidth = 1;
  canvas.drawLine(
    Offset(centerX - halfWidth * .32, topY),
    Offset(centerX - halfWidth * .32, tank.bottom),
    leg,
  );
  canvas.drawLine(
    Offset(centerX + halfWidth * .32, topY),
    Offset(centerX + halfWidth * .32, tank.bottom),
    leg,
  );
  // 侧面检修梯
  final ladder = Paint()
    ..color = Color.lerp(tint, Colors.white, .35)!
    ..strokeWidth = .7;
  final ladderX = centerX + halfWidth * .92;
  canvas.drawLine(Offset(ladderX, topY - 1), Offset(ladderX, topY + 6), ladder);
  for (var rung = 0; rung < 3; rung++) {
    final y = topY + 1 + rung * 2.4;
    canvas.drawLine(Offset(ladderX - 1.2, y), Offset(ladderX + 1.2, y), ladder);
  }
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      tank,
      topLeft: Radius.circular(tank.width * .45),
      topRight: Radius.circular(tank.width * .45),
      bottomLeft: const Radius.circular(1.5),
      bottomRight: const Radius.circular(1.5),
    ),
    Paint()..color = Color.lerp(tint, Colors.black, .25)!,
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: tank.center.translate(0, tank.height * .3),
      width: tank.width * .92,
      height: 2.2,
    ),
    Paint()..color = Colors.white.withValues(alpha: .1),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: tank.center.translate(0, -3.6),
      width: tank.width,
      height: 2.6,
    ),
    Paint()..color = Color.lerp(tint, Colors.white, .26)!,
  );
  canvas.drawLine(
    Offset(tank.left + 2, tank.center.dy),
    Offset(tank.right - 2, tank.center.dy),
    Paint()
      ..color = Colors.white.withValues(alpha: .12)
      ..strokeWidth = .6,
  );
  canvas.drawLine(
    Offset(tank.right - 1.6, tank.top),
    Offset(tank.right - 1.6, tank.top - 3),
    Paint()
      ..color = Color.lerp(tint, Colors.white, .4)!
      ..strokeWidth = .8,
  );
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

/// 坡顶小屋：矮四坡顶与右侧烟囱。
void _paintRoofCabin(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 9.5;
  _paintIsoBlock(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    shade: .23,
    lit: .08,
    top: .3,
  );
  final topY = baseY - wall;
  final apex = Offset(centerX, topY - 8);
  final west = Offset(centerX - halfWidth, topY);
  final south = Offset(centerX, topY + depth);
  final east = Offset(centerX + halfWidth, topY);
  canvas.drawPath(
    _triPath(west, south, apex),
    Paint()..color = Color.lerp(tint, Colors.black, .1)!,
  );
  canvas.drawPath(
    _triPath(south, east, apex),
    Paint()..color = Color.lerp(tint, Colors.white, .18)!,
  );
  _paintIsoBlock(
    canvas,
    centerX + halfWidth * .5,
    topY - 2.6,
    halfWidth * .18,
    depth * .18,
    6,
    tint,
    shade: .3,
    lit: .1,
    top: .3,
  );
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

/// 玻璃温室：矮墙、玻璃坡顶与白色支撑框。
void _paintRoofGreenhouse(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 7.5;
  _paintIsoBlock(canvas, centerX, baseY, halfWidth, depth, wall, tint);
  _paintGreenhouseGlazing(
    canvas,
    centerX,
    baseY - wall,
    halfWidth,
    depth,
    tint,
  );
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

void _paintGreenhouseGlazing(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
) {
  final west = Offset(centerX - halfWidth, baseY);
  final south = Offset(centerX, baseY + depth);
  final east = Offset(centerX + halfWidth, baseY);
  final apex = Offset(centerX, baseY - 9);
  final glass = Color.lerp(tint, const Color(0xFFB8D9D2), .48)!;
  canvas.drawPath(
    _triPath(west, south, apex),
    Paint()..color = glass.withValues(alpha: tint.a * .85),
  );
  canvas.drawPath(
    _triPath(south, east, apex),
    Paint()
      ..color = Color.lerp(glass, Colors.white, .2)!.withValues(alpha: tint.a),
  );
  final frame = Paint()
    ..color = Colors.white.withValues(alpha: tint.a * .55)
    ..strokeWidth = .8;
  for (final base in [west, south, east]) {
    canvas.drawLine(base, apex, frame);
  }
  canvas.drawLine(
    Offset.lerp(west, apex, .5)!,
    Offset.lerp(east, apex, .5)!,
    frame,
  );
}

/// 双塔机房：共用基座，两座高低不同的设备间。
void _paintRoofTwinTowers(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  _paintIsoBlock(canvas, centerX, baseY, halfWidth, depth, 3.5, tint);
  // 塔身与窗灯共用各自基线，窄时段柱缩放时不会错位。
  for (final tower in [
    (x: centerX - halfWidth * .38, y: baseY - 3.5 - depth * .12, height: 11.0),
    (x: centerX + halfWidth * .34, y: baseY - 3.5 + depth * .08, height: 17.0),
  ]) {
    _paintIsoBlock(
      canvas,
      tower.x,
      tower.y,
      halfWidth * .37,
      depth * .37,
      tower.height,
      tint,
    );
    _paintRooftopWindow(
      canvas,
      tower.x,
      tower.y,
      halfWidth * .37,
      depth * .37,
      tower.height,
      tint,
      light,
    );
  }
}

/// 单坡机房：斜屋顶与两块太阳能板。
void _paintRoofLeanTo(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  double light,
) {
  const wall = 8.5;
  _paintIsoBlock(canvas, centerX, baseY, halfWidth, depth, wall, tint);
  _paintSlopedRoof(canvas, centerX, baseY - wall, halfWidth, depth, tint);
  _paintRooftopWindow(
    canvas,
    centerX,
    baseY,
    halfWidth,
    depth,
    wall,
    tint,
    light,
  );
}

void _paintSlopedRoof(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
) {
  // 屋面、侧面和面板共用四个顶点，保持在一起避免窄柱缩放时出现接缝。
  final west = Offset(centerX - halfWidth, baseY - 6);
  final north = Offset(centerX, baseY - depth - 6);
  final east = Offset(centerX + halfWidth, baseY - 1.5);
  final south = Offset(centerX, baseY + depth - 1.5);
  canvas.drawPath(
    _quadPath(west, south, south.translate(0, 1.5), west.translate(0, 6)),
    Paint()
      ..color = Color.lerp(tint, Colors.black, .2)!.withValues(alpha: tint.a),
  );
  canvas.drawPath(
    _quadPath(east, south, south.translate(0, 1.5), east.translate(0, 1.5)),
    Paint()
      ..color = Color.lerp(tint, Colors.white, .08)!.withValues(alpha: tint.a),
  );
  canvas.drawPath(
    _quadPath(north, east, south, west),
    Paint()
      ..color = Color.lerp(tint, Colors.white, .3)!.withValues(alpha: tint.a),
  );
  final panel = Paint()
    ..color = Color.lerp(
      tint,
      const Color(0xFF2B4156),
      .6,
    )!.withValues(alpha: tint.a);
  for (var index = 0; index < 2; index++) {
    final start = .18 + index * .32;
    final end = start + .24;
    canvas.drawPath(
      _quadPath(
        Offset.lerp(north, east, start)!,
        Offset.lerp(north, east, end)!,
        Offset.lerp(west, south, end)!,
        Offset.lerp(west, south, start)!,
      ),
      panel,
    );
  }
}

void _paintIsoBlock(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  double height,
  Color tint, {
  double shade = .2,
  double lit = .08,
  double top = .28,
}) {
  final topY = baseY - height;
  final westBase = Offset(centerX - halfWidth, baseY);
  final southBase = Offset(centerX, baseY + depth);
  final eastBase = Offset(centerX + halfWidth, baseY);
  final westTop = Offset(centerX - halfWidth, topY);
  final southTop = Offset(centerX, topY + depth);
  final eastTop = Offset(centerX + halfWidth, topY);
  final northTop = Offset(centerX, topY - depth);
  canvas.drawPath(
    _quadPath(westTop, southTop, southBase, westBase),
    Paint()
      ..color = Color.lerp(
        tint,
        Colors.black,
        shade,
      )!.withValues(alpha: tint.a),
  );
  canvas.drawPath(
    _quadPath(eastTop, southTop, southBase, eastBase),
    Paint()
      ..color = Color.lerp(tint, Colors.white, lit)!.withValues(alpha: tint.a),
  );
  canvas.drawPath(
    _quadPath(northTop, eastTop, southTop, westTop),
    Paint()
      ..color = Color.lerp(tint, Colors.white, top)!.withValues(alpha: tint.a),
  );
}

void _paintRooftopWindow(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  double height,
  Color tint,
  double light,
) {
  final top = baseY - height * .72;
  final bottom = baseY - height * .36;
  Offset point(double ratio, double y) =>
      Offset(centerX + halfWidth * ratio, y + depth * (1 - ratio));
  final window = _quadPath(
    point(.36, top),
    point(.64, top),
    point(.64, bottom),
    point(.36, bottom),
  );
  _paintWindowLight(
    canvas,
    window,
    dark: Color.lerp(tint, Colors.black, .55)!.withValues(alpha: tint.a * .6),
    color: const Color(0xFFFFC46E).withValues(alpha: tint.a * .9),
    light: light,
  );
}

Path _quadPath(Offset a, Offset b, Offset c, Offset d) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..lineTo(d.dx, d.dy)
  ..close();

Path _triPath(Offset a, Offset b, Offset c) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..close();

void _paintFacadeCell(
  Canvas canvas,
  _VoxelCell cell, {
  required bool dimmed,
  required Color shadowColor,
  required double light,
}) {
  _paintFacadePanels(
    canvas,
    cell,
    dimmed: dimmed,
    shadowColor: shadowColor,
    light: light,
  );
  canvas.drawLine(
    _cellFacePoint(cell, 0, 0, cell.yTop),
    _cellFacePoint(cell, 0, 0, cell.yBottom),
    Paint()
      ..color = Colors.white.withValues(alpha: dimmed ? .03 : .1)
      ..strokeWidth = .8,
  );
  canvas.drawLine(
    _cellFacePoint(cell, 0, 1, cell.yTop),
    _cellFacePoint(cell, 0, 1, cell.yBottom),
    Paint()
      ..color = shadowColor.withValues(alpha: dimmed ? .05 : .16)
      ..strokeWidth = .7,
  );
}

void _paintFacadePanels(
  Canvas canvas,
  _VoxelCell cell, {
  required bool dimmed,
  required Color shadowColor,
  required double light,
}) {
  // 裁剪、窗格和接缝共用一组立面坐标，避免拆开绘制后出现漏光接缝。
  final tint = dimmed
      ? cell.color.withValues(alpha: cell.color.a * .3)
      : cell.color;
  final columns = _facadeColumns(cell.halfWidth);
  for (var side = 0; side < 2; side++) {
    canvas.save();
    // 光晕只落在当前立面内，不越过轮廓或楼层接缝。
    canvas.clipPath(_cellPanelPath(cell, side: side, start: 0, end: 1));
    for (var column = 0; column < columns; column++) {
      final start = column / columns;
      final end = (column + 1) / columns;
      final panel = _cellPanelPath(cell, side: side, start: start, end: end);
      final panelSeed = cell.seed + side * 211 + column * 47;
      final panelTint = side == 0
          ? Color.lerp(tint, Colors.black, .24 + _random(panelSeed) * .025)!
          : Color.lerp(tint, Colors.white, .07 + _random(panelSeed) * .025)!;
      canvas.drawPath(
        panel,
        Paint()..color = panelTint.withValues(alpha: tint.a),
      );
      if (column > 0) {
        canvas.drawLine(
          _cellFacePoint(cell, side, start, cell.yTop),
          _cellFacePoint(cell, side, start, cell.yBottom),
          Paint()
            ..color = shadowColor.withValues(alpha: .09)
            ..strokeWidth = .6,
        );
      }
      _paintFacadeWindow(
        canvas,
        cell,
        side: side,
        start: start,
        end: end,
        seed: panelSeed,
        tint: tint,
        dimmed: dimmed,
        light: light,
      );
    }
    canvas.restore();
  }
}

int _facadeColumns(double halfWidth) {
  if (halfWidth >= 16) return 3;
  if (halfWidth >= 7.5) return 2;
  return 1;
}

Offset _cellFacePoint(_VoxelCell cell, int side, double ratio, double y) {
  if (side == 0) {
    return Offset(
      cell.centerX - cell.halfWidth + cell.halfWidth * ratio,
      y + cell.depth * ratio,
    );
  }
  return Offset(
    cell.centerX + cell.halfWidth * ratio,
    y + cell.depth * (1 - ratio),
  );
}

Path _cellPanelPath(
  _VoxelCell cell, {
  required int side,
  required double start,
  required double end,
}) {
  final topLeft = _cellFacePoint(cell, side, start, cell.yTop);
  final topRight = _cellFacePoint(cell, side, end, cell.yTop);
  final bottomRight = _cellFacePoint(cell, side, end, cell.yBottom);
  final bottomLeft = _cellFacePoint(cell, side, start, cell.yBottom);
  return Path()
    ..moveTo(topLeft.dx, topLeft.dy)
    ..lineTo(topRight.dx, topRight.dy)
    ..lineTo(bottomRight.dx, bottomRight.dy)
    ..lineTo(bottomLeft.dx, bottomLeft.dy)
    ..close();
}

void _paintFacadeWindow(
  Canvas canvas,
  _VoxelCell cell, {
  required int side,
  required double start,
  required double end,
  required int seed,
  required Color tint,
  required bool dimmed,
  required double light,
}) {
  if (cell.height < 2.8 || cell.halfWidth < 1.8) return;
  final panelWidth = (end - start) * cell.halfWidth;
  final windowWidth = (panelWidth * .52).clamp(1.1, 3.4).toDouble();
  final windowHeight = (cell.height * .4).clamp(1.2, 4.2).toDouble();
  final widthRatio = windowWidth / cell.halfWidth;
  final dark = Color.lerp(tint, Colors.black, .5)!;
  final center = (start + end) / 2;
  final path = _cellWindowPath(
    cell,
    side: side,
    start: (center - widthRatio / 2).clamp(start + .03, end - .03).toDouble(),
    end: (center + widthRatio / 2).clamp(start + .03, end - .03).toDouble(),
    centerY: (cell.yTop + cell.yBottom) / 2,
    height: windowHeight,
  );
  // 约一半窗格随机亮灯；种子绑定柱子与书籍身份，刷新或重排不闪变。
  final lit = _random(seed + 3) >= .5;
  final color = _random(seed + 4) > .45
      ? const Color(0xFFFFBF70)
      : const Color(0xFFFFD797);
  _paintWindowLight(
    canvas,
    path,
    dark: dark.withValues(alpha: dimmed ? .15 : .7),
    color: color.withValues(
      alpha: dimmed ? .18 : .86 + _random(seed + 5) * .08,
    ),
    light: lit ? light : 0,
  );
}

void _paintWindowLight(
  Canvas canvas,
  Path path, {
  required Color dark,
  required Color color,
  required double light,
}) {
  if (light > 0) {
    final bounds = path.getBounds();
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(1.6);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: color.a * light * .16),
    );
    canvas.restore();
  }
  canvas.drawPath(path, Paint()..color = Color.lerp(dark, color, light)!);
}

void _paintFloorSeams(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required double clipTop,
  required Color shadowColor,
}) {
  for (final cell in bar.cells) {
    if (cell.yBottom < clipTop) continue;
    if (cell.yTop < clipTop + .2) continue;
    final line = Path()
      ..moveTo(
        _cellFacePoint(cell, 0, 0, cell.yTop).dx,
        _cellFacePoint(cell, 0, 0, cell.yTop).dy,
      )
      ..lineTo(
        _cellFacePoint(cell, 0, 1, cell.yTop).dx,
        _cellFacePoint(cell, 0, 1, cell.yTop).dy,
      )
      ..lineTo(
        _cellFacePoint(cell, 1, 1, cell.yTop).dx,
        _cellFacePoint(cell, 1, 1, cell.yTop).dy,
      );
    canvas.drawPath(
      line.shift(const Offset(0, -.6)),
      Paint()
        ..color = Colors.white.withValues(alpha: .09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    canvas.drawPath(
      line.shift(const Offset(0, .5)),
      Paint()
        ..color = shadowColor.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }
}

void _paintBarTop(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required double yTop,
  required Color color,
  required bool dimmed,
}) {
  final tint = dimmed ? color.withValues(alpha: color.a * .3) : color;
  final north = Offset(bar.centerX, yTop - bar.depth);
  final east = Offset(bar.centerX + bar.halfWidth, yTop);
  final south = Offset(bar.centerX, yTop + bar.depth);
  final west = Offset(bar.centerX - bar.halfWidth, yTop);
  final path = Path()
    ..moveTo(north.dx, north.dy)
    ..lineTo(east.dx, east.dy)
    ..lineTo(south.dx, south.dy)
    ..lineTo(west.dx, west.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = Color.lerp(tint, Colors.white, .24)!);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white.withValues(alpha: .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}

Path _cellWindowPath(
  _VoxelCell cell, {
  required int side,
  required double start,
  required double end,
  required double centerY,
  required double height,
}) {
  final top = math.max(cell.yTop + .8, centerY - height / 2);
  final bottom = math.min(cell.yBottom - .8, centerY + height / 2);
  final topLeft = _cellFacePoint(cell, side, start, top);
  final topRight = _cellFacePoint(cell, side, end, top);
  final bottomRight = _cellFacePoint(cell, side, end, bottom);
  final bottomLeft = _cellFacePoint(cell, side, start, bottom);
  return Path()
    ..moveTo(topLeft.dx, topLeft.dy)
    ..lineTo(topRight.dx, topRight.dy)
    ..lineTo(bottomRight.dx, bottomRight.dy)
    ..lineTo(bottomLeft.dx, bottomLeft.dy)
    ..close();
}

void _drawParticle(
  Canvas canvas,
  Offset center,
  Color color,
  double size,
  double opacity,
) {
  if (opacity <= 0) return;
  final alpha = (color.a * opacity).clamp(0.0, 1.0).toDouble();
  _paintIsoBlock(
    canvas,
    center.dx,
    center.dy + size * .5,
    size * .65,
    size * .32,
    size,
    color.withValues(alpha: alpha),
  );
}

double _revealValue(int index, int count, double controllerValue) {
  if (count <= 1) {
    return Curves.easeOutCubic.transform(controllerValue.clamp(0.0, 1.0));
  }
  // 在从左到右波次上叠加确定性错峰，使多柱入场不再像机械阶梯。
  final wave = index / (count - 1) * .14;
  final jitter = _random(index * 41 + count * 13) * .14;
  final start = (wave + jitter).clamp(0.0, .26);
  final end = math.min(1.0, start + .74);
  final local = ((controllerValue - start) / (end - start))
      .clamp(0.0, 1.0)
      .toDouble();
  return Curves.easeOutCubic.transform(local);
}

double _revealedHeight(_VoxelSceneBar bar, double reveal) {
  if (bar.height <= 0 || reveal <= 0) return 0;
  if (reveal >= 1) return bar.height;
  return bar.height * reveal;
}

/// 楼层共享同一条向上的点灯波，跨书籍色段也不从底部重新开始。
double _floorLightValue(double floor, double levels, double progress) =>
    _smooth01((progress * (levels + 2) - floor) / 1.5);

Path _diamond(double x, double y, double halfWidth, double depth) => Path()
  ..moveTo(x, y - depth)
  ..lineTo(x + halfWidth, y)
  ..lineTo(x, y + depth)
  ..lineTo(x - halfWidth, y)
  ..close();

Duration _maximumDuration(Iterable<Duration> durations) => durations.fold(
  Duration.zero,
  (maximum, duration) => duration > maximum ? duration : maximum,
);

double _smooth01(double value) {
  final clamped = value.clamp(0.0, 1.0).toDouble();
  return clamped * clamped * (3 - 2 * clamped);
}

double _random(int seed) {
  final value = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return value - value.floorToDouble();
}

int _seedForKey(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return hash;
}

bool _sameBars(List<DurationBarData> left, List<DurationBarData> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.key != b.key ||
        a.id != b.id ||
        a.title != b.title ||
        a.shortTitle != b.shortTitle ||
        a.share != b.share ||
        a.duration != b.duration ||
        a.color != b.color) {
      return false;
    }
  }
  return true;
}

bool _sameTimeBars(List<TimeOfDayBarData> left, List<TimeOfDayBarData> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.key != b.key ||
        a.label != b.label ||
        a.duration != b.duration ||
        a.segments.length != b.segments.length) {
      return false;
    }
    for (var segment = 0; segment < a.segments.length; segment++) {
      final leftSegment = a.segments[segment];
      final rightSegment = b.segments[segment];
      if (leftSegment.key != rightSegment.key ||
          leftSegment.title != rightSegment.title ||
          leftSegment.color != rightSegment.color ||
          leftSegment.duration != rightSegment.duration) {
        return false;
      }
    }
  }
  return true;
}
