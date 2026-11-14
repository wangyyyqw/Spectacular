import 'package:flutter/material.dart';

/// 电池填充随实际电量变化，未知电量用短横表示。
class ReaderBatteryIcon extends StatelessWidget {
  const ReaderBatteryIcon({
    super.key,
    required this.level,
    required this.color,
  });

  final int? level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = level?.clamp(0, 100);
    return Semantics(
      label: '电量',
      value: value == null ? '未知' : '$value%',
      image: true,
      child: CustomPaint(
        size: const Size(22, 12),
        painter: _BatteryPainter(value, color),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter(this.level, this.color);

  final int? level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(.5, .5, 19, 11),
        const Radius.circular(2),
      ),
      paint,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20.5, 4, 1.5, 4),
        const Radius.circular(.75),
      ),
      paint,
    );
    if (level == null) {
      canvas.drawRect(const Rect.fromLTWH(7, 5.5, 6, 1), paint);
    } else if (level! > 0) {
      canvas.drawRect(Rect.fromLTWH(2.5, 2.5, 15 * level! / 100, 7), paint);
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}
