import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// 让词典 WebView 优先接收触摸，避免外层弹窗抢走纵向滚动手势。
const dictionaryWebViewGestureRecognizers =
    <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    };
