import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_glyph.dart' show AppIconCanvas;

/// 编辑工作台专用字形，共用应用的 24 格坐标、圆角与 1.7 线宽。
enum EditorGlyph {
  arrowBack(_arrowBack),
  folder(_folder),
  search(_search),
  checklist(_checklist),
  undo(_undo),
  redo(_redo),
  save(_save),
  more(_more),
  close(_close),
  chevronDown(_chevronDown),
  chevronUp(_chevronUp),
  chevronLeft(_chevronLeft),
  chevronRight(_chevronRight),
  preview(_preview),
  locate(_locate),
  tune(_tune),
  code(_code),
  add(_add),
  removeCircle(_removeCircle),
  check(_check),
  filter(_filter),
  editNote(_editNote),
  addImage(_addImage),
  edit(_edit),
  formatPaint(_formatPaint),
  styleLibrary(_styleLibrary),
  image(_image),
  textFields(_textFields),
  article(_article),
  convert(_convert),
  structure(_structure),
  annotations(_annotations),
  export(_export),
  history(_history),
  metadata(_metadata),
  toc(_toc),
  split(_split),
  merge(_merge),
  wrap(_wrap),
  gotoLine(_gotoLine),
  format(_format),
  replace(_replace);

  const EditorGlyph(this.draw);

  /// 只描述几何，颜色与禁用态由按钮的图标主题提供。
  final void Function(AppIconCanvas canvas) draw;
}

class EditorIcon extends StatelessWidget {
  const EditorIcon(this.glyph, {super.key, this.size, this.color});

  final EditorGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 24;
    final foreground = color ?? theme.color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: dimension,
      child: Center(
        child: CustomPaint(
          size: Size.square(dimension),
          painter: _EditorIconPainter(
            glyph,
            foreground.withValues(alpha: foreground.a * (theme.opacity ?? 1)),
          ),
        ),
      ),
    );
  }
}

class _EditorIconPainter extends CustomPainter {
  const _EditorIconPainter(this.glyph, this.color);
  final EditorGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    glyph.draw(
      AppIconCanvas(canvas, color: color, filled: false, cutoutColor: color),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EditorIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}

Path _circle(double x, double y, double radius) =>
    Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));

void _styleLibrary(AppIconCanvas c) {
  c.outline(_rect(5, 3, 16, 16));
  c.line(
    Path()
      ..moveTo(2, 7)
      ..lineTo(2, 22)
      ..lineTo(17, 22)
      ..moveTo(9, 14)
      ..lineTo(12, 7)
      ..lineTo(15, 14)
      ..moveTo(10, 11.5)
      ..lineTo(14, 11.5)
      ..moveTo(9, 16.5)
      ..lineTo(17, 16.5),
  );
}

Path _rect(double x, double y, double width, double height) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height),
      const Radius.circular(1.4),
    ),
  );

void _arrowBack(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(10, 5)
    ..lineTo(3, 12)
    ..lineTo(10, 19)
    ..moveTo(3, 12)
    ..lineTo(21, 12),
);

void _folder(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(3, 18)
      ..lineTo(3, 5.5)
      ..quadraticBezierTo(3, 4, 4.5, 4)
      ..lineTo(9, 4)
      ..lineTo(11.5, 7)
      ..lineTo(19, 7)
      ..quadraticBezierTo(20.5, 7, 20.5, 8.5)
      ..lineTo(20.5, 10),
  );
  c.outline(
    Path()
      ..moveTo(3, 19.5)
      ..lineTo(6, 11)
      ..lineTo(22, 11)
      ..lineTo(19, 19.5)
      ..close(),
  );
}

void _search(AppIconCanvas c) {
  c.outline(_circle(10.25, 10.25, 6.75));
  c.line(
    Path()
      ..moveTo(15.25, 15.25)
      ..lineTo(21, 21),
  );
}

void _checklist(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(3, 6)
    ..lineTo(5, 8)
    ..lineTo(8.5, 4)
    ..moveTo(12, 6)
    ..lineTo(21, 6)
    ..moveTo(3, 14)
    ..lineTo(5, 16)
    ..lineTo(8.5, 12)
    ..moveTo(12, 14)
    ..lineTo(21, 14)
    ..moveTo(12, 20)
    ..lineTo(18, 20),
);

void _undo(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(8, 4)
    ..lineTo(3, 9)
    ..lineTo(8, 14)
    ..moveTo(3, 9)
    ..lineTo(15, 9)
    ..cubicTo(23, 9, 23, 20, 15, 20)
    ..lineTo(11, 20),
);

void _redo(AppIconCanvas c) => c.mirror(() => _undo(c));

void _save(AppIconCanvas c) {
  c.outline(
    Path()
      ..moveTo(4, 3)
      ..lineTo(16.5, 3)
      ..lineTo(21, 7.5)
      ..lineTo(21, 21)
      ..lineTo(3, 21)
      ..lineTo(3, 4)
      ..quadraticBezierTo(3, 3, 4, 3)
      ..close(),
  );
  c.line(
    Path()
      ..moveTo(7, 3)
      ..lineTo(7, 9)
      ..lineTo(16, 9)
      ..lineTo(16, 3)
      ..moveTo(7, 21)
      ..lineTo(7, 14)
      ..lineTo(17, 14)
      ..lineTo(17, 21),
  );
  c.solid(_rect(12.5, 4.5, 1.5, 3));
}

void _more(AppIconCanvas c) {
  for (final x in [5.0, 12.0, 19.0]) {
    c.solid(_circle(x, 12, 1.4));
  }
}

void _close(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(6, 6)
    ..lineTo(18, 18)
    ..moveTo(18, 6)
    ..lineTo(6, 18),
);

void _chevronDown(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(6, 9)
    ..lineTo(12, 15)
    ..lineTo(18, 9),
);

void _chevronUp(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(6, 15)
    ..lineTo(12, 9)
    ..lineTo(18, 15),
);

void _chevronLeft(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(15, 6)
    ..lineTo(9, 12)
    ..lineTo(15, 18),
);

void _chevronRight(AppIconCanvas c) => c.mirror(() => _chevronLeft(c));

void _preview(AppIconCanvas c) {
  c.outline(_rect(6, 2, 12, 20));
  c.line(
    Path()
      ..moveTo(10, 5)
      ..lineTo(14, 5)
      ..moveTo(10, 19)
      ..lineTo(14, 19),
  );
}

void _locate(AppIconCanvas c) {
  c.outline(_circle(12, 12, 6.5));
  c.solid(_circle(12, 12, 1.8));
  c.line(
    Path()
      ..moveTo(12, 2)
      ..lineTo(12, 7)
      ..moveTo(12, 17)
      ..lineTo(12, 22)
      ..moveTo(2, 12)
      ..lineTo(7, 12)
      ..moveTo(17, 12)
      ..lineTo(22, 12),
  );
}

void _tune(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(3, 7)
      ..lineTo(8, 7)
      ..moveTo(12, 7)
      ..lineTo(21, 7)
      ..moveTo(3, 17)
      ..lineTo(12, 17)
      ..moveTo(16, 17)
      ..lineTo(21, 17),
  );
  c.outline(_rect(8, 4, 4, 6));
  c.outline(_rect(12, 14, 4, 6));
}

void _code(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(7, 6)
    ..lineTo(2, 12)
    ..lineTo(7, 18)
    ..moveTo(17, 6)
    ..lineTo(22, 12)
    ..lineTo(17, 18)
    ..moveTo(14, 4)
    ..lineTo(10, 20),
);

void _add(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(12, 4)
    ..lineTo(12, 20)
    ..moveTo(4, 12)
    ..lineTo(20, 12),
);

void _removeCircle(AppIconCanvas c) {
  c.outline(_circle(12, 12, 9));
  c.line(
    Path()
      ..moveTo(7, 12)
      ..lineTo(17, 12),
  );
}

void _check(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(4, 12)
    ..lineTo(9, 17)
    ..lineTo(20, 6),
);

void _filter(AppIconCanvas c) {
  c.outline(
    Path()
      ..moveTo(3, 4)
      ..lineTo(21, 4)
      ..lineTo(14, 12)
      ..lineTo(14, 19)
      ..lineTo(10, 21)
      ..lineTo(10, 12)
      ..close(),
  );
}

void _editNote(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(11, 3)
      ..lineTo(4, 3)
      ..lineTo(4, 21)
      ..lineTo(20, 21)
      ..lineTo(20, 15)
      ..moveTo(7, 8)
      ..lineTo(10, 8)
      ..moveTo(7, 12)
      ..lineTo(9, 12),
  );
  c.outline(
    Path()
      ..moveTo(11, 16)
      ..lineTo(12, 12)
      ..lineTo(20, 4)
      ..lineTo(23, 7)
      ..lineTo(15, 15)
      ..close(),
  );
  c.line(
    Path()
      ..moveTo(18, 6)
      ..lineTo(21, 9),
  );
}

void _addImage(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(14, 3)
      ..lineTo(3, 3)
      ..lineTo(3, 21)
      ..lineTo(21, 21)
      ..lineTo(21, 12)
      ..moveTo(3, 17)
      ..lineTo(9, 11)
      ..lineTo(14, 16)
      ..lineTo(17, 13)
      ..lineTo(21, 17)
      ..moveTo(19, 2)
      ..lineTo(19, 8)
      ..moveTo(16, 5)
      ..lineTo(22, 5),
  );
  c.solid(_circle(8, 7, 1.25));
}

void _edit(AppIconCanvas c) {
  c.outline(
    Path()
      ..moveTo(3, 21)
      ..lineTo(4.5, 15)
      ..lineTo(17, 2.5)
      ..lineTo(21.5, 7)
      ..lineTo(9, 19.5)
      ..close(),
  );
  c.line(
    Path()
      ..moveTo(14, 5.5)
      ..lineTo(18.5, 10)
      ..moveTo(4.5, 15)
      ..lineTo(9, 19.5),
  );
}

void _formatPaint(AppIconCanvas c) {
  c.outline(_rect(3, 3, 15, 6));
  c.line(
    Path()
      ..moveTo(18, 6)
      ..lineTo(21, 6)
      ..lineTo(21, 12)
      ..lineTo(11, 12)
      ..lineTo(11, 15),
  );
  c.outline(_rect(9, 15, 4, 7));
}

void _image(AppIconCanvas c) {
  c.outline(_rect(2.5, 3, 19, 18));
  c.solid(_circle(8, 8, 1.5));
  c.line(
    Path()
      ..moveTo(3, 18)
      ..lineTo(9, 12)
      ..lineTo(13, 16)
      ..lineTo(17, 11)
      ..lineTo(21, 16),
  );
}

void _textFields(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(2, 7)
    ..lineTo(2, 4)
    ..lineTo(16, 4)
    ..lineTo(16, 7)
    ..moveTo(9, 4)
    ..lineTo(9, 20)
    ..moveTo(5, 20)
    ..lineTo(13, 20)
    ..moveTo(16, 12)
    ..lineTo(22, 12)
    ..moveTo(19, 9)
    ..lineTo(19, 20)
    ..lineTo(22, 20),
);

void _article(AppIconCanvas c) {
  c.outline(
    Path()
      ..moveTo(4, 2.5)
      ..lineTo(14, 2.5)
      ..lineTo(20, 8.5)
      ..lineTo(20, 21.5)
      ..lineTo(4, 21.5)
      ..close(),
  );
  c.line(
    Path()
      ..moveTo(14, 2.5)
      ..lineTo(14, 8.5)
      ..lineTo(20, 8.5)
      ..moveTo(8, 12)
      ..lineTo(16, 12)
      ..moveTo(8, 16)
      ..lineTo(16, 16),
  );
}

void _convert(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(3, 10)
    ..lineTo(3, 6)
    ..lineTo(20, 6)
    ..moveTo(16, 2)
    ..lineTo(20, 6)
    ..lineTo(16, 10)
    ..moveTo(21, 14)
    ..lineTo(21, 18)
    ..lineTo(4, 18)
    ..moveTo(8, 14)
    ..lineTo(4, 18)
    ..lineTo(8, 22),
);

void _structure(AppIconCanvas c) {
  c.outline(_rect(8, 2, 8, 5));
  c.outline(_rect(2, 17, 7, 5));
  c.outline(_rect(15, 17, 7, 5));
  c.line(
    Path()
      ..moveTo(12, 7)
      ..lineTo(12, 12)
      ..moveTo(5.5, 17)
      ..lineTo(5.5, 12)
      ..lineTo(18.5, 12)
      ..lineTo(18.5, 17),
  );
}

void _annotations(AppIconCanvas c) {
  c.outline(
    Path()
      ..moveTo(5, 3)
      ..lineTo(19, 3)
      ..quadraticBezierTo(21, 3, 21, 5)
      ..lineTo(21, 15)
      ..quadraticBezierTo(21, 17, 19, 17)
      ..lineTo(10, 17)
      ..lineTo(5, 21)
      ..lineTo(5, 17)
      ..quadraticBezierTo(3, 17, 3, 15)
      ..lineTo(3, 5)
      ..quadraticBezierTo(3, 3, 5, 3)
      ..close(),
  );
  c.line(
    Path()
      ..moveTo(7, 8)
      ..lineTo(17, 8)
      ..moveTo(7, 12)
      ..lineTo(14, 12),
  );
}

void _export(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(3, 14)
    ..lineTo(3, 21)
    ..lineTo(21, 21)
    ..lineTo(21, 14)
    ..moveTo(12, 16)
    ..lineTo(12, 3)
    ..moveTo(7, 8)
    ..lineTo(12, 3)
    ..lineTo(17, 8),
);

void _history(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(3.5, 8)
      ..cubicTo(6, 1, 16, 0, 20, 7)
      ..cubicTo(25, 16, 14, 26, 6, 19)
      ..moveTo(3, 3)
      ..lineTo(3, 8.5)
      ..lineTo(8.5, 8.5)
      ..moveTo(12, 7)
      ..lineTo(12, 12)
      ..lineTo(16, 14),
  );
}

void _metadata(AppIconCanvas c) {
  c.outline(_rect(3, 3, 18, 18));
  c.solid(_circle(7, 7, 1));
  c.solid(_circle(7, 12, 1));
  c.solid(_circle(7, 17, 1));
  c.line(
    Path()
      ..moveTo(11, 7)
      ..lineTo(17, 7)
      ..moveTo(11, 12)
      ..lineTo(17, 12)
      ..moveTo(11, 17)
      ..lineTo(15, 17),
  );
}

void _toc(AppIconCanvas c) {
  c.line(
    Path()
      ..moveTo(3, 4)
      ..lineTo(3, 19)
      ..lineTo(7, 19)
      ..moveTo(3, 11)
      ..lineTo(7, 11)
      ..moveTo(11, 11)
      ..lineTo(21, 11)
      ..moveTo(11, 19)
      ..lineTo(21, 19)
      ..moveTo(7, 4)
      ..lineTo(21, 4),
  );
}

void _split(AppIconCanvas c) {
  c.outline(_circle(6, 18, 3));
  c.outline(_circle(18, 18, 3));
  c.line(
    Path()
      ..moveTo(8, 15.5)
      ..lineTo(20, 3)
      ..moveTo(16, 15.5)
      ..lineTo(4, 3),
  );
}

void _merge(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(4, 21)
    ..lineTo(4, 17)
    ..cubicTo(4, 12, 12, 13, 12, 8)
    ..lineTo(12, 3)
    ..moveTo(20, 21)
    ..lineTo(20, 17)
    ..cubicTo(20, 12, 12, 13, 12, 8)
    ..moveTo(7, 8)
    ..lineTo(12, 3)
    ..lineTo(17, 8),
);

void _wrap(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(3, 5)
    ..lineTo(21, 5)
    ..moveTo(3, 10)
    ..lineTo(17, 10)
    ..cubicTo(23, 10, 23, 17, 17, 17)
    ..lineTo(12, 17)
    ..moveTo(15, 14)
    ..lineTo(12, 17)
    ..lineTo(15, 20)
    ..moveTo(3, 17)
    ..lineTo(7, 17),
);

void _gotoLine(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(11, 4)
    ..lineTo(21, 4)
    ..moveTo(11, 12)
    ..lineTo(21, 12)
    ..moveTo(11, 20)
    ..lineTo(21, 20)
    ..moveTo(2, 12)
    ..lineTo(7, 12)
    ..moveTo(4, 9)
    ..lineTo(7, 12)
    ..lineTo(4, 15),
);

void _format(AppIconCanvas c) => c.line(
  Path()
    ..moveTo(3, 4)
    ..lineTo(21, 4)
    ..moveTo(9, 9)
    ..lineTo(21, 9)
    ..moveTo(9, 14)
    ..lineTo(17, 14)
    ..moveTo(3, 20)
    ..lineTo(21, 20)
    ..moveTo(2, 8)
    ..lineTo(5, 11.5)
    ..lineTo(2, 15),
);

void _replace(AppIconCanvas c) {
  c.outline(_circle(7, 7, 4));
  c.line(
    Path()
      ..moveTo(10, 10)
      ..lineTo(13, 13)
      ..moveTo(4, 16)
      ..lineTo(4, 20)
      ..lineTo(19, 20)
      ..moveTo(15, 16)
      ..lineTo(19, 20)
      ..lineTo(15, 23),
  );
}
