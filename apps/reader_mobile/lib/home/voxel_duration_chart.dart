import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

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

/// 图书时长的 2.5D 像素柱；可切换为一天内每两小时的阅读分布。
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
  });

  final List<DurationBarData> bars;
  final List<TimeOfDayBarData> timeBars;
  final Duration total;
  final int bookCount;
  final String? selectedBookId;
  final ValueChanged<DurationBarData> onSelected;

  /// 柱顶是否绘制阁楼装饰；时段图柱体过窄，始终不绘制。
  final bool showRooftops;

  /// 放在卡片顶部边框内的切换控件（周期、日期、今天）。
  final Widget? controls;

  @override
  State<VoxelDurationChart> createState() => _VoxelDurationChartState();
}

enum _VoxelChartMode { books, timeOfDay }

class _VoxelDurationChartState extends State<VoxelDurationChart>
    with TickerProviderStateMixin {
  static const _plotHeight = 200.0;

  late final AnimationController _revealController;
  late final AnimationController _morphController;
  _VoxelChartMode _mode = _VoxelChartMode.books;
  _VoxelChartMode? _fromMode;
  bool _morphing = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener(_handleMorphStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _revealController
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
    // 周期或数据切换时直接显示完整柱体：重播长成动画会让月/季度/年等
    // 数据量不同的图表先变成空白再长出，看起来像图表没有显示。
    _revealController
      ..stop()
      ..value = 1;
  }

  void _handleMorphStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
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
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _mode = next;
        _fromMode = null;
      });
      return;
    }
    _revealController
      ..stop()
      ..value = 1;
    setState(() {
      _fromMode = _mode;
      _mode = next;
      _morphing = true;
    });
    _morphController.duration = const Duration(milliseconds: 1000);
    _morphController.forward(from: 0);
  }

  @override
  void dispose() {
    _morphController
      ..removeStatusListener(_handleMorphStatus)
      ..dispose();
    _revealController.dispose();
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
    return Container(
      key: const ValueKey('stats-book-duration-bars'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controls != null) ...[
            widget.controls!,
            const SizedBox(height: 6),
          ],
          _header(context, selected: selected, activeBuckets: activeBuckets),
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
        ? '${widget.bookCount} 本书'
        : '$activeBuckets 个时段';
    final switchingToTime = _mode == _VoxelChartMode.books;
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
              _mode == _VoxelChartMode.books ? '总阅读时长' : '一天时段',
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Tooltip(
              message: switchingToTime ? '切换为一天时段分布' : '切换为按书统计',
              child: TextButton.icon(
                key: const ValueKey('stats-book-duration-chart-mode'),
                onPressed: _morphing ? null : _toggleMode,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: scheme.onSurface,
                  backgroundColor: scheme.surfaceContainerHighest,
                  shape: StadiumBorder(
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: AppIcon(
                  switchingToTime ? AppGlyph.stats : AppGlyph.menuBook,
                  size: 16,
                ),
                label: Text(switchingToTime ? '时段' : '书目'),
              ),
            ),
            const SizedBox(height: 2),
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
        ),
      ],
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
    final targetScene = _sceneFor(_mode, width);
    final rooftops = showRooftops;
    final staticChart = _StaticVoxelChart(
      scene: targetScene,
      width: width,
      plotHeight: _plotHeight,
      labelHeight: labelHeight,
      selectedBookId: widget.selectedBookId,
      showBookLabel: showBookLabel,
      rooftops: rooftops,
      revealController: _revealController,
      shadowColor: scheme.shadow,
      baseColor: scheme.surfaceContainerHighest,
      onBookSelected: widget.onSelected,
      books: widget.bars,
    );
    if (!_morphing) return staticChart;

    final fromMode = _fromMode ?? _VoxelChartMode.books;
    final fromScene = _sceneFor(fromMode, width);
    final particles = _buildMorphParticles(fromScene, targetScene);
    return AnimatedBuilder(
      animation: _morphController,
      child: RepaintBoundary(child: staticChart),
      builder: (context, child) {
        final progress = _morphController.value;
        final targetOpacity = _smooth01((progress - .58) / .38);
        return SizedBox(
          height: _plotHeight + labelHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(opacity: targetOpacity, child: child),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const ValueKey('stats-book-duration-morph'),
                    painter: _MorphPainter(
                      fromScene: fromScene,
                      particles: particles,
                      rooftops: rooftops,
                      plotHeight: _plotHeight,
                      progress: progress,
                      selectedBookId: widget.selectedBookId,
                      shadowColor: scheme.shadow,
                      baseColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _VoxelScene _sceneFor(_VoxelChartMode mode, double width) =>
      mode == _VoxelChartMode.books
      ? _bookScene(
          width: width,
          plotHeight: _plotHeight,
          bars: widget.bars,
          selectedBookId: widget.selectedBookId,
        )
      : _timeScene(
          width: width,
          plotHeight: _plotHeight,
          bars: widget.timeBars,
        );
}

class _StaticVoxelChart extends StatelessWidget {
  const _StaticVoxelChart({
    required this.scene,
    required this.width,
    required this.plotHeight,
    required this.labelHeight,
    required this.selectedBookId,
    required this.showBookLabel,
    required this.rooftops,
    required this.revealController,
    required this.shadowColor,
    required this.baseColor,
    required this.onBookSelected,
    required this.books,
  });

  final _VoxelScene scene;
  final double width;
  final double plotHeight;
  final double labelHeight;
  final String? selectedBookId;
  final bool showBookLabel;
  final bool rooftops;
  final AnimationController revealController;
  final Color shadowColor;
  final Color baseColor;
  final ValueChanged<DurationBarData> onBookSelected;
  final List<DurationBarData> books;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: revealController,
    builder: (context, _) {
      final reveals = [
        for (var index = 0; index < scene.bars.length; index++)
          _revealValue(
            index,
            scene.bars.length,
            revealController.value,
            context,
          ),
      ];
      final slotWidth = scene.bars.isEmpty ? width : width / scene.bars.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: plotHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScenePainter(
                      scene: scene,
                      reveals: reveals,
                      rooftops: rooftops,
                      selectedBookId: selectedBookId,
                      shadowColor: shadowColor,
                      baseColor: baseColor,
                    ),
                  ),
                ),
                for (var index = 0; index < scene.bars.length; index++)
                  Positioned(
                    left: slotWidth * index,
                    width: slotWidth,
                    top: 0,
                    height: plotHeight,
                    child: _barInteraction(scene.bars[index]),
                  ),
              ],
            ),
          ),
          SizedBox(height: labelHeight, child: _labels(context)),
        ],
      );
    },
  );

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
                          bar.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8.5,
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
}

class _VoxelScene {
  const _VoxelScene({required this.bars, required this.isTime});

  final List<_VoxelSceneBar> bars;
  final bool isTime;
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
    required this.barIndex,
    required this.key,
    required this.color,
    required this.centerX,
    required this.yTop,
    required this.yBottom,
    required this.halfWidth,
    required this.depth,
    required this.floor,
    required this.segmentIndex,
  });

  final int barIndex;
  final String key;
  final Color color;
  final double centerX;
  final double yTop;
  final double yBottom;
  final double halfWidth;
  final double depth;
  final int floor;
  final int segmentIndex;

  double get height => yBottom - yTop;
}

_VoxelScene _bookScene({
  required double width,
  required double plotHeight,
  required List<DurationBarData> bars,
  required String? selectedBookId,
}) {
  const blockHeight = 12.0;
  final maximum = _maximumDuration(bars.map((bar) => bar.duration));
  final slotWidth = bars.isEmpty ? width : width / bars.length;
  return _VoxelScene(
    isTime: false,
    bars: [
      for (var index = 0; index < bars.length; index++)
        _bookSceneBar(
          bars[index],
          index,
          slotWidth,
          plotHeight,
          maximum,
          blockHeight,
          selectedBookId,
        ),
    ],
  );
}

_VoxelSceneBar _bookSceneBar(
  DurationBarData bar,
  int index,
  double slotWidth,
  double plotHeight,
  Duration maximum,
  double blockHeight,
  String? selectedBookId,
) {
  final halfWidth = math.min(slotWidth * .32, 24.0);
  final depth = halfWidth * .5;
  final level = _levelsFor(bar.duration, maximum, maximumLevels: 10);
  final height = level * blockHeight;
  final selected = bar.id != null && bar.id == selectedBookId;
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
  final baseY = plotHeight - depth - 6 - (selected ? 4 : 0);
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
      barIndex: index,
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
}) {
  const blockHeight = 8.0;
  final maximum = _maximumDuration(bars.map((bar) => bar.duration));
  final slotWidth = bars.isEmpty ? width : width / bars.length;
  return _VoxelScene(
    isTime: true,
    bars: [
      for (var index = 0; index < bars.length; index++)
        _timeSceneBar(
          bars[index],
          index,
          slotWidth,
          plotHeight,
          maximum,
          blockHeight,
        ),
    ],
  );
}

_VoxelSceneBar _timeSceneBar(
  TimeOfDayBarData bar,
  int index,
  double slotWidth,
  double plotHeight,
  Duration maximum,
  double blockHeight,
) {
  final halfWidth = math.min(slotWidth * .38, 13.0);
  final depth = halfWidth * .5;
  final level = _levelsFor(bar.duration, maximum, maximumLevels: 18);
  final height = level * blockHeight;
  final segments = _timeSegments(bar, height);
  final centerX = slotWidth * (index + .5);
  final baseY = plotHeight - depth - 6;
  return _VoxelSceneBar(
    index: index,
    key: bar.key,
    bookId: null,
    label: bar.label,
    semanticsLabel: _timeBarSemantics(bar),
    share: null,
    duration: bar.duration,
    height: height,
    blockHeight: blockHeight,
    segments: segments,
    cells: _buildVoxelCells(
      barIndex: index,
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
  required int barIndex,
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
    final segmentTop = segmentBottom - segment.height;
    var cursor = segmentBottom;
    var guard = 0;
    while (cursor > segmentTop + .1 && guard++ < 80) {
      final floor = ((baseY - cursor) / blockHeight).floor();
      final bandBottom = baseY - floor * blockHeight;
      final bandTop = bandBottom - blockHeight;
      final cellBottom = math.min(cursor, bandBottom);
      final cellTop = math.max(segmentTop, bandTop);
      if (cellBottom - cellTop > .3) {
        cells.add(
          _VoxelCell(
            barIndex: barIndex,
            key: segment.key,
            color: segment.color,
            centerX: centerX,
            yTop: cellTop,
            yBottom: cellBottom,
            halfWidth: halfWidth,
            depth: depth,
            floor: floor,
            segmentIndex: segmentIndex,
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
  final raw = [
    for (final segment in bar.segments)
      height * segment.duration.inMicroseconds / bar.duration.inMicroseconds,
  ];
  final minimum = math.min(1.4, height / bar.segments.length);
  final floors = [for (final value in raw) math.max(value, minimum)];
  final sum = floors.fold(0.0, (total, value) => total + value);
  final scale = sum > 0 ? height / sum : 0.0;
  return [
    for (var index = 0; index < bar.segments.length; index++)
      _VoxelSceneSegment(
        key: bar.segments[index].key,
        title: bar.segments[index].title,
        color: bar.segments[index].color,
        duration: bar.segments[index].duration,
        height: floors[index] * scale,
      ),
  ];
}

String _timeBarSemantics(TimeOfDayBarData bar) {
  if (bar.duration <= Duration.zero) return '${bar.label} 时，没有阅读记录';
  final contributions = bar.segments
      .map(
        (segment) =>
            '${segment.title} ${formatReadingDuration(segment.duration)}',
      )
      .join('，');
  return '${bar.label} 时，共 ${formatReadingDuration(bar.duration)}，'
      '$contributions';
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({
    required this.scene,
    required this.reveals,
    required this.rooftops,
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
  });

  final _VoxelScene scene;
  final List<double> reveals;
  final bool rooftops;
  final String? selectedBookId;
  final Color shadowColor;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.bars.isEmpty) return;
    _paintScene(
      canvas,
      size,
      scene,
      reveals: reveals,
      rooftops: rooftops,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => true;
}

class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.fromScene,
    required this.particles,
    required this.rooftops,
    required this.plotHeight,
    required this.progress,
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
  });

  final _VoxelScene fromScene;
  final List<_MorphParticle> particles;
  final bool rooftops;
  final double plotHeight;
  final double progress;
  final String? selectedBookId;
  final Color shadowColor;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, plotHeight));
    final sourceOpacity = 1 - _smooth01(progress / .26);
    _paintScene(
      canvas,
      size,
      fromScene,
      reveals: List.filled(fromScene.bars.length, 1.0),
      rooftops: rooftops,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
      opacity: sourceOpacity,
    );
    _paintParticles(canvas);
    canvas.restore();
  }

  void _paintParticles(Canvas canvas) {
    final fade =
        _smooth01(progress / .08) * (1 - _smooth01((progress - .9) / .08));
    if (fade <= 0) return;
    for (final particle in particles) {
      final start = .04 + particle.delay * .18;
      final local = ((progress - start) / .6).clamp(0.0, 1.0).toDouble();
      final eased = Curves.easeInOutCubic.transform(local);
      final burst = math.sin(math.pi * local);
      var center = Offset.lerp(particle.start, particle.end, eased)!;
      center +=
          Offset(math.cos(particle.angle), math.sin(particle.angle)) *
          particle.spread *
          burst;
      center += Offset(0, -burst * particle.size * 3);
      final dimmed = selectedBookId != null && particle.key != selectedBookId;
      final opacity =
          fade *
          (0.55 + 0.45 * math.sin(math.pi * local)) *
          (dimmed ? .3 : 1.0);
      _drawParticle(canvas, center, particle.color, particle.size, opacity);
    }
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fromScene != fromScene ||
      oldDelegate.particles != particles ||
      oldDelegate.selectedBookId != selectedBookId;
}

class _MorphParticle {
  const _MorphParticle({
    required this.key,
    required this.color,
    required this.start,
    required this.end,
    required this.delay,
    required this.spread,
    required this.angle,
    required this.size,
  });

  final String key;
  final Color color;
  final Offset start;
  final Offset end;
  final double delay;
  final double spread;
  final double angle;
  final double size;
}

List<_MorphParticle> _buildMorphParticles(
  _VoxelScene fromScene,
  _VoxelScene toScene,
) {
  final fromAreas = _areasByKey(fromScene);
  final toAreas = _areasByKey(toScene);
  final colors = <String, Color>{};
  final durations = <String, Duration>{};
  for (final bar in fromScene.bars) {
    for (final segment in bar.segments) {
      colors[segment.key] = segment.color;
      durations[segment.key] =
          (durations[segment.key] ?? Duration.zero) + segment.duration;
    }
  }
  final total = durations.values.fold(
    Duration.zero,
    (sum, duration) => sum + duration,
  );
  final particles = <_MorphParticle>[];
  var category = 0;
  for (final entry in fromAreas.entries) {
    final targets = toAreas[entry.key];
    if (entry.value.isEmpty || targets == null || targets.isEmpty) continue;
    final color = colors[entry.key];
    if (color == null) continue;
    final share = total <= Duration.zero
        ? 0.0
        : (durations[entry.key] ?? Duration.zero).inMicroseconds /
              total.inMicroseconds;
    final areaCount = math.max(entry.value.length, targets.length);
    final count = (10 + 36 * math.sqrt(share) + math.min(16, areaCount / 2))
        .round()
        .clamp(12, 56);
    for (var index = 0; index < count; index++) {
      final seed = category * 1000 + index * 11;
      final startRect = _pickArea(entry.value, _random(seed + 1));
      final endRect = _pickArea(targets, _random(seed + 2));
      particles.add(
        _MorphParticle(
          key: entry.key,
          color: color,
          start: _pointIn(startRect, seed + 3),
          end: _pointIn(endRect, seed + 4),
          delay: _random(seed + 5),
          spread: 7 + _random(seed + 6) * 24,
          angle: _random(seed + 7) * math.pi * 2,
          size: 2.2 + _random(seed + 8) * 2.2,
        ),
      );
    }
    category++;
  }
  return particles;
}

Map<String, List<Rect>> _areasByKey(_VoxelScene scene) {
  final result = <String, List<Rect>>{};
  for (final bar in scene.bars) {
    for (final cell in bar.cells) {
      if (cell.height <= 0) continue;
      final rect = Rect.fromLTRB(
        cell.centerX - cell.halfWidth * .9,
        cell.yTop,
        cell.centerX + cell.halfWidth * .9,
        cell.yBottom,
      );
      result.putIfAbsent(cell.key, () => []).add(rect);
    }
  }
  return result;
}

Rect _pickArea(List<Rect> areas, double value) {
  final total = areas.fold(0.0, (sum, rect) => sum + math.max(.1, rect.height));
  var cursor = value * total;
  for (final rect in areas) {
    cursor -= math.max(.1, rect.height);
    if (cursor <= 0) return rect;
  }
  return areas.last;
}

Offset _pointIn(Rect rect, int seed) => Offset(
  rect.left + _random(seed) * rect.width,
  rect.top + _random(seed + 100) * rect.height,
);

void _paintScene(
  Canvas canvas,
  Size size,
  _VoxelScene scene, {
  required List<double> reveals,
  required bool rooftops,
  required String? selectedBookId,
  required Color shadowColor,
  required Color baseColor,
  double opacity = 1,
}) {
  if (opacity <= 0) return;
  final layered = opacity < 1;
  if (layered) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
  }
  for (var index = 0; index < scene.bars.length; index++) {
    final bar = scene.bars[index];
    final reveal = index < reveals.length ? reveals[index] : 1.0;
    final visibleHeight = _revealedHeight(bar, reveal);
    if (visibleHeight <= 0) continue;
    _paintBar(
      canvas,
      bar,
      visibleHeight,
      rooftops: rooftops && !scene.isTime,
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
    );
  }
  if (layered) canvas.restore();
}

void _paintBar(
  Canvas canvas,
  _VoxelSceneBar bar,
  double visibleHeight, {
  required bool rooftops,
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
    _paintFacadeCell(canvas, cell, dimmed: dimmed, shadowColor: shadowColor);
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
    if (rooftops && visibleHeight >= bar.height - .01) {
      _paintRooftop(
        canvas,
        bar,
        roofY: clipTop,
        color: capCell.color,
        dimmed: selectedBookId != null && capCell.key != selectedBookId,
      );
    }
  }
}

void _paintBarBase(Canvas canvas, _VoxelSceneBar bar, Color baseColor) {
  canvas.drawPath(
    _diamond(bar.centerX, bar.baseY, bar.halfWidth + 2.4, bar.depth + 1.6),
    Paint()..color = baseColor.withValues(alpha: .7),
  );
}

const _rooftopStyleCount = 5;

/// 按柱子顺序轮换阁楼样式，相邻柱体不会重复。
void _paintRooftop(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required double roofY,
  required Color color,
  required bool dimmed,
}) {
  final tint = dimmed ? color.withValues(alpha: color.a * .3) : color;
  final halfWidth = bar.halfWidth * .66;
  final depth = bar.depth * .66;
  final centerX = bar.centerX;
  switch (bar.index % _rooftopStyleCount) {
    case 0:
      _paintRoofTerrace(canvas, centerX, roofY, halfWidth, depth, tint, dimmed);
    case 1:
      _paintRoofSpire(canvas, centerX, roofY, halfWidth, depth, tint, dimmed);
    case 2:
      _paintRoofStepped(canvas, centerX, roofY, halfWidth, depth, tint, dimmed);
    case 3:
      _paintRoofTank(canvas, centerX, roofY, halfWidth, depth, tint, dimmed);
    default:
      _paintRoofCabin(canvas, centerX, roofY, halfWidth, depth, tint, dimmed);
  }
}

/// 平顶露台：矮墙、出挑顶板与前侧栏杆。
void _paintRoofTerrace(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  bool dimmed,
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
  _paintRooftopWindow(canvas, centerX, baseY, halfWidth, depth, wall, dimmed);
}

/// 尖顶塔楼：方屋、四坡尖顶、天线与顶灯。
void _paintRoofSpire(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  bool dimmed,
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
  canvas.drawCircle(mastTop, 1.2, Paint()..color = const Color(0xFFFFC46E));
  _paintRooftopWindow(canvas, centerX, baseY, halfWidth, depth, wall, dimmed);
}

/// 退台阁楼：两层收分，顶上放一盆绿植。
void _paintRoofStepped(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  bool dimmed,
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
  _paintRooftopWindow(canvas, centerX, baseY, halfWidth, depth, lower, dimmed);
}

/// 水塔阁楼：设备间与顶部水箱、透气管。
void _paintRoofTank(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  bool dimmed,
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
  _paintRooftopWindow(canvas, centerX, baseY, halfWidth, depth, wall, dimmed);
}

/// 坡顶小屋：矮四坡顶与右侧烟囱。
void _paintRoofCabin(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  Color tint,
  bool dimmed,
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
  _paintRooftopWindow(canvas, centerX, baseY, halfWidth, depth, wall, dimmed);
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
    Paint()..color = Color.lerp(tint, Colors.black, shade)!,
  );
  canvas.drawPath(
    _quadPath(eastTop, southTop, southBase, eastBase),
    Paint()..color = Color.lerp(tint, Colors.white, lit)!,
  );
  canvas.drawPath(
    _quadPath(northTop, eastTop, southTop, westTop),
    Paint()..color = Color.lerp(tint, Colors.white, top)!,
  );
}

void _paintRooftopWindow(
  Canvas canvas,
  double centerX,
  double baseY,
  double halfWidth,
  double depth,
  double height,
  bool dimmed,
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
  final bounds = window.getBounds();
  const warm = Color(0xFFFFC46E);
  canvas.save();
  canvas.translate(bounds.center.dx, bounds.center.dy);
  canvas.scale(2);
  canvas.translate(-bounds.center.dx, -bounds.center.dy);
  canvas.drawPath(
    window,
    Paint()..color = warm.withValues(alpha: dimmed ? .1 : .16),
  );
  canvas.restore();
  canvas.drawPath(
    window,
    Paint()..color = warm.withValues(alpha: dimmed ? .28 : .85),
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
}) {
  final tint = dimmed
      ? cell.color.withValues(alpha: cell.color.a * .3)
      : cell.color;
  final seed = cell.barIndex * 10000 + cell.floor * 97 + cell.segmentIndex * 13;
  final west = _cellFacePoint(cell, 0, 0, cell.yTop);
  final south = _cellFacePoint(cell, 0, 1, cell.yTop);
  final east = _cellFacePoint(cell, 1, 1, cell.yTop);
  final baseSouth = _cellFacePoint(cell, 0, 1, cell.yBottom);
  final baseWest = _cellFacePoint(cell, 0, 0, cell.yBottom);
  final baseEast = _cellFacePoint(cell, 1, 1, cell.yBottom);
  final leftFace = Path()
    ..moveTo(west.dx, west.dy)
    ..lineTo(south.dx, south.dy)
    ..lineTo(baseSouth.dx, baseSouth.dy)
    ..lineTo(baseWest.dx, baseWest.dy)
    ..close();
  final rightFace = Path()
    ..moveTo(east.dx, east.dy)
    ..lineTo(south.dx, south.dy)
    ..lineTo(baseSouth.dx, baseSouth.dy)
    ..lineTo(baseEast.dx, baseEast.dy)
    ..close();
  canvas.drawPath(
    leftFace,
    Paint()..color = Color.lerp(tint, Colors.black, .2)!,
  );
  canvas.drawPath(
    rightFace,
    Paint()..color = Color.lerp(tint, Colors.white, .06)!,
  );
  final columns = _facadeColumns(cell.halfWidth);
  for (var side = 0; side < 2; side++) {
    for (var column = 0; column < columns; column++) {
      final start = column / columns;
      final end = (column + 1) / columns;
      final panel = _cellPanelPath(cell, side: side, start: start, end: end);
      final panelSeed = seed + side * 211 + column * 47;
      final panelTint = side == 0
          ? Color.lerp(tint, Colors.black, .17 + _random(panelSeed) * .07)!
          : Color.lerp(tint, Colors.white, .05 + _random(panelSeed) * .07)!;
      canvas.drawPath(panel, Paint()..color = panelTint);
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
      );
    }
  }
  canvas.drawLine(
    west,
    baseWest,
    Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    south,
    baseSouth,
    Paint()
      ..color = shadowColor.withValues(alpha: .13)
      ..strokeWidth = .8,
  );
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
}) {
  if (cell.height < 2.4 || cell.halfWidth < 1.8) return;
  final panelWidth = (end - start) * cell.halfWidth;
  final windowWidth = (panelWidth * .42).clamp(.9, 2.4).toDouble();
  final windowHeight = (cell.height * .36).clamp(1.4, 3.2).toDouble();
  final widthRatio = windowWidth / cell.halfWidth;
  final dark = Color.lerp(tint, Colors.black, .5)!;
  if (_random(seed) < .08) return;
  final center =
      (start + end) / 2 + (_random(seed + 1) - .5) * (end - start) * .1;
  final centerY =
      (cell.yTop + cell.yBottom) / 2 +
      (_random(seed + 2) - .5) * cell.height * .16;
  final path = _cellWindowPath(
    cell,
    side: side,
    start: (center - widthRatio / 2).clamp(start + .03, end - .03).toDouble(),
    end: (center + widthRatio / 2).clamp(start + .03, end - .03).toDouble(),
    centerY: centerY,
    height: windowHeight,
  );
  if (_random(seed + 3) > .78) {
    final color = _random(seed + 4) > .45
        ? const Color(0xFFFFB65E)
        : const Color(0xFFFFD28C);
    final opacity = dimmed ? .14 : .8 + _random(seed + 5) * .2;
    final bounds = path.getBounds();
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(1.8);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: opacity * .14),
    );
    canvas.restore();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  } else {
    canvas.drawPath(
      path,
      Paint()..color = dark.withValues(alpha: dimmed ? .08 : .4),
    );
  }
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
  final front = Rect.fromCenter(center: center, width: size, height: size);
  final topCenter = Offset(center.dx, front.top - size * .18);
  final topFace = Path()
    ..moveTo(topCenter.dx, topCenter.dy - size * .34)
    ..lineTo(topCenter.dx + size * .5, topCenter.dy)
    ..lineTo(topCenter.dx, topCenter.dy + size * .34)
    ..lineTo(topCenter.dx - size * .5, topCenter.dy)
    ..close();
  canvas.drawPath(
    topFace,
    Paint()
      ..color = Color.lerp(color, Colors.white, .3)!.withValues(alpha: alpha),
  );
  canvas.drawRect(front, Paint()..color = color.withValues(alpha: alpha));
}

double _revealValue(
  int index,
  int count,
  double controllerValue,
  BuildContext context,
) {
  if (MediaQuery.disableAnimationsOf(context)) return 1;
  final start = count <= 1 ? 0.0 : index / count * .42;
  final end = math.min(1.0, start + .58);
  final local = ((controllerValue - start) / (end - start))
      .clamp(0.0, 1.0)
      .toDouble();
  return Curves.easeOutCubic.transform(local);
}

double _revealedHeight(_VoxelSceneBar bar, double reveal) {
  if (bar.height <= 0 || reveal <= 0) return 0;
  if (reveal >= 1) return bar.height;
  final raw = bar.height * reveal;
  return math.min(bar.height, (raw / bar.blockHeight).ceil() * bar.blockHeight);
}

Path _diamond(double x, double y, double halfWidth, double depth) => Path()
  ..moveTo(x, y - depth)
  ..lineTo(x + halfWidth, y)
  ..lineTo(x, y + depth)
  ..lineTo(x - halfWidth, y)
  ..close();

int _levelsFor(
  Duration duration,
  Duration maximum, {
  required int maximumLevels,
}) {
  if (duration <= Duration.zero || maximum <= Duration.zero) return 0;
  final ratio = (duration.inMicroseconds / maximum.inMicroseconds).clamp(
    0.0,
    1.0,
  );
  return 1 + (ratio * maximumLevels).round();
}

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
