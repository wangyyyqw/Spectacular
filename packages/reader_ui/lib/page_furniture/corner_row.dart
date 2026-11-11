import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/reader_theme.dart';
import 'corner_info.dart';

/// 四角显示所需的当前页数据。
class ReaderCornerData {
  const ReaderCornerData({
    this.bookTitle = '',
    this.chapterTitle = '',
    this.pageLabel = '',
    this.progress = 0,
  });

  final String bookTitle;
  final String chapterTitle;
  final String pageLabel;
  final double progress;
}

/// 页眉或页脚的一行；仅在显示时间、电量时启动分钟刷新。
class ReaderCornerRow extends StatefulWidget {
  const ReaderCornerRow({
    super.key,
    required this.left,
    required this.right,
    required this.data,
    this.theme,
    this.inkMode = false,
    this.now,
  });

  final ReaderCornerContent left;
  final ReaderCornerContent right;
  final ReaderCornerData data;
  final ReaderTheme? theme;
  final bool inkMode;
  final DateTime? now;

  @override
  State<ReaderCornerRow> createState() => _ReaderCornerRowState();
}

class _ReaderCornerRowState extends State<ReaderCornerRow> {
  static const _channel = MethodChannel('com.spectacular.reader_mobile/reader');
  Timer? _timer;
  late DateTime _now = widget.now ?? DateTime.now();
  int? _battery;

  bool get _needsBattery =>
      widget.left.needsBattery || widget.right.needsBattery;
  bool get _needsClock => widget.left.needsClock || widget.right.needsClock;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(ReaderCornerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.left != widget.left ||
        oldWidget.right != widget.right ||
        oldWidget.now != widget.now) {
      _refresh();
    }
  }

  void _refresh() {
    _timer?.cancel();
    _now = widget.now ?? DateTime.now();
    if (_needsBattery) unawaited(_readBattery());
    if (widget.now != null || (!_needsBattery && !_needsClock)) return;
    _timer = Timer(
      Duration(milliseconds: 60000 - _now.second * 1000 - _now.millisecond),
      () {
        if (!mounted) return;
        setState(_refresh);
      },
    );
  }

  Future<void> _readBattery() async {
    try {
      final value = await _channel.invokeMethod<int>('getBatteryLevel');
      if (mounted &&
          value != _battery &&
          value != null &&
          value >= 0 &&
          value <= 100) {
        setState(() => _battery = value);
      }
    } on MissingPluginException {
      // 桌面或测试环境不提供电量，显示不可用状态。
    } on PlatformException {
      // 系统暂时无法读取时保留最后一次有效电量。
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _text(ReaderCornerContent content) {
    final clock =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final battery = _battery == null ? '电量 --' : '$_battery%';
    return switch (content) {
      ReaderCornerContent.none => '',
      ReaderCornerContent.bookTitle => widget.data.bookTitle,
      ReaderCornerContent.chapterTitle => widget.data.chapterTitle,
      ReaderCornerContent.chapterPage => widget.data.pageLabel,
      ReaderCornerContent.progress =>
        '${(widget.data.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(2)}%',
      ReaderCornerContent.clock => clock,
      ReaderCornerContent.battery => battery,
      ReaderCornerContent.clockAndBattery =>
        _battery == null ? clock : '$clock · $battery',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.inkMode
        ? widget.theme?.text ?? const Color(0xFF757575)
        : widget.theme?.sub ?? const Color(0xFF9E9E9E);
    return Row(
      children: [
        if (widget.left != ReaderCornerContent.none)
          Expanded(child: _label(widget.left, color, TextAlign.left)),
        if (widget.left != ReaderCornerContent.none &&
            widget.right != ReaderCornerContent.none)
          const SizedBox(width: 12),
        if (widget.right != ReaderCornerContent.none)
          Expanded(child: _label(widget.right, color, TextAlign.right)),
      ],
    );
  }

  Widget _label(ReaderCornerContent content, Color color, TextAlign align) =>
      Text(
        _text(content),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          letterSpacing: .26,
          color: color,
          decoration: TextDecoration.none,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}
