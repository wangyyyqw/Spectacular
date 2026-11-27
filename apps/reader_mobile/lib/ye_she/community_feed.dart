import 'package:flutter/foundation.dart';

typedef CommunityBatch<T> = ({List<T> items, bool hasMore});

class CommunityFeed<T> extends ChangeNotifier {
  CommunityFeed(this._fetch, this._identity);

  final Future<CommunityBatch<T>> Function(int page) _fetch;
  final Object Function(T item) _identity;
  List<T> items = [];
  int _page = 0;
  int _generation = 0;
  bool hasMore = true;
  bool loading = false;
  bool _refreshing = false;
  bool _retryFirst = false;
  String? error;

  Future<void> ensureLoaded() =>
      _page == 0 && error == null ? next() : Future<void>.value();

  Future<void> refresh() => _load(reset: true);
  Future<void> next() => _load(reset: false);
  Future<void> retry() => _load(reset: _retryFirst);

  Future<void> _load({required bool reset}) async {
    if (reset ? _refreshing : loading || !hasMore) return;
    final generation = ++_generation;
    final page = reset ? 1 : _page + 1;
    _refreshing = reset;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final batch = await _fetch(page);
      if (_generation != generation) return;
      final previous = reset ? <T>[] : items;
      final seen = previous.map(_identity).toSet();
      final fresh = batch.items
          .where((item) => seen.add(_identity(item)))
          .toList();
      items = [...previous, ...fresh];
      _page = page;
      hasMore = batch.hasMore && fresh.isNotEmpty;
    } catch (failure) {
      if (_generation != generation) return;
      error = failure.toString();
      _retryFirst = reset;
    } finally {
      if (_generation == generation) {
        loading = false;
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    _generation++;
    _page = 0;
    items = [];
    loading = _refreshing = false;
    hasMore = true;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
