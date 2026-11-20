import 'dart:math' as math;

import 'package:flutter/material.dart';

const double _strokeWidth = 1.7;

/// 界面图标字形。底栏四图标与其余图标共用 24 格坐标、1.7 线宽与圆角拐角，
/// 细节以实心小片表示；实心态把轮廓改为实心，细节镂空为底色。
enum AppGlyph {
  bookshelf(_bookshelf),
  discover(_discover),
  stats(_stats),
  review(_review),
  profile(_profile),
  arrowBack(_arrowBack),
  arrowForward(_arrowForward),
  chevronLeft(_chevronLeft),
  chevronRight(_chevronRight),
  chevronUp(_chevronUp),
  chevronDown(_chevronDown),
  skipPrevious(_skipPrevious),
  skipNext(_skipNext),
  play(_play),
  close(_close),
  add(_add),
  addCircle(_addCircle),
  remove(_remove),
  removeCircle(_removeCircle),
  check(_check),
  checkCircle(_checkCircle),
  search(_search),
  searchOff(_searchOff),
  refresh(_refresh),
  restore(_restore),
  undo(_undo),
  redo(_redo),
  save(_save),
  locate(_locate),
  tune(_tune),
  settings(_settings),
  more(_more),
  dragHandle(_dragHandle),
  sort(_sort),
  filter(_filter),
  filterOff(_filterOff),
  gridView(_gridView),
  listView(_listView),
  grid(_grid),
  pageMargin(_pageMargin),
  share(_share),
  upload(_upload),
  copy(_copy),
  link(_link),
  code(_code),
  delete(_delete),
  deleteSweep(_deleteSweep),
  edit(_edit),
  editNote(_editNote),
  highlighter(_highlighter),
  note(_note),
  article(_article),
  noteAdd(_noteAdd),
  rateReview(_rateReview),
  bookmark(_bookmark),
  bookmarkAdd(_bookmarkAdd),
  pushPin(_pushPin),
  star(_star),
  radioChecked(_radioChecked),
  radioUnchecked(_radioUnchecked),
  checklist(_checklist),
  lock(_lock),
  preview(_preview),
  touchApp(_touchApp),
  autoFix(_autoFix),
  palette(_palette),
  formatPaint(_formatPaint),
  formatUnderlined(_formatUnderlined),
  textFields(_textFields),
  listBulleted(_listBulleted),
  headphones(_headphones),
  image(_image),
  addImage(_addImage),
  brokenImage(_brokenImage),
  folder(_folder),
  folderOff(_folderOff),
  folderAdd(_folderAdd),
  warning(_warning),
  error(_error),
  info(_info),
  lightMode(_lightMode),
  darkMode(_darkMode),
  menuBook(_menuBook),
  autoStories(_autoStories);

  const AppGlyph(this.draw);

  /// 在 24 格坐标系中绘制字形。
  final void Function(AppIconCanvas canvas) draw;
}

/// 图标画布：统一笔触与填充规则，字形只描述 24 格坐标下的几何。
class AppIconCanvas {
  AppIconCanvas(
    this._canvas, {
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final Canvas _canvas;
  final Color color;
  final bool filled;
  final Color cutoutColor;

  /// 线段与开放折线，始终描边。
  void line(Path path) => _canvas.drawPath(path, _strokePaint(color));

  /// 轮廓：线框态描边，实心态填充。
  void outline(Path path) =>
      _canvas.drawPath(path, filled ? _fillPaint(color) : _strokePaint(color));

  /// 实心细节：线框态使用前景色，实心态镂空为底色。
  void solid(Path path) =>
      _canvas.drawPath(path, _fillPaint(filled ? cutoutColor : color));

  void rotate(Offset center, double radians, void Function() draw) {
    _canvas.save();
    _canvas.translate(center.dx, center.dy);
    _canvas.rotate(radians);
    _canvas.translate(-center.dx, -center.dy);
    draw();
    _canvas.restore();
  }

  void mirror(void Function() draw) {
    _canvas.save();
    _canvas.translate(24, 0);
    _canvas.scale(-1, 1);
    draw();
    _canvas.restore();
  }

  void clip(Path path, void Function() draw) {
    _canvas.save();
    _canvas.clipPath(path);
    draw();
    _canvas.restore();
  }
}

Paint _strokePaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = _strokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fillPaint(Color color) => Paint()..color = color;

Path _roundRect(
  double left,
  double top,
  double right,
  double bottom,
  double radius,
) => Path()
  ..addRRect(
    RRect.fromLTRBR(left, top, right, bottom, Radius.circular(radius)),
  );

Path _circle(double centerX, double centerY, double radius) => Path()
  ..addOval(Rect.fromCircle(center: Offset(centerX, centerY), radius: radius));

Path _polylines(List<List<Offset>> lines) {
  final path = Path();
  for (final points in lines) {
    path.addPolygon(points, false);
  }
  return path;
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

Offset _polar(double radius, double angle) =>
    Offset(12 + radius * math.cos(angle), 12 + radius * math.sin(angle));

void _bookshelf(AppIconCanvas canvas) {
  canvas.outline(_roundRect(2.8, 2.7, 10.6, 21.3, 1.2));
  canvas.rotate(const Offset(13.75, 12), -0.16, () {
    canvas.outline(_roundRect(12.4, 3, 15.1, 21, 1.2));
  });
  canvas.rotate(const Offset(18.65, 12), -0.16, () {
    canvas.outline(_roundRect(17.3, 3, 20, 21, 1.2));
  });
  canvas.solid(_roundRect(5.5, 9.6, 8, 11.1, 0.75));
  canvas.solid(_roundRect(5.5, 13.1, 8, 14.6, 0.75));
}

void _stats(AppIconCanvas canvas) {
  canvas.outline(_roundRect(3.1, 11.7, 7.5, 20.5, 1.2));
  canvas.outline(_roundRect(9.8, 7, 14.2, 20.5, 1.2));
  canvas.outline(_roundRect(16.5, 2.7, 20.9, 20.5, 1.2));
}

void _review(AppIconCanvas canvas) {
  canvas.rotate(const Offset(18.75, 11.45), -0.17, () {
    canvas.outline(_roundRect(17.4, 2.7, 20.1, 20.2, 1.2));
  });
  canvas.outline(_roundRect(2.8, 2.7, 10.1, 21.3, 1.2));
  canvas.outline(_roundRect(10.8, 8.5, 16, 21.3, 1.2));
  canvas.solid(
    canvas.filled
        ? _roundRect(11.7, 14, 15.1, 16.2, 1.1)
        : _roundRect(11.9, 14, 14.9, 15.4, 0.7),
  );
}

void _profile(AppIconCanvas canvas) {
  final badge = _circle(12, 12, 10.2);
  canvas.outline(badge);
  canvas.clip(badge, () {
    canvas.solid(
      _circle(12, 8.65, 2.7)
        ..moveTo(5.35, 19.6)
        ..cubicTo(6.05, 15.8, 8.4, 13.75, 12, 13.75)
        ..cubicTo(15.6, 13.75, 17.95, 15.8, 18.65, 19.6)
        ..cubicTo(16.95, 20.85, 14.65, 21.5, 12, 21.5)
        ..cubicTo(9.35, 21.5, 7.05, 20.85, 5.35, 19.6)
        ..close(),
    );
  });
}

void _arrowBack(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(19.5, 12), Offset(4.5, 12)],
    [Offset(11, 6.5), Offset(4.5, 12), Offset(11, 17.5)],
  ]),
);

void _arrowForward(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(4.5, 12), Offset(19.5, 12)],
    [Offset(13, 6.5), Offset(19.5, 12), Offset(13, 17.5)],
  ]),
);

void _pushPin(AppIconCanvas canvas) {
  canvas.line(
    _polylines(const [
      [Offset(8, 3.5), Offset(16, 3.5)],
      [
        Offset(9, 3.5),
        Offset(9, 10),
        Offset(6, 14.5),
        Offset(18, 14.5),
        Offset(15, 10),
        Offset(15, 3.5),
      ],
      [Offset(12, 14.5), Offset(12, 21)],
    ]),
  );
}

void _chevronLeft(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(14.5, 6.5), Offset(9.5, 12), Offset(14.5, 17.5)],
  ]),
);

void _chevronRight(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(9.5, 6.5), Offset(14.5, 12), Offset(9.5, 17.5)],
  ]),
);

void _chevronUp(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(6.5, 14.5), Offset(12, 9), Offset(17.5, 14.5)],
  ]),
);

void _chevronDown(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(6.5, 9.5), Offset(12, 15), Offset(17.5, 9.5)],
  ]),
);

void _skipPrevious(AppIconCanvas canvas) {
  canvas.line(
    _polylines(const [
      [Offset(5.5, 5.5), Offset(5.5, 18.5)],
    ]),
  );
  canvas.line(
    _polygon(const [Offset(18.5, 6), Offset(9, 12), Offset(18.5, 18)]),
  );
}

void _skipNext(AppIconCanvas canvas) {
  canvas.line(
    _polylines(const [
      [Offset(18.5, 5.5), Offset(18.5, 18.5)],
    ]),
  );
  canvas.line(
    _polygon(const [Offset(5.5, 6), Offset(15, 12), Offset(5.5, 18)]),
  );
}

void _play(AppIconCanvas canvas) => canvas.line(
  _polygon(const [Offset(8, 5.5), Offset(18.5, 12), Offset(8, 18.5)]),
);

void _close(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(6, 6), Offset(18, 18)],
    [Offset(18, 6), Offset(6, 18)],
  ]),
);

void _add(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(12, 5), Offset(12, 19)],
    [Offset(5, 12), Offset(19, 12)],
  ]),
);

void _addCircle(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 9.2));
  canvas.line(
    _polylines(const [
      [Offset(12, 8.2), Offset(12, 15.8)],
      [Offset(8.2, 12), Offset(15.8, 12)],
    ]),
  );
}

void _remove(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(5, 12), Offset(19, 12)],
  ]),
);

void _removeCircle(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 9.2));
  canvas.line(
    _polylines(const [
      [Offset(8.2, 12), Offset(15.8, 12)],
    ]),
  );
}

void _check(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(4.8, 12.6), Offset(9.6, 17.4), Offset(19.2, 7.8)],
  ]),
);

void _checkCircle(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 9.2));
  canvas.line(
    _polylines(const [
      [Offset(8, 12.4), Offset(10.9, 15.3), Offset(16.2, 9.8)],
    ]),
  );
}

void _search(AppIconCanvas canvas) {
  canvas.line(_circle(10.5, 10.5, 6.5));
  canvas.line(
    _polylines(const [
      [Offset(15.5, 15.5), Offset(20, 20)],
    ]),
  );
}

void _searchOff(AppIconCanvas canvas) {
  canvas.line(_circle(10, 10, 5.5));
  canvas.line(
    _polylines(const [
      [Offset(14, 14), Offset(20, 20)],
      [Offset(7.8, 7.8), Offset(12.2, 12.2)],
      [Offset(12.2, 7.8), Offset(7.8, 12.2)],
    ]),
  );
}

void _refresh(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: 7.8),
        0.63,
        4.87,
      )
      ..addPolygon(const [Offset(17.5, 6.5), Offset(21.3, 10.3)], false)
      ..addPolygon(const [
        Offset(21.3, 5.3),
        Offset(21.3, 10.3),
        Offset(16.3, 10.3),
      ], false),
  );
}

void _restore(AppIconCanvas canvas) {
  canvas.mirror(() => _refresh(canvas));
  canvas.line(
    _polylines(const [
      [Offset(12, 8.6), Offset(12, 12.2), Offset(14.4, 13.6)],
    ]),
  );
}

void _undo(AppIconCanvas canvas) => canvas.line(
  Path()
    ..addPolygon(const [
      Offset(9.5, 5.5),
      Offset(4.5, 10.5),
      Offset(9.5, 15.5),
    ], false)
    ..moveTo(4.5, 10.5)
    ..lineTo(13, 10.5)
    ..arcToPoint(const Offset(13, 21.5), radius: const Radius.circular(5.5)),
);

void _redo(AppIconCanvas canvas) => canvas.mirror(() => _undo(canvas));

void _save(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 20.5, 20.5, 2));
  canvas.line(_roundRect(7.5, 13.5, 16.5, 19.5, 1));
  canvas.solid(_roundRect(7.5, 3.5, 15.5, 8.5, 0.75));
}

void _locate(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 6.5));
  canvas.line(
    _polylines(const [
      [Offset(12, 2.5), Offset(12, 5.5)],
      [Offset(12, 18.5), Offset(12, 21.5)],
      [Offset(2.5, 12), Offset(5.5, 12)],
      [Offset(18.5, 12), Offset(21.5, 12)],
    ]),
  );
  canvas.solid(_circle(12, 12, 2.2));
}

void _tune(AppIconCanvas canvas) {
  canvas.line(
    _polylines(const [
      [Offset(3.5, 7), Offset(20.5, 7)],
      [Offset(3.5, 17), Offset(20.5, 17)],
    ]),
  );
  canvas.solid(_circle(15, 7, 2.6));
  canvas.solid(_circle(9, 17, 2.6));
}

void _settings(AppIconCanvas canvas) {
  canvas.line(
    _polygon([
      for (var tooth = 0; tooth < 8; tooth++)
        for (final (offset, radius) in const [
          (-0.27, 7.0),
          (-0.16, 9.0),
          (0.16, 9.0),
          (0.27, 7.0),
        ])
          _polar(radius, tooth * math.pi / 4 + offset),
    ]),
  );
  canvas.line(_circle(12, 12, 3.1));
}

void _more(AppIconCanvas canvas) {
  canvas.solid(_circle(5.5, 12, 1.6));
  canvas.solid(_circle(12, 12, 1.6));
  canvas.solid(_circle(18.5, 12, 1.6));
}

void _dragHandle(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(5, 9), Offset(19, 9)],
    [Offset(5, 15), Offset(19, 15)],
  ]),
);

void _sort(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(4, 6.5), Offset(14.5, 6.5)],
    [Offset(4, 12), Offset(11.5, 12)],
    [Offset(4, 17.5), Offset(8.5, 17.5)],
  ]),
);

void _filter(AppIconCanvas canvas) => canvas.line(
  _polygon(const [
    Offset(4, 5),
    Offset(20, 5),
    Offset(13.8, 12.6),
    Offset(13.8, 18.7),
    Offset(10.2, 20.2),
    Offset(10.2, 12.6),
  ]),
);

void _filterOff(AppIconCanvas canvas) {
  _filter(canvas);
  canvas.line(
    _polylines(const [
      [Offset(4, 4), Offset(20, 20)],
    ]),
  );
}

void _gridView(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 10.5, 10.5, 1.5));
  canvas.line(_roundRect(13.5, 3.5, 20.5, 10.5, 1.5));
  canvas.line(_roundRect(3.5, 13.5, 10.5, 20.5, 1.5));
  canvas.line(_roundRect(13.5, 13.5, 20.5, 20.5, 1.5));
}

void _listView(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 4, 20.5, 9.5, 1.5));
  canvas.line(_roundRect(3.5, 14.5, 20.5, 20, 1.5));
}

void _grid(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 20.5, 20.5, 1.5));
  canvas.line(
    _polylines(const [
      [Offset(9.5, 3.5), Offset(9.5, 20.5)],
      [Offset(14.5, 3.5), Offset(14.5, 20.5)],
      [Offset(3.5, 9.5), Offset(20.5, 9.5)],
      [Offset(3.5, 14.5), Offset(20.5, 14.5)],
    ]),
  );
}

void _pageMargin(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 20.5, 20.5, 1.5));
  canvas.line(_roundRect(7.5, 7.5, 16.5, 16.5, 0.75));
}

void _share(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(8, 9.5)
      ..lineTo(6.5, 9.5)
      ..arcToPoint(
        const Offset(4, 12),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(4, 18.5)
      ..arcToPoint(
        const Offset(6.5, 21),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(17.5, 21)
      ..arcToPoint(
        const Offset(20, 18.5),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(20, 12)
      ..arcToPoint(
        const Offset(17.5, 9.5),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(16, 9.5),
  );
  canvas.line(
    _polylines(const [
      [Offset(12, 3), Offset(12, 14.5)],
      [Offset(8.5, 6.5), Offset(12, 3), Offset(15.5, 6.5)],
    ]),
  );
}

void _upload(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(4, 14)
      ..lineTo(4, 18.5)
      ..arcToPoint(
        const Offset(6.5, 21),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(17.5, 21)
      ..arcToPoint(
        const Offset(20, 18.5),
        radius: const Radius.circular(2.5),
        clockwise: false,
      )
      ..lineTo(20, 14),
  );
  canvas.line(
    _polylines(const [
      [Offset(12, 15), Offset(12, 3.5)],
      [Offset(8, 7.5), Offset(12, 3.5), Offset(16, 7.5)],
    ]),
  );
}

void _copy(AppIconCanvas canvas) {
  canvas.line(_roundRect(4, 8.5, 16, 20.5, 2));
  canvas.line(
    Path()
      ..moveTo(8.5, 8.5)
      ..lineTo(8.5, 5.5)
      ..arcToPoint(const Offset(10.5, 3.5), radius: const Radius.circular(2))
      ..lineTo(18.5, 3.5)
      ..arcToPoint(const Offset(20.5, 5.5), radius: const Radius.circular(2))
      ..lineTo(20.5, 13.5)
      ..arcToPoint(const Offset(18.5, 15.5), radius: const Radius.circular(2))
      ..lineTo(16, 15.5),
  );
}

void _link(AppIconCanvas canvas) => canvas.rotate(
  const Offset(12, 12),
  -math.pi / 4,
  () => canvas.line(
    Path()
      ..moveTo(10.5, 7)
      ..lineTo(8, 7)
      ..arcToPoint(
        const Offset(8, 17),
        radius: const Radius.circular(5),
        clockwise: false,
      )
      ..lineTo(10.5, 17)
      ..moveTo(13.5, 7)
      ..lineTo(16, 7)
      ..arcToPoint(const Offset(16, 17), radius: const Radius.circular(5))
      ..lineTo(13.5, 17)
      ..moveTo(10.5, 12)
      ..lineTo(13.5, 12),
  ),
);

void _code(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(8.5, 7.5), Offset(3.5, 12), Offset(8.5, 16.5)],
    [Offset(15.5, 7.5), Offset(20.5, 12), Offset(15.5, 16.5)],
  ]),
);

Path _trashPath() => Path()
  ..moveTo(4.5, 6.5)
  ..lineTo(19.5, 6.5)
  ..moveTo(9.5, 6.5)
  ..lineTo(9.5, 4.5)
  ..lineTo(14.5, 4.5)
  ..lineTo(14.5, 6.5)
  ..moveTo(6.5, 6.5)
  ..lineTo(6.5, 18.5)
  ..arcToPoint(
    const Offset(9, 21),
    radius: const Radius.circular(2.5),
    clockwise: false,
  )
  ..lineTo(15, 21)
  ..arcToPoint(
    const Offset(17.5, 18.5),
    radius: const Radius.circular(2.5),
    clockwise: false,
  )
  ..lineTo(17.5, 6.5)
  ..moveTo(10, 10.5)
  ..lineTo(10, 16.5)
  ..moveTo(14, 10.5)
  ..lineTo(14, 16.5);

void _delete(AppIconCanvas canvas) => canvas.line(_trashPath());

void _deleteSweep(AppIconCanvas canvas) {
  final matrix = Matrix4.identity()
    ..translateByDouble(14.5, 12, 0, 1)
    ..scaleByDouble(0.8, 0.8, 0.8, 1)
    ..translateByDouble(-12, -12, 0, 1);
  canvas.line(_trashPath().transform(matrix.storage));
  canvas.line(
    _polylines(const [
      [Offset(2.5, 9), Offset(5.5, 9)],
      [Offset(2.5, 14.5), Offset(5.5, 14.5)],
    ]),
  );
}

void _edit(AppIconCanvas canvas) => canvas.line(
  _polygon(const [
    Offset(15.5, 4.8),
    Offset(19.2, 8.5),
    Offset(9.4, 18.3),
    Offset(4.8, 19.3),
    Offset(5.7, 14.7),
  ]),
);

void _editNote(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 4, 14, 20.5, 2));
  canvas.line(
    _polygon(const [
      Offset(15.5, 18.5),
      Offset(16.5, 14.5),
      Offset(20.5, 6.5),
      Offset(21.5, 7.5),
      Offset(18, 17.5),
    ]),
  );
}

void _highlighter(AppIconCanvas canvas) {
  canvas.rotate(
    const Offset(12, 10.5),
    -math.pi / 4,
    () => canvas.line(_roundRect(4, 8.5, 20, 12.5, 1.5)),
  );
  canvas.line(
    _polylines(const [
      [Offset(4, 20.5), Offset(20, 20.5)],
    ]),
  );
}

void _note(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(5.5, 3.5)
      ..lineTo(18.5, 3.5)
      ..arcToPoint(const Offset(20.5, 5.5), radius: const Radius.circular(2))
      ..lineTo(20.5, 14)
      ..lineTo(14, 20.5)
      ..lineTo(5.5, 20.5)
      ..arcToPoint(const Offset(3.5, 18.5), radius: const Radius.circular(2))
      ..lineTo(3.5, 5.5)
      ..arcToPoint(const Offset(5.5, 3.5), radius: const Radius.circular(2))
      ..close(),
  );
  canvas.line(
    Path()
      ..moveTo(14, 20.5)
      ..lineTo(14, 16)
      ..arcToPoint(const Offset(16, 14), radius: const Radius.circular(2))
      ..lineTo(20.5, 14),
  );
}

void _article(AppIconCanvas canvas) {
  canvas.line(_roundRect(4, 3.5, 20, 20.5, 2));
  canvas.solid(_roundRect(7.5, 8, 16.5, 9.5, 0.75));
  canvas.solid(_roundRect(7.5, 11.75, 16.5, 13.25, 0.75));
  canvas.solid(_roundRect(7.5, 15.5, 13, 17, 0.75));
}

void _noteAdd(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 14, 20.5, 2));
  canvas.line(
    _polylines(const [
      [Offset(18, 13.7), Offset(18, 19.3)],
      [Offset(15.2, 16.5), Offset(20.8, 16.5)],
    ]),
  );
}

void _rateReview(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(21, 15)
      ..arcToPoint(const Offset(19, 17), radius: const Radius.circular(2))
      ..lineTo(7, 17)
      ..lineTo(3, 21)
      ..lineTo(3, 5)
      ..arcToPoint(const Offset(5, 3), radius: const Radius.circular(2))
      ..lineTo(19, 3)
      ..arcToPoint(const Offset(21, 5), radius: const Radius.circular(2))
      ..close(),
  );
  canvas.solid(_roundRect(7, 7.5, 17, 9, 0.75));
  canvas.solid(_roundRect(7, 11.5, 13.5, 13, 0.75));
}

Path _bookmarkPath() => _polygon(const [
  Offset(6.5, 3.5),
  Offset(17.5, 3.5),
  Offset(17.5, 20.5),
  Offset(12, 16.5),
  Offset(6.5, 20.5),
]);

void _bookmark(AppIconCanvas canvas) => canvas.line(_bookmarkPath());

void _bookmarkAdd(AppIconCanvas canvas) {
  canvas.line(_bookmarkPath());
  canvas.line(
    _polylines(const [
      [Offset(12, 8.3), Offset(12, 13.7)],
      [Offset(9.3, 11), Offset(14.7, 11)],
    ]),
  );
}

void _star(AppIconCanvas canvas) => canvas.outline(
  _polygon([
    for (var point = 0; point < 10; point++)
      _polar(point.isEven ? 9.4 : 4.6, -math.pi / 2 + point * math.pi / 5),
  ]),
);

void _radioChecked(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 8.6));
  canvas.solid(_circle(12, 12, 4.4));
}

void _radioUnchecked(AppIconCanvas canvas) => canvas.line(_circle(12, 12, 8.6));

void _checklist(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(3.5, 7.2), Offset(5.3, 9), Offset(8.6, 5.5)],
    [Offset(11.5, 7.2), Offset(20.5, 7.2)],
    [Offset(3.5, 16.8), Offset(5.3, 18.6), Offset(8.6, 15.1)],
    [Offset(11.5, 16.8), Offset(20.5, 16.8)],
  ]),
);

void _lock(AppIconCanvas canvas) {
  canvas.line(_roundRect(5, 10.5, 19, 20.5, 2));
  canvas.line(
    Path()
      ..moveTo(8.5, 10.5)
      ..lineTo(8.5, 7.5)
      ..arcToPoint(const Offset(15.5, 7.5), radius: const Radius.circular(3.5))
      ..lineTo(15.5, 10.5),
  );
  canvas.solid(_circle(12, 15.5, 1.4));
}

void _preview(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(2.5, 12)
      ..cubicTo(5, 7.5, 8.3, 5.5, 12, 5.5)
      ..cubicTo(15.7, 5.5, 19, 7.5, 21.5, 12)
      ..cubicTo(19, 16.5, 15.7, 18.5, 12, 18.5)
      ..cubicTo(8.3, 18.5, 5, 16.5, 2.5, 12)
      ..close(),
  );
  canvas.line(_circle(12, 12, 3));
}

void _touchApp(AppIconCanvas canvas) => canvas.line(
  _polygon(const [
    Offset(7, 4.5),
    Offset(18, 12),
    Offset(13, 13.3),
    Offset(15.5, 19),
    Offset(13.4, 20),
    Offset(11, 14.2),
    Offset(7, 17.3),
  ]),
);

void _autoFix(AppIconCanvas canvas) {
  canvas.line(
    _polylines(const [
      [Offset(4.5, 19.5), Offset(14, 10)],
    ]),
  );
  canvas.line(
    _polylines(const [
      [Offset(18, 3.5), Offset(18, 8.5)],
      [Offset(15.5, 6), Offset(20.5, 6)],
    ]),
  );
  canvas.solid(_circle(19.5, 13.5, 1.2));
}

void _palette(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(12, 3)
      ..cubicTo(7, 3, 3, 7, 3, 12)
      ..cubicTo(3, 17, 7, 21, 12, 21)
      ..cubicTo(13, 21, 13.6, 20.2, 13.1, 19.2)
      ..cubicTo(12.6, 18.1, 13.2, 16.8, 14.6, 16.8)
      ..lineTo(16.2, 16.8)
      ..cubicTo(19, 16.8, 21, 14.8, 21, 12)
      ..cubicTo(21, 7, 17, 3, 12, 3)
      ..close(),
  );
  for (final (centerX, centerY) in const [
    (7.5, 10.5),
    (11.5, 7.0),
    (16.0, 9.5),
  ]) {
    canvas.solid(_circle(centerX, centerY, 1.3));
  }
}

void _formatPaint(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 3.5, 17.5, 9.5, 1.5));
  canvas.line(
    _polylines(const [
      [Offset(17.5, 6.5), Offset(20.5, 6.5)],
      [Offset(10.5, 9.5), Offset(10.5, 12.5)],
    ]),
  );
  canvas.line(_roundRect(8, 12.5, 13, 20.5, 1.5));
}

void _formatUnderlined(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(7, 4)
      ..lineTo(7, 11)
      ..arcToPoint(
        const Offset(17, 11),
        radius: const Radius.circular(5),
        clockwise: false,
      )
      ..lineTo(17, 4),
  );
  canvas.line(
    _polylines(const [
      [Offset(5, 20.5), Offset(19, 20.5)],
    ]),
  );
}

void _textFields(AppIconCanvas canvas) => canvas.line(
  _polylines(const [
    [Offset(5, 5.5), Offset(19, 5.5)],
    [Offset(12, 5.5), Offset(12, 19.5)],
    [Offset(8.5, 19.5), Offset(15.5, 19.5)],
  ]),
);

void _listBulleted(AppIconCanvas canvas) {
  for (final centerY in const [7.0, 12.0, 17.0]) {
    canvas.solid(_circle(4.5, centerY, 1.2));
    canvas.line(
      _polylines([
        [Offset(9, centerY), Offset(20.5, centerY)],
      ]),
    );
  }
}

void _headphones(AppIconCanvas canvas) {
  canvas.line(
    Path()
      ..moveTo(4.5, 14.5)
      ..lineTo(4.5, 12)
      ..arcToPoint(const Offset(19.5, 12), radius: const Radius.circular(7.5))
      ..lineTo(19.5, 14.5),
  );
  canvas.line(_roundRect(3.5, 13.5, 8, 20.5, 2));
  canvas.line(_roundRect(16, 13.5, 20.5, 20.5, 2));
}

void _image(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 4.5, 20.5, 19.5, 2));
  canvas.solid(_circle(8.5, 9.5, 1.6));
  canvas.line(
    _polylines(const [
      [
        Offset(4.5, 17),
        Offset(9.5, 12),
        Offset(13, 15.5),
        Offset(15.5, 13),
        Offset(19.5, 17),
      ],
    ]),
  );
}

void _addImage(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 8, 16, 20.5, 2));
  canvas.solid(_circle(8, 13.5, 1.4));
  canvas.line(
    _polylines(const [
      [Offset(5.5, 18), Offset(9.5, 14.5), Offset(13, 17.5)],
    ]),
  );
  canvas.line(
    _polylines(const [
      [Offset(18.5, 2), Offset(18.5, 7)],
      [Offset(16, 4.5), Offset(21, 4.5)],
    ]),
  );
}

void _brokenImage(AppIconCanvas canvas) {
  canvas.line(_roundRect(3.5, 4.5, 20.5, 19.5, 2));
  canvas.line(
    _polylines(const [
      [Offset(13, 4.5), Offset(10.5, 10), Offset(14, 13.5), Offset(11.5, 19.5)],
    ]),
  );
}

Path _folderPath() => Path()
  ..moveTo(3.5, 18.5)
  ..lineTo(3.5, 6.5)
  ..arcToPoint(const Offset(5.5, 4.5), radius: const Radius.circular(2))
  ..lineTo(9.4, 4.5)
  ..lineTo(11.4, 7)
  ..lineTo(18.5, 7)
  ..arcToPoint(const Offset(20.5, 9), radius: const Radius.circular(2))
  ..lineTo(20.5, 18.5)
  ..arcToPoint(const Offset(18.5, 20.5), radius: const Radius.circular(2))
  ..lineTo(5.5, 20.5)
  ..arcToPoint(const Offset(3.5, 18.5), radius: const Radius.circular(2))
  ..close();

void _folder(AppIconCanvas canvas) => canvas.line(_folderPath());

void _folderOff(AppIconCanvas canvas) {
  canvas.line(_folderPath());
  canvas.line(
    _polylines(const [
      [Offset(4, 4), Offset(20, 20)],
    ]),
  );
}

void _folderAdd(AppIconCanvas canvas) {
  canvas.line(_folderPath());
  canvas.line(
    _polylines(const [
      [Offset(12, 10.5), Offset(12, 16.5)],
      [Offset(9, 13.5), Offset(15, 13.5)],
    ]),
  );
}

void _warning(AppIconCanvas canvas) {
  canvas.line(
    _polygon(const [Offset(12, 3.6), Offset(21.5, 20), Offset(2.5, 20)]),
  );
  canvas.line(
    _polylines(const [
      [Offset(12, 9.5), Offset(12, 14.2)],
    ]),
  );
  canvas.solid(_circle(12, 17.2, 1.2));
}

void _error(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 9.2));
  canvas.line(
    _polylines(const [
      [Offset(12, 7.3), Offset(12, 13)],
    ]),
  );
  canvas.solid(_circle(12, 16.7, 1.2));
}

void _info(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 9.2));
  canvas.line(
    _polylines(const [
      [Offset(12, 11), Offset(12, 16.8)],
    ]),
  );
  canvas.solid(_circle(12, 7.8, 1.2));
}

void _lightMode(AppIconCanvas canvas) {
  canvas.line(_circle(12, 12, 3.8));
  for (var ray = 0; ray < 8; ray++) {
    final angle = ray * math.pi / 4;
    canvas.line(
      _polylines([
        [_polar(6.6, angle), _polar(9, angle)],
      ]),
    );
  }
}

void _darkMode(AppIconCanvas canvas) => canvas.line(
  Path()
    ..moveTo(21, 12.8)
    ..arcToPoint(
      const Offset(11.2, 3),
      radius: const Radius.circular(9),
      largeArc: true,
    )
    ..arcToPoint(
      const Offset(21, 12.8),
      radius: const Radius.circular(7),
      clockwise: false,
    )
    ..close(),
);

Path _openBook() => Path()
  ..moveTo(12, 6.6)
  ..cubicTo(10.3, 5.1, 7.2, 4.2, 3.5, 4.9)
  ..lineTo(3.5, 18.7)
  ..cubicTo(7.2, 18, 10.3, 18.9, 12, 20.4)
  ..cubicTo(13.7, 18.9, 16.8, 18, 20.5, 18.7)
  ..lineTo(20.5, 4.9)
  ..cubicTo(16.8, 4.2, 13.7, 5.1, 12, 6.6)
  ..close();

void _menuBook(AppIconCanvas canvas) {
  canvas.line(_openBook());
  canvas.line(
    _polylines(const [
      [Offset(12, 6.6), Offset(12, 20.4)],
    ]),
  );
}

void _autoStories(AppIconCanvas canvas) {
  canvas.line(_openBook());
  canvas.line(
    _polylines(const [
      [Offset(12, 6.6), Offset(12, 20.4)],
    ]),
  );
  canvas.solid(_roundRect(6, 9.5, 9.5, 11, 0.75));
  canvas.solid(_roundRect(6, 13, 9.5, 14.5, 0.75));
  canvas.solid(_roundRect(14.5, 9.5, 18, 11, 0.75));
  canvas.solid(_roundRect(14.5, 13, 18, 14.5, 0.75));
}

/// 与现有图标相同线宽的发现指南针。
void _discover(AppIconCanvas context) {
  context.outline(Path()..addOval(const Rect.fromLTWH(3, 3, 18, 18)));
  final needle = Path()
    ..moveTo(16, 8)
    ..lineTo(14, 14)
    ..lineTo(8, 16)
    ..lineTo(10, 10)
    ..close();
  if (context.filled) {
    context.solid(needle);
  } else {
    context.line(needle);
  }
}
