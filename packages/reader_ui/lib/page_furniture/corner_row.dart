import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/reader_theme.dart';
import 'battery_icon.dart';
import 'corner_info.dart';

typedef ReaderBatteryStatus = ({int? level, bool? charging});

/// 电量或充电状态变化时让翻页快照失效。
ValueListenable<ReaderBatteryStatus> get readerBatteryStatus =>
    _ReaderCornerRowState._battery;

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
  static final _battery = _BatteryStatus();
  Timer? _timer;
  late DateTime _now = widget.now ?? DateTime.now();
  bool _listeningBattery = false;

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
    _syncBattery();
    if (widget.now != null || (!_needsBattery && !_needsClock)) return;
    _timer = Timer(
      Duration(milliseconds: 60000 - _now.second * 1000 - _now.millisecond),
      () {
        if (!mounted) return;
        setState(_refresh);
      },
    );
  }

  void _syncBattery() {
    if (_needsBattery && !_listeningBattery) {
      _battery.addListener(_batteryChanged);
      _listeningBattery = true;
    } else if (!_needsBattery && _listeningBattery) {
      _battery.removeListener(_batteryChanged);
      _listeningBattery = false;
    }
    if (_needsBattery) unawaited(_battery.refresh());
  }

  void _batteryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_listeningBattery) _battery.removeListener(_batteryChanged);
    super.dispose();
  }

  String get _clock =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  String _text(ReaderCornerContent content) {
    return switch (content) {
      ReaderCornerContent.none => '',
      ReaderCornerContent.bookTitle => widget.data.bookTitle,
      ReaderCornerContent.chapterTitle => widget.data.chapterTitle,
      ReaderCornerContent.chapterPage => widget.data.pageLabel,
      ReaderCornerContent.progress =>
        '${(widget.data.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(2)}%',
      ReaderCornerContent.clock ||
      ReaderCornerContent.clockAndBattery => _clock,
      ReaderCornerContent.battery => '',
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

  Widget _label(ReaderCornerContent content, Color color, TextAlign align) {
    if (!content.needsBattery) return _textLabel(_text(content), color, align);
    return Row(
      mainAxisAlignment: align == TextAlign.left
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        if (content.needsClock) ...[
          Flexible(child: _textLabel(_clock, color, align)),
          const SizedBox(width: 8),
        ],
        ReaderBatteryIcon(
          level: _battery.value.level,
          charging: _battery.value.charging,
          color: color,
        ),
      ],
    );
  }

  Widget _textLabel(String text, Color color, TextAlign align) => Text(
    text,
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

/// 静态纸面与预热纸面共享系统状态，异步读取期间保留最近有效值。
class _BatteryStatus extends ValueNotifier<ReaderBatteryStatus> {
  _BatteryStatus() : super((level: null, charging: null));

  static const _channel = MethodChannel('com.spectacular.reader_mobile/reader');
  static const _events = EventChannel('com.spectacular.reader_mobile/battery');
  StreamSubscription<Object?>? _subscription;
  Future<void>? _pending;
  int _generation = 0;
  int _eventRevision = 0;

  Future<void> refresh() {
    final pending = _pending;
    if (pending != null) return pending;
    final generation = _generation;
    return _pending = _read(generation).whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<void> _read(int generation) async {
    try {
      final revision = _eventRevision;
      final status = await _channel.invokeMapMethod<String, Object?>(
        'getBatteryStatus',
      );
      if (generation != _generation || !hasListeners || status == null) return;
      // 分钟查询晚于系统事件返回时，不能把新充电状态覆盖成旧状态。
      if (revision == _eventRevision) _update(status);
      _watch(generation);
    } on MissingPluginException {
      // 桌面或测试环境不提供电量，显示不可用状态。
    } on PlatformException {
      // 系统暂时无法读取时保留最后一次有效电量。
    }
  }

  void _watch(int generation) {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (event) {
        if (generation != _generation || !hasListeners) return;
        _eventRevision++;
        _update(event);
      },
      onError: (Object error) {
        // 系统暂时无法推送时保留有效状态，分钟查询继续兜底。
      },
    );
  }

  void _update(Object? event) {
    if (event is! Map) return;
    final level = event['level'];
    final charging = event['charging'];
    value = (
      level: level is int && level >= 0 && level <= 100 ? level : value.level,
      charging: charging is bool ? charging : value.charging,
    );
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _generation++;
      _pending = null;
      unawaited(_subscription?.cancel());
      _subscription = null;
      value = (level: null, charging: null);
    }
  }
}
