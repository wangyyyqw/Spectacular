import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../tap_zones.dart';

/// 九宫格点击区域编辑页。
class TapZoneEditor extends StatefulWidget {
  /// 创建编辑页。
  const TapZoneEditor({
    super.key,
    required this.zones,
    required this.onApply,
    required this.onCancel,
    required this.foreground,
    required this.background,
  });

  /// 当前配置。
  final ReaderTapZones zones;

  /// 点击“保留”。
  final ValueChanged<ReaderTapZones> onApply;

  /// 取消编辑。
  final VoidCallback onCancel;

  /// 主文字色。
  final Color foreground;

  /// 页面底色。
  final Color background;

  @override
  State<TapZoneEditor> createState() => _TapZoneEditorState();
}

class _TapZoneEditorState extends State<TapZoneEditor> {
  late ReaderTapZones _draft = widget.zones;

  void _cycle(ReaderTapZone zone) {
    final current = _draft.actionAt(zone);
    final next = ReaderTapAction
        .values[(current.index + 1) % ReaderTapAction.values.length];
    setState(() => _draft = _draft.withAction(zone, next));
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.foreground.withValues(alpha: 0.07);
    return Material(
      color: widget.background,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 58,
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: const ValueKey<String>('tap-zone-cancel'),
                    onPressed: widget.onCancel,
                    icon: const AppIcon(AppGlyph.close),
                    color: widget.foreground,
                    tooltip: '取消',
                  ),
                  Expanded(
                    child: Text(
                      '点击区域设置',
                      style: TextStyle(
                        color: widget.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey<String>('tap-zone-apply'),
                    onPressed: () => widget.onApply(_draft),
                    child: const Text('保留'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点按方格切换动作',
                  style: TextStyle(
                    color: widget.foreground.withValues(alpha: 0.58),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: Column(
                  children: <Widget>[
                    for (var row = 0; row < 3; row++) ...<Widget>[
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            for (var column = 0; column < 3; column++) ...[
                              Expanded(
                                child: _TapZoneCell(
                                  zone: ReaderTapZone.values[row * 3 + column],
                                  action: _draft.actionAt(
                                    ReaderTapZone.values[row * 3 + column],
                                  ),
                                  foreground: widget.foreground,
                                  fill: fill,
                                  onTap: () => _cycle(
                                    ReaderTapZone.values[row * 3 + column],
                                  ),
                                ),
                              ),
                              if (column < 2) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      if (row < 2) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TapZoneCell extends StatelessWidget {
  const _TapZoneCell({
    required this.zone,
    required this.action,
    required this.foreground,
    required this.fill,
    required this.onTap,
  });

  final ReaderTapZone zone;
  final ReaderTapAction action;
  final Color foreground;
  final Color fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: ValueKey<String>('tap-zone-${zone.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                action.label,
                key: ValueKey<String>('tap-zone-${zone.name}-action'),
                style: TextStyle(
                  color: foreground,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              AppIcon(
                AppGlyph.touchApp,
                size: 18,
                color: foreground.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
