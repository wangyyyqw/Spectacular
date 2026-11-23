import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/theme/reader_background.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import 'reader_background_store.dart';

/// 取色仅影响阅读面板，不更改正文参数或排版指纹。
class ReaderBackgroundColorTheme extends StatefulWidget {
  const ReaderBackgroundColorTheme({
    super.key,
    required this.enabled,
    required this.theme,
    required this.backgroundId,
    required this.store,
    required this.child,
  });

  final bool enabled;
  final ReaderTheme theme;
  final String backgroundId;
  final ReaderBackgroundStore store;
  final Widget child;

  @override
  State<ReaderBackgroundColorTheme> createState() =>
      _ReaderBackgroundColorThemeState();
}

class _ReaderBackgroundColorThemeState
    extends State<ReaderBackgroundColorTheme> {
  int _request = 0;
  ColorScheme? _imageScheme;
  final Map<(String, Brightness), ColorScheme> _cache = {};

  bool get _enabled => widget.enabled && widget.theme.id != 'ink';
  Brightness get _brightness =>
      widget.theme.isDark ? Brightness.dark : Brightness.light;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReaderBackgroundColorTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.backgroundId != widget.backgroundId ||
        oldWidget.theme != widget.theme ||
        oldWidget.store != widget.store) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    _imageScheme = null;
    if (!_enabled) return;
    final background = ReaderBackground.byId(widget.backgroundId);
    if (!background.isImage && background.asset == null) return;
    final key = (background.id, _brightness);
    final cached = _cache[key];
    if (cached != null) {
      _imageScheme = cached;
      return;
    }
    final brightness = _brightness;
    try {
      final bytes = background.isImage
          ? await widget.store.load(background.id)
          : (await rootBundle.load(background.asset!)).buffer.asUint8List();
      final scheme = background.tint == null
          ? await ColorScheme.fromImageProvider(
              provider: MemoryImage(bytes),
              brightness: brightness,
            )
          : ColorScheme.fromSeed(
              seedColor: background.tint!,
              brightness: brightness,
            );
      if (!mounted || request != _request) return;
      _cache[key] = scheme;
      setState(() => _imageScheme = scheme);
    } catch (_) {
      // 背景失效时按当前纯色取色，正文原有的恢复流程继续负责图片。
    }
  }

  @override
  Widget build(BuildContext context) => ReaderPanelColorScope(
    scheme: _enabled
        ? _imageScheme ??
              ColorScheme.fromSeed(
                seedColor: widget.theme.background,
                brightness: _brightness,
              )
        : null,
    child: widget.child,
  );
}
