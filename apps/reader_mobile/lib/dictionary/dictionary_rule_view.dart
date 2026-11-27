import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'dictionary_rule_html.dart';
import 'dictionary_webview_gestures.dart';

class DictionaryRuleView extends StatefulWidget {
  const DictionaryRuleView({
    super.key,
    required this.html,
    required this.baseUrl,
    this.height = 340,
  });
  final String html;
  final String baseUrl;
  final double height;

  @override
  State<DictionaryRuleView> createState() => _DictionaryRuleViewState();
}

class _DictionaryRuleViewState extends State<DictionaryRuleView> {
  String? _html;
  String? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _html ??= buildRuleDictionaryHtml(
      widget.html,
      Uri.tryParse(widget.baseUrl) ?? Uri(),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Stack(
      children: [
        Positioned.fill(
          child: _error != null
              ? Center(child: Text(_error!))
              : InAppWebView(
                  gestureRecognizers: dictionaryWebViewGestureRecognizers,
                  initialData: InAppWebViewInitialData(
                    data: _html!,
                    baseUrl: WebUri(widget.baseUrl),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: false,
                    javaScriptCanOpenWindowsAutomatically: false,
                    allowFileAccess: false,
                    allowContentAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                    useShouldOverrideUrlLoading: true,
                    transparentBackground: true,
                    useHybridComposition: true,
                    disableVerticalScroll: false,
                    disableHorizontalScroll: true,
                    verticalScrollBarEnabled: true,
                    horizontalScrollBarEnabled: false,
                    supportZoom: false,
                    textZoom: 100,
                    disableContextMenu: true,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                  ),
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url;
                    if (url == null) return NavigationActionPolicy.CANCEL;
                    // 只允许首屏 data/about:blank，点击结果里的外链不离开词典。
                    if (url.scheme == 'data' ||
                        url.toString() == 'about:blank' ||
                        url.toString() == widget.baseUrl) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    return NavigationActionPolicy.CANCEL;
                  },
                  onLoadStop: (_, _) {
                    if (mounted) setState(() => _loading = false);
                  },
                  onReceivedError: (_, request, _) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() {
                        _loading = false;
                        _error = '在线词典内容显示失败';
                      });
                    }
                  },
                ),
        ),
        if (_loading && _error == null)
          const Positioned.fill(
            child: Center(
              child: CircularProgressIndicator(
                key: ValueKey('dictionary-rule-loading'),
              ),
            ),
          ),
      ],
    ),
  );
}
