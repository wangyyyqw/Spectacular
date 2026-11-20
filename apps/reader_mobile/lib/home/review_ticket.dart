import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import 'book_cover_image.dart';

/// 书评票根：左联展示书籍与书评，副联只使用已有的日期和阅读时长。
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
  String get _dateLabel => review == null ? '最近阅读' : '书评更新';

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
    final date = (review?.updatedAt ?? book.lastReadAt)?.toLocal();
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
    final hue = HSLColor.fromAHSL(
      1,
      book.coverHue.toDouble(),
      .44,
      .55,
    ).toColor();
    final face = Ink(
      decoration: ShapeDecoration(
        shape: _PaperEdge(
          stacked ? Alignment.bottomLeft : Alignment.topRight,
          Alignment.bottomRight,
          scheme.outlineVariant,
        ),
        gradient: LinearGradient(
          colors: [
            Color.lerp(scheme.surface, hue, .28)!,
            Color.lerp(scheme.surface, hue, .055)!,
          ],
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: _bookFace(context),
    );
    final stub = Ink(
      decoration: ShapeDecoration(
        shape: _PaperEdge(
          Alignment.topLeft,
          stacked ? Alignment.topRight : Alignment.bottomLeft,
          scheme.outlineVariant,
        ),
        color: Color.lerp(scheme.surface, hue, .025),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: _stub(context, date, time, stacked),
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

  Widget _bookFace(BuildContext context) => Row(
    children: [
      BookCoverImage(book: book, width: 66, height: 94),
      const SizedBox(width: 12),
      Expanded(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 94),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(height: 1.32, fontWeight: FontWeight.w600),
                  ),
                  if (book.author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _caption(context),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _marks(context),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  TextStyle _caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(height: 1.4);

  Widget _marks(BuildContext context) {
    final style = _caption(context);
    final rating = review?.rating;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (review == null) ...[
          AppIcon(AppGlyph.editNote, size: 15, color: style.color),
          Text('写书评', style: style),
        ] else if (rating == null)
          Text('未评分', style: style)
        else
          for (var star = 1; star <= 5; star++)
            AppIcon(
              AppGlyph.star,
              size: 14,
              color: style.color,
              filled: star <= rating,
            ),
        if (_hasBody)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: AppIcon(AppGlyph.article, size: 15, color: style.color),
          ),
      ],
    );
  }

  Widget _stub(
    BuildContext context,
    DateTime? date,
    List<(String, String)> time,
    bool stacked,
  ) {
    final caption = _caption(context);
    final stamp = Column(
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
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
    final amounts = [
      for (final (value, unit) in time)
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  height: 1.16,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(text: ' $unit', style: caption),
            ],
          ),
          textAlign: TextAlign.end,
        ),
      if (time.isEmpty) Text('暂无时长记录', style: caption),
    ];
    if (stacked) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          stamp,
          Wrap(spacing: 6, children: amounts),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        stamp,
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: amounts,
          ),
        ),
      ],
    );
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
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)));
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
