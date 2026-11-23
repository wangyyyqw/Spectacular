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
  });

  final List<DurationBarData> bars;
  final List<TimeOfDayBarData> timeBars;
  final Duration total;
  final int bookCount;
  final String? selectedBookId;
  final ValueChanged<DurationBarData> onSelected;

  @override
  State<VoxelDurationChart> createState() => _VoxelDurationChartState();
}

enum _VoxelChartMode { books, timeOfDay }

class _VoxelDurationChartState extends State<VoxelDurationChart>
    with TickerProviderStateMixin {
  static const _plotHeight = 176.0;

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
    if (MediaQuery.disableAnimationsOf(context)) {
      _revealController
        ..stop()
        ..value = 1;
    } else {
      _revealController.forward(from: 0);
    }
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
    final showValue = textScale <= 1.4;
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
          _header(context, selected: selected, activeBuckets: activeBuckets),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => _chartBody(
              context,
              width: constraints.maxWidth,
              labelHeight: labelHeight,
              showValue: showValue,
              showBookLabel: showBookLabel,
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
    required bool showValue,
    required bool showBookLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final targetScene = _sceneFor(_mode, width);
    final staticChart = _StaticVoxelChart(
      scene: targetScene,
      width: width,
      plotHeight: _plotHeight,
      labelHeight: labelHeight,
      selectedBookId: widget.selectedBookId,
      showValue: showValue,
      showBookLabel: showBookLabel,
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
      child: staticChart,
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
                      toScene: targetScene,
                      particles: particles,
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
    required this.showValue,
    required this.showBookLabel,
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
  final bool showValue;
  final bool showBookLabel;
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
                if (!scene.isTime && showValue)
                  for (var index = 0; index < scene.bars.length; index++)
                    _valuePill(
                      scene.bars[index],
                      reveals[index],
                      slotWidth,
                      index,
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

  Widget _valuePill(
    _VoxelSceneBar bar,
    double reveal,
    double slotWidth,
    int index,
  ) {
    final visibleHeight = _revealedHeight(bar, reveal);
    final share = bar.share;
    if (visibleHeight <= 0 || share == null) return const SizedBox.shrink();
    final opacity = ((reveal - .15) / .85).clamp(0.0, 1.0).toDouble();
    final top = (bar.baseY - visibleHeight - bar.depth - 25)
        .clamp(0.0, math.max(0.0, plotHeight - 22))
        .toDouble();
    final selected = bar.bookId != null && bar.bookId == selectedBookId;
    return Positioned(
      left: slotWidth * index + 2,
      width: math.max(0, slotWidth - 4),
      top: top,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Center(
            child: _ValuePill(
              share: share,
              color: bar.segments.first.color,
              selected: selected,
              dimmed: selectedBookId != null && !selected,
            ),
          ),
        ),
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

class _ValuePill extends StatelessWidget {
  const _ValuePill({
    required this.share,
    required this.color,
    required this.selected,
    required this.dimmed,
  });

  final String share;
  final Color color;
  final bool selected;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : scheme.onSurface)
        : scheme.onSurfaceVariant;
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 40),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? color : scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? color : scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: selected ? .12 : .05),
            blurRadius: selected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            share,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: dimmed && !selected
                  ? foreground.withValues(alpha: .72)
                  : foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
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
    segments: [
      _VoxelSceneSegment(
        key: bar.key,
        title: bar.title,
        color: bar.color,
        duration: bar.duration,
        height: height,
      ),
    ],
    centerX: slotWidth * (index + .5),
    halfWidth: halfWidth,
    depth: depth,
    baseY: plotHeight - depth - 6 - (selected ? 4 : 0),
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
    segments: _timeSegments(bar, height),
    centerX: slotWidth * (index + .5),
    halfWidth: halfWidth,
    depth: depth,
    baseY: plotHeight - depth - 6,
  );
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
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
  });

  final _VoxelScene scene;
  final List<double> reveals;
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
    required this.toScene,
    required this.particles,
    required this.plotHeight,
    required this.progress,
    required this.selectedBookId,
    required this.shadowColor,
    required this.baseColor,
  });

  final _VoxelScene fromScene;
  final _VoxelScene toScene;
  final List<_MorphParticle> particles;
  final double plotHeight;
  final double progress;
  final String? selectedBookId;
  final Color shadowColor;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, plotHeight));
    final sourceOpacity = 1 - _smooth01(progress / .22);
    final targetOpacity = _smooth01((progress - .58) / .38);
    _paintScene(
      canvas,
      size,
      fromScene,
      reveals: List.filled(fromScene.bars.length, 1.0),
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
      opacity: sourceOpacity,
    );
    _paintScene(
      canvas,
      size,
      toScene,
      reveals: List.filled(toScene.bars.length, 1.0),
      selectedBookId: selectedBookId,
      shadowColor: shadowColor,
      baseColor: baseColor,
      opacity: targetOpacity,
    );
    _paintParticles(canvas);
    canvas.restore();
  }

  void _paintParticles(Canvas canvas) {
    final fade =
        _smooth01(progress / .08) * (1 - _smooth01((progress - .9) / .08));
    if (fade <= 0) return;
    for (final particle in particles) {
      final start = .06 + particle.delay * .16;
      final local = ((progress - start) / .62).clamp(0.0, 1.0).toDouble();
      final eased = Curves.easeInOutCubic.transform(local);
      final burst = math.sin(math.pi * local);
      var center = Offset.lerp(particle.start, particle.end, eased)!;
      center +=
          Offset(math.cos(particle.angle), math.sin(particle.angle)) *
          particle.spread *
          burst;
      center += Offset(0, -burst * particle.size * 2.4);
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
      oldDelegate.toScene != toScene ||
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
    final count = (8 + 30 * math.sqrt(share)).round().clamp(8, 38);
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
          spread: 5 + _random(seed + 6) * 20,
          angle: _random(seed + 7) * math.pi * 2,
          size: 2.8 + _random(seed + 8) * 2.4,
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
    var consumed = 0.0;
    for (final segment in bar.segments) {
      final height = segment.height;
      if (height <= 0) {
        consumed += height;
        continue;
      }
      final bottom = bar.baseY - consumed;
      final rect = Rect.fromLTRB(
        bar.centerX - bar.halfWidth * .9,
        bottom - height,
        bar.centerX + bar.halfWidth * .9,
        bottom,
      );
      result.putIfAbsent(segment.key, () => []).add(rect);
      consumed += height;
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
  required String? selectedBookId,
  required Color shadowColor,
  required Color baseColor,
}) {
  _paintBarBase(canvas, bar, shadowColor, baseColor);
  var consumed = 0.0;
  for (final segment in bar.segments) {
    if (consumed >= visibleHeight) break;
    final height = math.min(segment.height, visibleHeight - consumed);
    if (height > .1) {
      final dimmed = selectedBookId != null && segment.key != selectedBookId;
      _paintSegment(
        canvas,
        bar,
        segment: segment,
        yBottom: bar.baseY - consumed,
        yTop: bar.baseY - consumed - height,
        dimmed: dimmed,
      );
    }
    consumed += segment.height;
  }
  _paintSeams(canvas, bar, visibleHeight, shadowColor);
}

void _paintBarBase(
  Canvas canvas,
  _VoxelSceneBar bar,
  Color shadowColor,
  Color baseColor,
) {
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(bar.centerX, bar.baseY + bar.depth * .84),
      width: bar.halfWidth * 2.8,
      height: bar.depth * 1.35,
    ),
    Paint()..color = shadowColor.withValues(alpha: .07),
  );
  canvas.drawPath(
    _diamond(bar.centerX, bar.baseY, bar.halfWidth + 2.4, bar.depth + 1.6),
    Paint()..color = baseColor.withValues(alpha: .7),
  );
}

void _paintSegment(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required _VoxelSceneSegment segment,
  required double yBottom,
  required double yTop,
  required bool dimmed,
}) {
  final tint = dimmed
      ? segment.color.withValues(alpha: segment.color.a * .32)
      : segment.color;
  final centerX = bar.centerX;
  final halfWidth = bar.halfWidth;
  final depth = bar.depth;
  final north = Offset(centerX, yTop - depth);
  final east = Offset(centerX + halfWidth, yTop);
  final south = Offset(centerX, yTop + depth);
  final west = Offset(centerX - halfWidth, yTop);
  final baseSouth = Offset(centerX, yBottom + depth);
  final baseWest = Offset(centerX - halfWidth, yBottom);
  final baseEast = Offset(centerX + halfWidth, yBottom);
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
  final topFace = Path()
    ..moveTo(north.dx, north.dy)
    ..lineTo(east.dx, east.dy)
    ..lineTo(south.dx, south.dy)
    ..lineTo(west.dx, west.dy)
    ..close();
  canvas.drawPath(
    leftFace,
    Paint()..color = Color.lerp(tint, Colors.black, .18)!,
  );
  canvas.drawPath(
    rightFace,
    Paint()..color = Color.lerp(tint, Colors.white, .08)!,
  );
  canvas.drawPath(
    topFace,
    Paint()..color = Color.lerp(tint, Colors.white, .24)!,
  );
  canvas.drawLine(
    west,
    baseWest,
    Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1,
  );
  _paintFloorLights(canvas, bar, yTop: yTop, yBottom: yBottom, dimmed: dimmed);
  canvas.drawPath(
    topFace,
    Paint()
      ..color = Colors.white.withValues(alpha: .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}

void _paintFloorLights(
  Canvas canvas,
  _VoxelSceneBar bar, {
  required double yTop,
  required double yBottom,
  required bool dimmed,
}) {
  final blockHeight = bar.blockHeight;
  final firstFloor = ((bar.baseY - yBottom) / blockHeight).floor();
  final lastFloor = ((bar.baseY - yTop) / blockHeight).ceil();
  final windowWidth = (bar.halfWidth * .16).clamp(2.2, 3.6).toDouble();
  final windowHeight = (blockHeight * .26).clamp(1.7, 2.6).toDouble();
  final widthRatio = windowWidth / bar.halfWidth;
  for (var floor = firstFloor; floor < lastFloor; floor++) {
    final centerY = bar.baseY - (floor + .5) * blockHeight;
    if (centerY < yTop + windowHeight || centerY > yBottom - windowHeight) {
      continue;
    }
    for (var side = 0; side < 2; side++) {
      final seed = bar.index * 997 + floor * 31 + side * 127;
      if (_random(seed) > (dimmed ? .12 : .34)) continue;
      final centerRatio = .26 + _random(seed + 1) * .48;
      final start = (centerRatio - widthRatio / 2).clamp(.04, .7).toDouble();
      final end = (centerRatio + widthRatio / 2).clamp(.3, .96).toDouble();
      final path = _windowPath(
        bar,
        side: side,
        start: start,
        end: end,
        centerY: centerY,
        height: windowHeight,
      );
      final color = _random(seed + 2) > .42
          ? const Color(0xFFFFB65E)
          : const Color(0xFFFFD28C);
      final opacity = dimmed ? .18 : .72 + _random(seed + 3) * .28;
      final bounds = path.getBounds();
      canvas.save();
      canvas.translate(bounds.center.dx, bounds.center.dy);
      canvas.scale(1.75);
      canvas.translate(-bounds.center.dx, -bounds.center.dy);
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: opacity * .16),
      );
      canvas.restore();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
    }
  }
}

Path _windowPath(
  _VoxelSceneBar bar, {
  required int side,
  required double start,
  required double end,
  required double centerY,
  required double height,
}) {
  Offset point(double ratio, double y) {
    if (side == 0) {
      return Offset(
        bar.centerX - bar.halfWidth + bar.halfWidth * ratio,
        y + bar.depth * ratio,
      );
    }
    return Offset(
      bar.centerX + bar.halfWidth * ratio,
      y + bar.depth * (1 - ratio),
    );
  }

  final top = centerY - height / 2;
  final bottom = centerY + height / 2;
  final topLeft = point(start, top);
  final topRight = point(end, top);
  final bottomRight = point(end, bottom);
  final bottomLeft = point(start, bottom);
  return Path()
    ..moveTo(topLeft.dx, topLeft.dy)
    ..lineTo(topRight.dx, topRight.dy)
    ..lineTo(bottomRight.dx, bottomRight.dy)
    ..lineTo(bottomLeft.dx, bottomLeft.dy)
    ..close();
}

void _paintSeams(
  Canvas canvas,
  _VoxelSceneBar bar,
  double visibleHeight,
  Color shadowColor,
) {
  final topY = bar.baseY - visibleHeight;
  final paint = Paint()
    ..color = shadowColor.withValues(alpha: .22)
    ..strokeWidth = .8;
  for (
    var y = bar.baseY - bar.blockHeight;
    y > topY + .1;
    y -= bar.blockHeight
  ) {
    canvas.drawLine(
      Offset(bar.centerX - bar.halfWidth, y),
      Offset(bar.centerX, y + bar.depth),
      paint,
    );
    canvas.drawLine(
      Offset(bar.centerX, y + bar.depth),
      Offset(bar.centerX + bar.halfWidth, y),
      paint,
    );
  }
  canvas.drawLine(
    Offset(bar.centerX, topY + bar.depth),
    Offset(bar.centerX, bar.baseY + bar.depth),
    Paint()
      ..color = shadowColor.withValues(alpha: .12)
      ..strokeWidth = .8,
  );
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
