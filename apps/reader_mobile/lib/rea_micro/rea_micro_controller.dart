import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/library_store.dart';
import '../storage/reading_session_store.dart';
import 'rea_micro_api_client.dart';
import 'rea_micro_models.dart';
import 'rea_micro_store.dart';

/// 一次阅读时长同步的结果。
class ReaMicroSyncResult {
  /// 创建结果。
  const ReaMicroSyncResult({
    required this.success,
    required this.message,
    this.requests = 0,
    this.durationSeconds = 0,
  });

  /// 是否至少成功提交了一部分数据。
  final bool success;

  /// 用户可读结果。
  final String message;

  /// 成功请求数。
  final int requests;

  /// 成功上报的总秒数。
  final int durationSeconds;
}

/// 阅微登录、账号数据与阅读时长同步状态。
class ReaMicroController extends ChangeNotifier {
  /// 创建控制器。
  ReaMicroController({
    required LibraryStore library,
    ReaMicroApi? api,
    ReaMicroStore? store,
  }) : _library = library,
       _api = api ?? ReaMicroApiClient(),
       _store = store ?? ReaMicroStore(library);

  final LibraryStore _library;
  final ReaMicroApi _api;
  final ReaMicroStore _store;

  String? _token;
  ReaMicroUser? _user;
  List<ReaMicroChartPoint> _chart = const <ReaMicroChartPoint>[];
  Map<String, ReaMicroBookLink> _links = <String, ReaMicroBookLink>{};
  DateTime? _lastSyncAt;
  DateTime? _lastRefreshAt;
  bool _busy = false;
  bool _sendingCode = false;
  bool _syncing = false;
  bool _initialized = false;
  bool _disposed = false;
  Timer? _autoSyncTimer;
  String? _error;
  String? _notice;

  /// 是否已登录。
  bool get signedIn => _token != null;

  /// 当前访问令牌；只在网络层使用，不展示到界面。
  String? get token => _token;

  /// 缓存的账号信息。
  ReaMicroUser? get user => _user;

  /// 最近若干天的阅读时长。
  List<ReaMicroChartPoint> get chart => _chart;

  /// 本地书籍与云端书籍的关联。
  Map<String, ReaMicroBookLink> get links =>
      Map<String, ReaMicroBookLink>.unmodifiable(_links);

  /// 上次成功同步时间。
  DateTime? get lastSyncAt => _lastSyncAt;

  /// 正在刷新账号数据。
  bool get busy => _busy;

  /// 正在发送验证码。
  bool get sendingCode => _sendingCode;

  /// 正在上报阅读时长。
  bool get syncing => _syncing;

  /// 是否已完成本地状态加载。
  bool get initialized => _initialized;

  /// 最近一次错误。
  String? get error => _error;

  /// 最近一次操作提示。
  String? get notice => _notice;

  /// 首次加载本地令牌、账号缓存、书籍关联和同步时间。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _token = await _store.loadToken();
    _user = await _store.loadCachedUser();
    _links = await _store.loadLinks();
    _lastSyncAt = await _store.loadLastSyncAt();
    _notify();
    if (_token != null) {
      await refresh(silent: true);
      if (!_disposed && _links.isNotEmpty) {
        scheduleReadingSync(delay: const Duration(seconds: 5));
      }
    }
  }

  /// 读取本地书架，供书籍匹配页展示。
  Future<List<BookEntry>> listLocalBooks() => _library.list();

  /// 阅读页关闭后延迟合并同步，避免连续开关书产生重复网络请求。
  void scheduleReadingSync({Duration delay = const Duration(seconds: 3)}) {
    if (_disposed || !signedIn || _links.isEmpty) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(delay, () async {
      if (_disposed) return;
      if (_syncing) {
        scheduleReadingSync(delay: delay);
        return;
      }
      await syncReadingSessions();
    });
  }

  /// 刷新账号与阅读图表；[silent] 为静默刷新时不覆盖已有数据。
  Future<void> refresh({bool silent = false}) async {
    final token = _token;
    if (token == null || _busy) return;
    await _refreshInternal(token, silent: silent);
  }

  Future<void> _refreshInternal(String token, {required bool silent}) async {
    _busy = true;
    if (!silent) _error = null;
    _notify();
    try {
      final userFuture = _api.fetchUser(token);
      final chartFuture = _api.fetchReadTimeChart(token);
      final results = await Future.wait<Object?>(<Future<Object?>>[
        userFuture,
        chartFuture,
      ]);
      final user = results[0]! as ReaMicroUser;
      final chart = results[1]! as List<ReaMicroChartPoint>;
      _user = user;
      _chart = List<ReaMicroChartPoint>.unmodifiable(chart);
      _lastRefreshAt = DateTime.now();
      _error = null;
      await _store.saveCachedUser(user);
    } catch (error) {
      await _handleError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 超过给定间隔才刷新，供切换页面时低频调用。
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    if (_token == null || _busy) return;
    final last = _lastRefreshAt;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    await refresh(silent: true);
  }

  /// 发送邮箱验证码。
  Future<bool> sendEmailCode(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      _error = '请先填写邮箱';
      _notify();
      return false;
    }
    if (_sendingCode) return false;
    _sendingCode = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      await _api.sendEmailCode(normalized);
      _notice = '验证码已发送，请检查邮箱';
      return true;
    } catch (error) {
      await _handleError(error);
      return false;
    } finally {
      _sendingCode = false;
      _notify();
    }
  }

  /// 使用邮箱验证码登录。
  Future<bool> login({required String email, required String code}) async {
    final normalizedEmail = email.trim();
    final normalizedCode = code.trim();
    if (normalizedEmail.isEmpty || normalizedCode.isEmpty) {
      _error = '请填写邮箱和验证码';
      _notify();
      return false;
    }
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      final token = await _api.loginWithEmail(
        email: normalizedEmail,
        code: normalizedCode,
      );
      _token = token;
      await _store.saveToken(token);
      _links = await _store.loadLinks();
      _notice = '登录成功';
      await _refreshInternal(token, silent: true);
      return true;
    } catch (error) {
      await _handleError(error);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 退出登录，保留本地阅读记录和书籍关联。
  Future<void> logout() async {
    await _store.clearAuth();
    _token = null;
    _user = null;
    _chart = const <ReaMicroChartPoint>[];
    _lastRefreshAt = null;
    _error = null;
    _notice = '已退出阅微账号';
    _notify();
  }

  /// 搜索云端书籍。
  Future<ReaMicroCloudBook?> searchCloudBook({
    required String name,
    String author = '',
  }) async {
    final token = _token;
    if (token == null) {
      throw const ReaMicroException('请先登录阅微账号');
    }
    final query = name.trim();
    if (query.isEmpty) {
      throw const ReaMicroException('请填写书名');
    }
    try {
      return await _api.searchCloudBook(
        token,
        name: query,
        author: author.trim(),
      );
    } catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 关联本地书籍与云端书籍。
  Future<void> linkBook(String bookId, ReaMicroCloudBook book) async {
    _links = <String, ReaMicroBookLink>{
      ..._links,
      bookId: ReaMicroBookLink(
        cloudBookId: book.cloudBookId,
        name: book.name,
        author: book.author,
        linkedAt: DateTime.now(),
      ),
    };
    await _store.saveLinks(_links);
    _notice = '已关联《${book.name}》';
    _notify();
  }

  /// 解除本地书籍关联。
  Future<void> unlinkBook(String bookId) async {
    final next = Map<String, ReaMicroBookLink>.of(_links)..remove(bookId);
    _links = next;
    await _store.saveLinks(_links);
    _notice = '已解除关联';
    _notify();
  }

  /// 将尚未上报的阅读时段按书、按北京时间自然日聚合后提交。
  Future<ReaMicroSyncResult> syncReadingSessions() async {
    final token = _token;
    if (token == null) {
      return const ReaMicroSyncResult(success: false, message: '请先登录阅微账号');
    }
    if (_syncing) {
      return const ReaMicroSyncResult(success: false, message: '正在同步，请稍后');
    }
    if (_links.isEmpty) {
      return const ReaMicroSyncResult(success: false, message: '尚未关联任何阅微书籍');
    }
    final sessionStore = _library.readingSessionStore();
    if (sessionStore == null) {
      return const ReaMicroSyncResult(success: false, message: '本地阅读记录暂不可用');
    }
    _syncing = true;
    _error = null;
    _notice = null;
    _notify();
    List<ReadingSession> sessions;
    Set<String> uploaded;
    Map<String, int> watermarks;
    try {
      sessions = await sessionStore.list();
      uploaded = await _store.loadUploadedSessionKeys();
      watermarks = await _store.loadSessionWatermarks();
    } catch (error) {
      _syncing = false;
      await _handleError(error);
      _notify();
      return ReaMicroSyncResult(success: false, message: _error ?? '读取阅读记录失败');
    }

    final groups = <String, _SyncGroup>{};
    final bookEnds = <String, int>{};
    final pendingGroupCount = <String, int>{};
    for (final session in sessions) {
      final endedAt = session.endedAt.millisecondsSinceEpoch;
      if (endedAt <= (watermarks[session.bookId] ?? 0)) continue;
      final link = _links[session.bookId];
      if (link == null) continue;
      for (final portion in _splitSession(session)) {
        if (uploaded.contains(portion.key)) continue;
        final key = '${link.cloudBookId}|${portion.date}';
        final group = groups.putIfAbsent(
          key,
          () => _SyncGroup(cloudBookId: link.cloudBookId, date: portion.date),
        );
        group.durationSeconds += portion.durationSeconds;
        group.keys.add(portion.key);
        group.bookIds.add(session.bookId);
      }
      final currentEnd = bookEnds[session.bookId] ?? 0;
      if (endedAt > currentEnd) bookEnds[session.bookId] = endedAt;
    }
    for (final group in groups.values) {
      for (final bookId in group.bookIds) {
        pendingGroupCount.update(
          bookId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    Future<void> saveAdvancedWatermarks() async {
      final next = Map<String, int>.of(watermarks);
      var changed = false;
      for (final entry in bookEnds.entries) {
        if ((pendingGroupCount[entry.key] ?? 0) != 0) continue;
        if (entry.value > (next[entry.key] ?? 0)) {
          next[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        watermarks = next;
        await _store.saveSessionWatermarks(next);
      }
    }

    if (groups.isEmpty) {
      await saveAdvancedWatermarks();
      _syncing = false;
      _notice = '没有新的阅读记录需要同步';
      _notify();
      return const ReaMicroSyncResult(success: true, message: '没有新的阅读记录需要同步');
    }

    var requests = 0;
    var durationSeconds = 0;
    String? failure;
    for (final group in groups.values) {
      try {
        await _api.updateReadTimeByDate(token, <ReaMicroReadTimeEntry>[
          ReaMicroReadTimeEntry(
            cloudBookId: group.cloudBookId,
            date: group.date,
            durationSeconds: group.durationSeconds,
          ),
        ]);
        uploaded.addAll(group.keys);
        for (final bookId in group.bookIds) {
          final remaining = (pendingGroupCount[bookId] ?? 1) - 1;
          pendingGroupCount[bookId] = remaining < 0 ? 0 : remaining;
        }
        requests += 1;
        durationSeconds += group.durationSeconds;
      } catch (error) {
        failure = _messageOf(error);
        if (error is ReaMicroException && error.unauthorized) {
          await _clearExpiredAuth();
        }
        break;
      }
    }

    await saveAdvancedWatermarks();
    if (requests > 0) {
      await _store.saveUploadedSessionKeys(uploaded);
      final now = DateTime.now();
      _lastSyncAt = now;
      await _store.saveLastSyncAt(now);
    }
    _syncing = false;
    if (failure == null) {
      final message = requests == 0
          ? '没有新的阅读记录需要同步'
          : '已同步 $requests 天，共 ${_formatDuration(durationSeconds)}';
      _notice = message;
      _notify();
      return ReaMicroSyncResult(
        success: true,
        message: message,
        requests: requests,
        durationSeconds: durationSeconds,
      );
    }
    _error = failure;
    _syncing = false;
    _notify();
    return ReaMicroSyncResult(
      success: requests > 0,
      message: requests == 0 ? failure : '已同步 $requests 天，其余记录失败：$failure',
      requests: requests,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> _handleError(Object error) async {
    if (error is ReaMicroException && error.unauthorized) {
      await _clearExpiredAuth();
      _error = '阅微登录已失效，请重新登录';
      return;
    }
    _error = _messageOf(error);
  }

  Future<void> _clearExpiredAuth() async {
    await _store.clearAuth();
    _token = null;
    _user = null;
    _chart = const <ReaMicroChartPoint>[];
    _lastRefreshAt = null;
  }

  String _messageOf(Object error) =>
      error is ReaMicroException ? error.message : '操作失败：$error';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoSyncTimer?.cancel();
    _api.close();
    super.dispose();
  }
}

class _SyncGroup {
  _SyncGroup({required this.cloudBookId, required this.date});

  final int cloudBookId;
  final String date;
  final Set<String> keys = <String>{};
  final Set<String> bookIds = <String>{};
  int durationSeconds = 0;
}

class _SessionPortion {
  const _SessionPortion({
    required this.date,
    required this.durationSeconds,
    required this.key,
  });

  final String date;
  final int durationSeconds;
  final String key;
}

List<_SessionPortion> _splitSession(ReadingSession session) {
  if (session.duration <= Duration.zero ||
      !session.endedAt.isAfter(session.startedAt)) {
    return const <_SessionPortion>[];
  }
  final start = _chinaTime(session.startedAt);
  final end = _chinaTime(session.endedAt);
  final portions = <_SessionPortion>[];
  var cursor = start;
  while (cursor.isBefore(end)) {
    // start/end 已平移为北京时间墙钟值并保留 UTC 标志，日期边界也必须
    // 使用同一表示，避免与设备本地时区午夜混算。
    final dayStart = DateTime.utc(cursor.year, cursor.month, cursor.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final segmentEnd = end.isBefore(dayEnd) ? end : dayEnd;
    final seconds = segmentEnd.difference(cursor).inSeconds;
    if (seconds > 0) {
      final date = _dateString(dayStart);
      portions.add(
        _SessionPortion(
          date: date,
          durationSeconds: seconds,
          key:
              '${session.bookId}|'
              '${session.startedAt.millisecondsSinceEpoch}|'
              '${session.endedAt.millisecondsSinceEpoch}|$date',
        ),
      );
    }
    cursor = segmentEnd;
  }
  return portions;
}

DateTime _chinaTime(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  value.millisecondsSinceEpoch,
  isUtc: true,
).add(const Duration(hours: 8));

String _dateString(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final remain = minutes % 60;
  return remain == 0 ? '$hours 小时' : '$hours 小时 $remain 分钟';
}
