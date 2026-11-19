import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.spectacular.reader_mobile/reader');

Future<void> setReaderSystemBars({
  required bool statusBar,
  required bool navigationBar,
}) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod<void>('setSystemBars', {
        'statusBar': statusBar,
        'navigationBar': navigationBar,
      });
      return;
    } on MissingPluginException {
      await _setFlutterSystemBars(statusBar, navigationBar);
    }
  } else {
    await _setFlutterSystemBars(statusBar, navigationBar);
  }
}

Future<void> _setFlutterSystemBars(bool statusBar, bool navigationBar) =>
    SystemChrome.setEnabledSystemUIMode(
      statusBar && navigationBar
          ? SystemUiMode.edgeToEdge
          : SystemUiMode.manual,
      overlays: [
        if (statusBar) SystemUiOverlay.top,
        if (navigationBar) SystemUiOverlay.bottom,
      ],
    );

SystemUiOverlayStyle readerSystemBarStyle(Color background) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  final icons = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: brightness,
    statusBarIconBrightness: icons,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
  );
}
