import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/dictionary/dictionary_webview_settings.dart';

void main() {
  test('两类释义保持只读、固定缩放和纵向滚动，在线兼容选项不影响本地', () {
    final local = dictionaryWebViewSettings();
    final online = dictionaryWebViewSettings(
      disableContextMenu: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
    );
    for (final settings in [local, online]) {
      expect(settings.javaScriptEnabled, isFalse);
      expect(settings.javaScriptCanOpenWindowsAutomatically, isFalse);
      expect(settings.allowFileAccess, isFalse);
      expect(settings.allowContentAccess, isFalse);
      expect(settings.allowFileAccessFromFileURLs, isFalse);
      expect(settings.allowUniversalAccessFromFileURLs, isFalse);
      expect(settings.useShouldOverrideUrlLoading, isTrue);
      expect(settings.disableVerticalScroll, isFalse);
      expect(settings.disableHorizontalScroll, isTrue);
      expect(settings.supportZoom, isFalse);
      expect(settings.textZoom, 100);
    }
    expect(local.disableContextMenu, isFalse);
    expect(local.mixedContentMode, isNull);
    expect(online.disableContextMenu, isTrue);
    expect(
      online.mixedContentMode,
      MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
    );
  });
}
