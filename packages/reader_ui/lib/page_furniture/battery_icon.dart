import 'package:flutter/material.dart';

/// 电池填充随实际电量变化，未知电量用短横表示。
class ReaderBatteryIcon extends StatelessWidget {
  const ReaderBatteryIcon({
    super.key,
    required this.level,
    required this.color,
    this.charging,
  });

  final int? level;
  final Color color;
  final bool? charging;

  @override
  Widget build(BuildContext context) {
    final value = level?.clamp(0, 100);
    final status = switch (charging) {
      true => value == 100 ? '已充满，已接电' : '充电中',
      false => '未充电',
      null => '充电状态未知',
    };
    return Semantics(
      label: '电量',
      value: '${value == null ? '未知' : '$value%'}，$status',
      image: true,
      child: CustomPaint(
        // 保留闪电位置，接通或断开电源时不挤动相邻信息。
        size: const Size(32, 12),
        painter: _BatteryPainter(value, color, charging == true),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter(this.level, this.color, this.charging);

  final int? level;
  final Color color;
  final bool charging;

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
    if (charging) _paintCharging(canvas, paint);
  }

  void _paintCharging(Canvas canvas, Paint paint) {
    final bolt = Path()
      ..moveTo(28, 1)
      ..lineTo(25, 6.5)
      ..lineTo(28, 6.5)
      ..lineTo(26.5, 11)
      ..lineTo(32, 4.5)
      ..lineTo(29, 4.5)
      ..lineTo(31, 1)
      ..close();
    canvas.drawPath(bolt, paint);
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.color != color ||
      oldDelegate.charging != charging;
}
