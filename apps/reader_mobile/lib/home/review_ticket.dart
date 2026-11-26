import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/app_semantic_colors.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';

/// 票纸封面内缩与圆角。
const _coverInset = 6.0;
const _coverRadius = 10.0;

/// 封面固定尺寸（3:4）；上下票纸时同样使用这一尺寸。
const _coverWidth = 84.0;
const _coverHeight = _coverWidth * 4 / 3;

/// 书评区最小高度。
const _faceMinHeight = 96.0;

/// 电影票根外圆角与半圆裁切缺口半径。
const _ticketRadius = 16.0;
const _notchRadius = 8.0;
const _seamExtent = _notchRadius * 2;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _layout(context, constraints.maxWidth, date, time),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stacked = width < 300 * scale || scale >= 1.5;
    final stubFill = Color.alphaBlend(
      scheme.surfaceContainerLow.withValues(alpha: .72),
      scheme.surface,
    );
    final borderColor = scheme.outlineVariant;
    final face = Row(
      key: const ValueKey<String>('review-ticket-face'),
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(_coverInset),
          child: _cover(context),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
            child: _bookFace(context, time),
          ),
        ),
      ],
    );
    if (stacked) {
      final topClipper = _StackedTicketPartClipper(isTop: true);
      final bottomClipper = _StackedTicketPartClipper(isTop: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            foregroundPainter: _StackedTicketPartPainter(
              isTop: true,
              borderColor: borderColor,
              dashColor: borderColor,
            ),
            child: ClipPath(
              clipper: topClipper,
              child: ColoredBox(
                color: scheme.surface,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: _notchRadius),
                  child: face,
                ),
              ),
            ),
          ),
          CustomPaint(
            foregroundPainter: _StackedTicketPartPainter(
              isTop: false,
              borderColor: borderColor,
              dashColor: borderColor,
            ),
            child: ClipPath(
              clipper: bottomClipper,
              child: ColoredBox(
                color: stubFill,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    _notchRadius + 10,
                    14,
                    14,
                  ),
                  child: _stub(context, date, true),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final stubWidth = (width * .32).clamp(108 * scale, 152 * scale);
    final splitX = width - stubWidth - _seamExtent / 2;
    final clipper = _HorizontalTicketClipper(splitX: splitX);
    final shadow = theme.brightness == Brightness.light;
    return CustomPaint(
      painter: shadow ? _TicketShadowPainter(splitX: splitX) : null,
      foregroundPainter: _HorizontalTicketBorderPainter(
        splitX: splitX,
        borderColor: borderColor,
        dashColor: scheme.outline.withValues(alpha: .42),
      ),
      child: ClipPath(
        clipper: clipper,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.only(right: _seamExtent / 2),
                    child: face,
                  ),
                ),
              ),
              SizedBox(
                width: stubWidth + _seamExtent / 2,
                child: ColoredBox(
                  color: stubFill,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _seamExtent / 2 + 8,
                      12,
                      12,
                      10,
                    ),
                    child: _stub(context, date, false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final semantics = AppSemanticColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_coverRadius),
        border: Border.all(color: semantics.bookCoverBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_coverRadius - 1),
        child: SizedBox(
          width: _coverWidth,
          height: _coverHeight,
          child: BookCoverImage(
            key: const ValueKey<String>('review-ticket-cover'),
            book: book,
          ),
        ),
      ),
    );
  }

  Widget _bookFace(BuildContext context, List<(String, String)> time) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final caption = _caption(context);
    final author = book.author.trim();
    final duration = time
        .map((part) => '${part.$1 == '<1' ? '不足 1' : part.$1} ${part.$2}')
        .join(' ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _faceMinHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 书名、作者、阅读时长各占固定行高，缺字段时保留空位。
          _lineSlot(context, titleStyle, 2, book.title, titleStyle),
          const SizedBox(height: 6),
          _lineSlot(context, caption, 1, author, caption),
          const SizedBox(height: 3),
          _lineSlot(
            context,
            caption,
            1,
            duration,
            caption.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: .85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
          .copyWith(fontSize: 12, height: 1.45);

  Widget _stars(BuildContext context, int rating) {
    final semantics = AppSemanticColors.of(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Padding(
              padding: EdgeInsets.only(right: star < 5 ? 2 : 0),
              child: AppIcon(
                AppGlyph.star,
                size: 13,
                color: star <= rating
                    ? semantics.starFilled
                    : semantics.starEmpty.withValues(alpha: .48),
                filled: star <= rating,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stub(BuildContext context, DateTime? date, bool stacked) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final caption = _caption(context);
    final rating = review?.rating;
    final score = review == null
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: .22)),
            ),
            child: Text(
              '写书评',
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: stacked ? Alignment.centerLeft : Alignment.center,
            child: Text(
              rating == null ? '—' : rating.toStringAsFixed(1),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    final marks = rating == null
        ? (review == null ? null : Text('未评分', style: caption))
        : _stars(context, rating);
    final stampStyle = caption.copyWith(
      fontSize: 11,
      height: 1.35,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final stamp = Column(
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          date == null ? '暂无阅读日期' : _dateLabel,
          style: stampStyle.copyWith(
            fontSize: 10,
            letterSpacing: .6,
            color: scheme.onSurfaceVariant.withValues(alpha: .78),
          ),
        ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            score,
            if (marks != null) ...[const SizedBox(height: 4), marks],
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            stamp,
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: SizedBox(
                width: 66,
                height: 10,
                child: CustomPaint(
                  painter: _TicketBarcodePainter(
                    color: scheme.outline.withValues(alpha: .36),
                    seed: book.id.hashCode,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 生成横排电影票根路径：四角圆角 + 顶部/底部半圆裁切缺口。
Path _horizontalTicketPath(Size size, double splitX) {
  final w = size.width;
  final h = size.height;
  final r = math.min(_ticketRadius, math.min(w, h) / 4);
  final notch = math.min(_notchRadius, h / 4);
  final cx = splitX.clamp(r + notch + 2, w - r - notch - 2);
  return Path()
    ..moveTo(r, 0)
    ..lineTo(cx - notch, 0)
    ..arcToPoint(
      Offset(cx + notch, 0),
      radius: Radius.circular(notch),
      clockwise: false,
    )
    ..lineTo(w - r, 0)
    ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
    ..lineTo(w, h - r)
    ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
    ..lineTo(cx + notch, h)
    ..arcToPoint(
      Offset(cx - notch, h),
      radius: Radius.circular(notch),
      clockwise: false,
    )
    ..lineTo(r, h)
    ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
    ..lineTo(0, r)
    ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
    ..close();
}

class _HorizontalTicketClipper extends CustomClipper<Path> {
  const _HorizontalTicketClipper({required this.splitX});

  final double splitX;

  @override
  Path getClip(Size size) => _horizontalTicketPath(size, splitX);

  @override
  bool shouldReclip(_HorizontalTicketClipper oldClipper) =>
      oldClipper.splitX != splitX;
}

class _TicketShadowPainter extends CustomPainter {
  const _TicketShadowPainter({required this.splitX});

  final double splitX;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _horizontalTicketPath(size, splitX);
    canvas.drawShadow(path, const Color(0x18000000), 4, false);
  }

  @override
  bool shouldRepaint(_TicketShadowPainter oldDelegate) =>
      oldDelegate.splitX != splitX;
}

class _HorizontalTicketBorderPainter extends CustomPainter {
  const _HorizontalTicketBorderPainter({
    required this.splitX,
    required this.borderColor,
    required this.dashColor,
  });

  final double splitX;
  final Color borderColor;
  final Color dashColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _horizontalTicketPath(size, splitX);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, borderPaint);

    final cx = splitX.clamp(
      _ticketRadius + _notchRadius + 2,
      size.width - _ticketRadius - _notchRadius - 2,
    );
    final dashPaint = Paint()
      ..color = dashColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const dashLen = 3.5;
    const gapLen = 4.5;
    var y = _notchRadius + 5;
    final endY = size.height - _notchRadius - 5;
    while (y < endY) {
      final next = math.min(y + dashLen, endY);
      canvas.drawLine(Offset(cx, y), Offset(cx, next), dashPaint);
      y += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_HorizontalTicketBorderPainter oldDelegate) =>
      oldDelegate.splitX != splitX ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.dashColor != dashColor;
}

/// 窄屏/大字号上下票根路径：主联底角与副联顶角向内凹 1/4 圆，拼合后形成左右对称半圆缺口。
Path _stackedPartPath(Size size, {required bool isTop}) {
  final w = size.width;
  final h = size.height;
  final r = math.min(_ticketRadius, math.min(w, h) / 3);
  final notch = math.min(_notchRadius, h / 2);
  if (isTop) {
    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - notch)
      ..arcToPoint(
        Offset(w - notch, h),
        radius: Radius.circular(notch),
        clockwise: false,
      )
      ..lineTo(notch, h)
      ..arcToPoint(
        Offset(0, h - notch),
        radius: Radius.circular(notch),
        clockwise: false,
      )
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
  }
  return Path()
    ..moveTo(notch, 0)
    ..lineTo(w - notch, 0)
    ..arcToPoint(
      Offset(w, notch),
      radius: Radius.circular(notch),
      clockwise: false,
    )
    ..lineTo(w, h - r)
    ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
    ..lineTo(r, h)
    ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
    ..lineTo(0, notch)
    ..arcToPoint(
      Offset(notch, 0),
      radius: Radius.circular(notch),
      clockwise: false,
    )
    ..close();
}

class _StackedTicketPartClipper extends CustomClipper<Path> {
  const _StackedTicketPartClipper({required this.isTop});

  final bool isTop;

  @override
  Path getClip(Size size) => _stackedPartPath(size, isTop: isTop);

  @override
  bool shouldReclip(_StackedTicketPartClipper oldClipper) =>
      oldClipper.isTop != isTop;
}

class _StackedTicketPartPainter extends CustomPainter {
  const _StackedTicketPartPainter({
    required this.isTop,
    required this.borderColor,
    required this.dashColor,
  });

  final bool isTop;
  final Color borderColor;
  final Color dashColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = math.min(_ticketRadius, math.min(w, h) / 3);
    final notch = math.min(_notchRadius, h / 2);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path();
    if (isTop) {
      outline
        ..moveTo(0, h - notch)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
        ..lineTo(w - r, 0)
        ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
        ..lineTo(w, h - notch)
        ..arcToPoint(
          Offset(w - notch, h),
          radius: Radius.circular(notch),
          clockwise: false,
        );
      final leftArc = Path()
        ..moveTo(notch, h)
        ..arcToPoint(
          Offset(0, h - notch),
          radius: Radius.circular(notch),
          clockwise: false,
        );
      canvas.drawPath(outline, borderPaint);
      canvas.drawPath(leftArc, borderPaint);

      final dashPaint = Paint()
        ..color = dashColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      var x = notch + 5;
      final endX = w - notch - 5;
      while (x < endX) {
        final next = math.min(x + 3.5, endX);
        canvas.drawLine(Offset(x, h - .5), Offset(next, h - .5), dashPaint);
        x += 8;
      }
    } else {
      outline
        ..moveTo(w - notch, 0)
        ..arcToPoint(
          Offset(w, notch),
          radius: Radius.circular(notch),
          clockwise: false,
        )
        ..lineTo(w, h - r)
        ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
        ..lineTo(r, h)
        ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
        ..lineTo(0, notch)
        ..arcToPoint(
          Offset(notch, 0),
          radius: Radius.circular(notch),
          clockwise: false,
        );
      canvas.drawPath(outline, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_StackedTicketPartPainter oldDelegate) =>
      oldDelegate.isTop != isTop ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.dashColor != dashColor;
}

/// 电影票存根底部的极简条码纹样，按书籍 ID 生成稳定节奏。
class _TicketBarcodePainter extends CustomPainter {
  const _TicketBarcodePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    var state = seed == 0 ? 0x5A17 : seed;
    var x = 0.0;
    while (x < size.width) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final barWidth = ((state >> 16) % 3 == 0) ? 2.0 : 1.0;
      if (x + barWidth <= size.width) {
        canvas.drawRect(Rect.fromLTWH(x, 0, barWidth, size.height), paint);
      }
      final gap = ((state >> 20) % 2 == 0) ? 1.5 : 2.5;
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_TicketBarcodePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}
