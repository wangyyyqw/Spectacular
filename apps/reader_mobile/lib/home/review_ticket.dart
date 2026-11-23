import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';

/// 封面宽高比。
const _coverRatio = 3 / 4;

/// 票纸外圆角。
const _paperRadius = 4.0;

/// 书评区最小高度与内边距；封面在左右分栏时按这两项换算成 3:4。
const _faceMinHeight = 94.0;
const _facePadding = 12.0;
const _coverHeight = _faceMinHeight + _facePadding * 2;

/// 书评票根：左联是整幅封面、书名和阅读信息，副联仿电影票根用大字评分、
/// 星级和标记读完日期呈现，两联之间保留票纸裁切缺口。
class ReviewTicket extends StatelessWidget {
  const ReviewTicket({
    super.key,
    required this.book,
    required this.review,
    required this.duration,
    required this.onTap,
  });

  final BookEntry book;
  final BookReview? review;
  final Duration? duration;
  final VoidCallback onTap;

  bool get _hasBody => review?.content.trim().isNotEmpty ?? false;
  String get _dateLabel => review == null ? '最近阅读' : '标记读完';

  List<(String, String)> get _timeParts {
    final elapsed = duration;
    if (elapsed == null || elapsed <= Duration.zero) return const [];
    if (elapsed.inMinutes == 0) return const [('<1', '分钟')];
    final minutes = (elapsed.inSeconds / Duration.secondsPerMinute).ceil();
    return [
      if (minutes >= 60) ('${minutes ~/ 60}', '小时'),
      if (minutes % 60 != 0) ('${minutes % 60}', '分钟'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final date = (review?.createdAt ?? book.lastReadAt)?.toLocal();
    final time = _timeParts;
    final label = [
      book.title,
      if (book.author.isNotEmpty) book.author,
      if (review != null)
        review!.rating == null ? '未评分' : '${review!.rating} 星',
      if (_hasBody) '有书评正文',
      if (date == null)
        '暂无阅读日期'
      else
        '$_dateLabel：${date.year}年${date.month}月${date.day}日',
      if (time.isEmpty)
        '暂无时长记录'
      else
        '累计阅读${time.map((part) => '${part.$1 == '<1' ? '不足 1' : part.$1} ${part.$2}').join(' ')}',
    ].join('，');
    return Semantics(
      button: true,
      label: label,
      hint: review == null ? '写书评' : '查看书评',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _layout(context, constraints.maxWidth, date, time),
          ),
        ),
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    double width,
    DateTime? date,
    List<(String, String)> time,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stacked = width < 300 * scale || scale >= 1.5;
    final face = Ink(
      key: const ValueKey<String>('review-ticket-face'),
      decoration: ShapeDecoration(
        shape: _PaperEdge(
          stacked ? Alignment.bottomLeft : Alignment.topRight,
          Alignment.bottomRight,
          scheme.outlineVariant,
        ),
        color: scheme.surface,
      ),
      child: Row(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.stretch,
        children: [
          _cover(stretch: !stacked),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(_facePadding),
              child: _bookFace(context, time),
            ),
          ),
        ],
      ),
    );
    final stub = Ink(
      decoration: ShapeDecoration(
        shape: _PaperEdge(
          Alignment.topLeft,
          stacked ? Alignment.topRight : Alignment.bottomLeft,
          scheme.outlineVariant,
        ),
        color: scheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: _stub(context, date, stacked),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [face, stub],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: face),
          SizedBox(
            width: (width * .29).clamp(94 * scale, 140 * scale),
            child: stub,
          ),
        ],
      ),
    );
  }

  Widget _cover({required bool stretch}) {
    final image = BookCoverImage(
      key: const ValueKey<String>('review-ticket-cover'),
      book: book,
    );
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(_paperRadius),
      ),
      // 左右分栏时封面高度跟随票纸，宽度按 3:4 换算并贴齐上、左、下边缘。
      child: stretch
          ? _CoverAspect(child: image)
          : SizedBox(
              width: _coverHeight * _coverRatio,
              height: _coverHeight,
              child: image,
            ),
    );
  }

  Widget _bookFace(BuildContext context, List<(String, String)> time) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _faceMinHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 17,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _meta(context, time),
            ),
          ],
        ),
      );

  /// 书名下方的斜线分隔信息，模仿票根的“时长 / 类型 / 导演”一行。
  Widget _meta(BuildContext context, List<(String, String)> time) {
    final style = _caption(context);
    final duration = time.isEmpty
        ? '暂无时长记录'
        : time
              .map((part) => '${part.$1 == '<1' ? '不足 1' : part.$1} ${part.$2}')
              .join(' ');
    final parts = <String>[if (book.author.isNotEmpty) book.author, duration];
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (index > 0) Text('/', style: style),
          Text(parts[index], style: style),
        ],
      ],
    );
  }

  TextStyle _caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(height: 1.4);

  Widget _badge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        review == null ? '写书评' : '我的评分',
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _stars(BuildContext context, int rating) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var star = 1; star <= 5; star++)
        Padding(
          padding: const EdgeInsets.only(right: 1),
          child: AppIcon(
            AppGlyph.star,
            size: 12,
            color: Theme.of(context).colorScheme.onSurface,
            filled: star <= rating,
          ),
        ),
    ],
  );

  Widget _stub(BuildContext context, DateTime? date, bool stacked) {
    final theme = Theme.of(context);
    final caption = _caption(context);
    final rating = review?.rating;
    final score = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        rating == null ? '—' : rating.toStringAsFixed(1),
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.bodyMedium!.copyWith(
          fontSize: 28,
          height: 1.1,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final marks = rating == null
        ? (review == null ? null : Text('未评分', style: caption))
        : _stars(context, rating);
    final stamp = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date == null ? '暂无阅读日期' : _dateLabel, style: caption),
        if (date != null)
          Text(
            '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
            style: caption.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
    final badge = _badge(context);
    if (stacked) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [badge, score, ?marks, stamp],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            badge,
            const SizedBox(height: 6),
            score,
            if (marks != null) ...[const SizedBox(height: 2), marks],
          ],
        ),
        Padding(padding: const EdgeInsets.only(top: 8), child: stamp),
      ],
    );
  }
}

/// 高度由票纸决定、宽度固定为高度的 3/4 的封面槽。
///
/// 固有高度固定为 0，卡片高度仍由文字内容决定；布局时再按实际高度换算宽度，
/// 保证封面既是 3:4 又贴齐票纸的上、左、下边缘。
class _CoverAspect extends SingleChildRenderObjectWidget {
  const _CoverAspect({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCoverAspect();
}

class _RenderCoverAspect extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  double computeMinIntrinsicWidth(double height) =>
      height.isFinite ? height * _coverRatio : 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      height.isFinite ? height * _coverRatio : 0;

  @override
  void performLayout() {
    final height = constraints.maxHeight;
    final width = height.isFinite ? height * _coverRatio : 0.0;
    size = constraints.constrain(Size(width, height));
    child?.layout(BoxConstraints.tight(size));
  }
}

class _PaperEdge extends ShapeBorder {
  const _PaperEdge(this.firstNotch, this.lastNotch, this.line);

  final Alignment firstNotch;
  final Alignment lastNotch;
  final Color line;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double factor) => this;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final paper = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_paperRadius)),
      );
    final cutouts = Path();
    for (final notch in [firstNotch, lastNotch]) {
      cutouts.addOval(
        Rect.fromCircle(center: notch.withinRect(rect), radius: 9),
      );
    }
    return Path.combine(PathOperation.difference, paper, cutouts);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(.5));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      getInnerPath(rect),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
  }
}
