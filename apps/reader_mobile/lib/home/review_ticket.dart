import 'package:reader_ui/rating/reader_rating.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';

/// 票纸外圆角与封面内缩、圆角。
const _coverInset = 6.0;
const _coverRadius = 6.0;

/// 封面固定尺寸（3:4）；上下票纸时同样使用这一尺寸。
const _coverWidth = 76.0;
const _coverHeight = _coverWidth * 4 / 3;

/// 书评区最小高度。
const _faceMinHeight = _coverHeight;

/// 书评票根：左联是整幅封面、书名和阅读信息，副联仿电影票根用大字评分、
/// 星级和标记读完日期呈现，两联之间保留票纸裁切缺口。
class ReviewTicket extends StatelessWidget {
  const ReviewTicket({
    super.key,
    required this.book,
    required this.review,
    required this.duration,
    required this.onTap,
    this.readDays,
  });

  final BookEntry book;
  final BookReview? review;
  final Duration? duration;
  final VoidCallback onTap;
  final int? readDays;

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
      if (readDays != null) '阅读 $readDays 天',
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
    final stubWidth = (width * .31).clamp(100 * scale, 150 * scale);
    final textWidth = math.max(
      0.0,
      width -
          (stacked ? 0 : stubWidth + 12) -
          _coverWidth -
          _coverInset * 2 -
          22,
    );
    final face = Row(
      key: const ValueKey<String>('review-ticket-face'),
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(padding: const EdgeInsets.all(_coverInset), child: _cover()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            child: _bookFace(context, time, textWidth),
          ),
        ),
      ],
    );
    final stub = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: _stub(context, date, stacked),
    );
    final Widget body;
    if (stacked) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [face, _seam(context, horizontal: true), stub],
      );
    } else {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: face),
            _seam(context, horizontal: false),
            SizedBox(width: stubWidth, child: stub),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(_coverRadius),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: body,
    );
  }

  /// 两联之间的锯齿撕口，模仿票根的打孔虚线。
  Widget _seam(BuildContext context, {required bool horizontal}) => SizedBox(
    width: horizontal ? null : 12,
    height: horizontal ? 12 : null,
    child: CustomPaint(
      painter: _SeamPainter(
        Theme.of(context).colorScheme.outlineVariant,
        horizontal,
      ),
    ),
  );

  Widget _cover() => ClipRRect(
    borderRadius: BorderRadius.circular(_coverRadius),
    child: SizedBox(
      width: _coverWidth,
      height: _coverHeight,
      child: BookCoverImage(
        key: const ValueKey<String>('review-ticket-cover'),
        book: book,
      ),
    ),
  );

  Widget _bookFace(
    BuildContext context,
    List<(String, String)> time,
    double width,
  ) {
    final titleStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 16, height: 1.25, fontWeight: FontWeight.w600);
    final caption = _caption(context);
    final author = book.author.trim();
    final duration = time
        .map((part) => '${part.$1 == '<1' ? '不足 1' : part.$1} ${part.$2}')
        .join(' ');
    final title = TextPainter(
      text: TextSpan(text: book.title, style: titleStyle),
      maxLines: 2,
      ellipsis: '…',
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final titleLines = title.computeLineMetrics().length.clamp(1, 2);
    title.dispose();
    final titleHeight = _lineHeight(context, titleStyle) * titleLines;
    final captionHeight = _lineHeight(context, caption);
    final contentHeight =
        titleHeight +
        3 +
        captionHeight * 2 +
        (readDays == null ? 0 : captionHeight + 2);
    final gap = math.max(2.0, _faceMinHeight - contentHeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 书名按实际行数占位，作者紧随书名，余白留在阅读数据上方。
        _lineSlot(context, titleStyle, titleLines, book.title, titleStyle),
        const SizedBox(height: 3),
        _lineSlot(context, caption, 1, author, caption),
        SizedBox(height: gap),
        if (readDays != null) ...[
          _lineSlot(context, caption, 1, '阅读 $readDays 天', caption),
          const SizedBox(height: 2),
        ],
        _lineSlot(context, caption, 1, duration, caption),
      ],
    );
  }

  Widget _lineSlot(
    BuildContext context,
    TextStyle style,
    int lines,
    String text,
    TextStyle textStyle,
  ) => SizedBox(
    height: _lineHeight(context, style) * lines,
    child: Align(
      alignment: Alignment.topLeft,
      child: text.isEmpty
          ? null
          : Text(
              text,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
    ),
  );

  double _lineHeight(BuildContext context, TextStyle style) =>
      MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) *
      (style.height ?? 1);

  TextStyle _caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!
          .copyWith(fontSize: 12, height: 1.35);

  Widget _stars(BuildContext context, num rating) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: ReaderRatingStars(rating: rating, size: 16),
  );

  Widget _stub(BuildContext context, DateTime? date, bool stacked) {
    final theme = Theme.of(context);
    final caption = _caption(context);
    final rating = review?.rating;
    final score = review == null
        ? Text(
            '写书评',
            style: theme.textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              rating == null ? '—' : rating.toStringAsFixed(1),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 34,
                height: 1.08,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    final marks = rating == null
        ? (review == null ? null : Text('未评分', style: caption))
        : _stars(context, rating);
    final stampStyle = caption.copyWith(fontSize: 11, height: 1.25);
    final stamp = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date == null ? '暂无阅读日期' : _dateLabel, style: stampStyle),
        if (date != null)
          Text(
            '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
            style: stampStyle,
          ),
      ],
    );
    if (stacked) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [score, ?marks, stamp],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            score,
            if (marks != null) ...[const SizedBox(height: 2), marks],
          ],
        ),
        Padding(padding: const EdgeInsets.only(top: 4), child: stamp),
      ],
    );
  }
}

/// 两联之间的波浪撕口，仿票根打孔线的走向。
class _SeamPainter extends CustomPainter {
  const _SeamPainter(this.color, this.horizontal);

  final Color color;
  final bool horizontal;

  static const double _depth = 3;
  static const double _step = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    final path = Path();
    if (horizontal) {
      final y = size.height / 2;
      path.moveTo(0, y);
      var x = 0.0;
      var up = true;
      while (x < size.width) {
        final next = math.min(x + _step, size.width);
        path.quadraticBezierTo(
          (x + next) / 2,
          up ? y - _depth : y + _depth,
          next,
          y,
        );
        up = !up;
        x = next;
      }
    } else {
      final x = size.width / 2;
      path.moveTo(x, 0);
      var y = 0.0;
      var left = true;
      while (y < size.height) {
        final next = math.min(y + _step, size.height);
        path.quadraticBezierTo(
          left ? x - _depth : x + _depth,
          (y + next) / 2,
          x,
          next,
        );
        left = !left;
        y = next;
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SeamPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.horizontal != horizontal;
}
