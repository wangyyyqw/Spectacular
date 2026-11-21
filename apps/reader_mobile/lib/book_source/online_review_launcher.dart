import 'package:flutter/services.dart';

import 'book_source_models.dart';
import 'book_source_service.dart';
import 'online_reading_book.dart';
import 'online_review.dart';

/// 在线段评与阅读页共享登录状态，关闭面板后仍停留在原文。
class OnlineReviewLauncher {
  const OnlineReviewLauncher();

  static const _channel = MethodChannel(
    'com.spectacular.reader_mobile/online_review',
  );

  Future<void> open(
    OnlineReadingBook reading,
    int spineIndex,
    OnlineReviewAction action,
  ) async {
    if (spineIndex < 0 || spineIndex >= reading.chapters.length) return;
    final service = reading.service;
    final page = await service.openReview(
      reading.source,
      reading.book,
      reading.chapters[spineIndex],
      action,
    );
    await show(reading.source, service, page);
  }

  Future<void> show(
    BookSource source,
    BookSourceService service,
    OnlineReviewPage page,
  ) async {
    final result = await _channel.invokeMapMethod<String, Object?>('show', {
      'url': page.url,
      'html': page.html,
      'preloadJs': page.preloadJs,
      'config': page.config,
      'headers': page.headers,
      'cookie': source.enabledCookieJar
          ? service.cookieStore.cookieHeader(page.url)
          : '',
      'enabledCookieJar': source.enabledCookieJar,
    });
    final cookie = result?['cookie'];
    final url = result?['url'];
    if (source.enabledCookieJar && cookie is String && url is String) {
      await service.cookieStore.saveLoginCookies(url, {
        for (final part in cookie.split(';'))
          if (part.indexOf('=') > 0)
            part.substring(0, part.indexOf('=')).trim(): part
                .substring(part.indexOf('=') + 1)
                .trim(),
      }, source: source);
    }
  }
}
