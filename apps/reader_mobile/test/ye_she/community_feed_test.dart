import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/community_feed.dart';

void main() {
  test('分页失败保留已有内容，重试同页，末页停止请求', () async {
    final pages = <int>[];
    final feed = CommunityFeed<int>((page) async {
      pages.add(page);
      if (pages.length == 2) throw StateError('网络不可用');
      return page == 1
          ? (items: [1, 2], hasMore: true)
          : (items: [2, 3], hasMore: false);
    }, (id) => id);
    addTearDown(feed.dispose);
    await feed.ensureLoaded();
    await feed.next();
    expect(feed.items, [1, 2]);
    expect(feed.error, contains('网络不可用'));
    await feed.retry();
    await feed.next();
    expect(pages, [1, 2, 2]);
    expect(feed.items, [1, 2, 3]);
    expect(feed.error, isNull);
  });

  test('连续触底只请求一次，刷新后的列表不会被迟到的旧页覆盖', () async {
    final pages = <int>[];
    final pending = Completer<CommunityBatch<int>>();
    final feed = CommunityFeed<int>((page) async {
      pages.add(page);
      if (page == 2) return pending.future;
      return (items: [pages.length], hasMore: true);
    }, (id) => id);
    addTearDown(feed.dispose);
    await feed.ensureLoaded();
    final loading = feed.next();
    await feed.next();
    await feed.refresh();
    pending.complete((items: [2], hasMore: false));
    await loading;
    expect(pages, [1, 2, 1]);
    expect(feed.items, [3]);
    expect(feed.hasMore, isTrue);
  });
}
