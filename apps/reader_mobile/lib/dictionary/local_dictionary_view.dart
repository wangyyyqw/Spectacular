import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'local_dictionary_server.dart';
import 'local_dictionary_store.dart';

class LocalDictionaryView extends StatefulWidget {
  const LocalDictionaryView({
    super.key,
    required this.session,
    required this.definition,
    required this.onLookup,
  });
  final LocalDictionarySession session;
  final String definition;
  final ValueChanged<String> onLookup;

  @override
  State<LocalDictionaryView> createState() => _LocalDictionaryViewState();
}

class _LocalDictionaryViewState extends State<LocalDictionaryView> {
  LocalDictionaryServer? _server;
  AudioPlayer? _audio;
  String? _error;
  bool _pageLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start ??= _open(Theme.of(context).brightness == Brightness.dark);
  }

  Future<void>? _start;
  Future<void> _open(bool dark) async {
    try {
      final server = await LocalDictionaryServer.start(
        widget.session,
        widget.definition,
        dark: dark,
      );
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() => _server = server);
    } catch (_) {
      if (mounted) setState(() => _error = '本地释义显示失败，请重新查询');
    }
  }

  @override
  void dispose() {
    unawaited(_server?.close());
    unawaited(_audio?.dispose());
    super.dispose();
  }

  Future<NavigationActionPolicy> _navigate(Uri? uri) async {
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (uri.scheme == 'entry' || uri.scheme == 'sound') {
      final value = Uri.decodeComponent(
        uri.toString().split('://').skip(1).join('://').split('#').first,
      );
      if (uri.scheme == 'entry') {
        widget.onLookup(value);
      } else {
        final source = dictionaryResourceUri(_server!.baseUri, value);
        if (source != null) {
          try {
            await (_audio ??= AudioPlayer()).play(UrlSource(source.toString()));
          } catch (_) {
            if (mounted) setState(() => _error = '发音资源无法播放，请检查配套 MDD');
          }
        }
      }
      return NavigationActionPolicy.CANCEL;
    }
    return isLocalDictionaryUrl(uri, _server!.baseUri)
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) Text(_error!),
        SizedBox(
          height: 340,
          child: server == null
              ? _error == null
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox.shrink()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri.uri(server.pageUri),
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
                        ),
                        shouldOverrideUrlLoading: (_, action) =>
                            _navigate(action.request.url),
                        onLoadStop: (_, url) {
                          if (mounted) setState(() => _pageLoading = false);
                        },
                        onReceivedError: (_, request, error) {
                          if (request.isForMainFrame == true && mounted) {
                            setState(() {
                              _pageLoading = false;
                              _error = '本地释义显示失败，请重新查询';
                            });
                          }
                        },
                      ),
                    ),
                    if (_pageLoading)
                      const Positioned.fill(
                        child: Center(
                          child: CircularProgressIndicator(
                            key: ValueKey('dictionary-local-loading'),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
