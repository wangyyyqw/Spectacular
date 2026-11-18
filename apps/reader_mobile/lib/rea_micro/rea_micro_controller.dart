import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../storage/reading_session_store.dart';
import 'rea_micro_api_client.dart';
import 'rea_micro_lan.dart';
import 'rea_micro_models.dart';
import 'rea_micro_progress_mapping.dart';
import 'rea_micro_progress_store.dart';
import 'rea_micro_s3.dart';
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
    ReaderProgressStore? progressStore,
    ReaMicroLanClient? lan,
    ReaMicroS3Client Function(ReaMicroS3Config config)? s3ClientFactory,
  }) : _library = library,
       _api = api ?? ReaMicroApiClient(),
       _store = store ?? ReaMicroStore(library),
       _rawProgressStore = progressStore,
       // ignore: prefer_initializing_formals
       _s3ClientFactory = s3ClientFactory,
       _lan = lan ?? ReaMicroLanClient() {
    _trackedProgressStore = progressStore == null
        ? null
        : ReaMicroTrackingProgressStore(progressStore, _onLocalProgressSaved);
  }

  final LibraryStore _library;
  final ReaMicroApi _api;
  final ReaMicroStore _store;
  final ReaderProgressStore? _rawProgressStore;
  final ReaMicroLanClient _lan;
  final ReaMicroS3Client Function(ReaMicroS3Config config)? _s3ClientFactory;
  late final ReaderProgressStore? _trackedProgressStore;

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
  Timer? _progressSyncTimer;
  String? _error;
  String? _notice;
  Map<String, ReaMicroProgressState> _progressStates =
      <String, ReaMicroProgressState>{};
  Future<void> _progressPersist = Future<void>.value();
  bool _syncingProgress = false;
  bool _syncingMarks = false;
  String? _deviceId;
  List<ReaMicroLanLoginDevice> _lanLoginDevices =
      const <ReaMicroLanLoginDevice>[];
  List<ReaMicroLanSyncPeer> _lanSyncPeers = const <ReaMicroLanSyncPeer>[];
  bool _lanScanning = false;
  bool _lanLoggingIn = false;
  bool _lanSyncing = false;
  String? _lanMessage;
  bool _cloudAsPrimary = false;
  ReaMicroCloudStats? _cloudStats;
  DateTime? _cloudStatsAt;
  bool _loadingCloudStats = false;
  String? _cloudStatsError;
  List<ReaMicroMilestone> _milestones = const <ReaMicroMilestone>[];
  bool _loadingMilestones = false;
  String? _milestonesError;
  Timer? _cloudSyncTimer;
  Timer? _s3SyncTimer;
  ReaMicroS3Config? _s3Config;
  Map<String, String> _s3BookmarkBases = <String, String>{};
  Map<String, int> _markIds = <String, int>{};
  bool _s3Syncing = false;
  String? _s3Message;
  DateTime? _s3LastSyncAt;

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

  /// 正在同步阅读位置。
  bool get syncingProgress => _syncingProgress;

  /// 正在同步划线与想法。
  bool get syncingMarks => _syncingMarks;

  /// 是否已完成本地状态加载。
  bool get initialized => _initialized;

  /// 阅读进度存储；阅读页通过它保存后自动进入待上报队列。
  ReaderProgressStore? get trackedProgressStore => _trackedProgressStore;

  /// 局域网授权登录候选设备。
  List<ReaMicroLanLoginDevice> get lanLoginDevices => _lanLoginDevices;

  /// 局域网同步候选设备。
  List<ReaMicroLanSyncPeer> get lanSyncPeers => _lanSyncPeers;

  /// 正在扫描局域网设备。
  bool get lanScanning => _lanScanning;

  /// 正在通过局域网登录。
  bool get lanLoggingIn => _lanLoggingIn;

  /// 正在与局域网设备同步。
  bool get lanSyncing => _lanSyncing;

  /// 最近一次局域网操作结果。
  String? get lanMessage => _lanMessage;

  /// 最近一次错误。
  String? get error => _error;

  /// 最近一次操作提示。
  String? get notice => _notice;

  /// 是否把阅微作为唯一阅读数据源。
  bool get cloudAsPrimary => _cloudAsPrimary && signedIn;

  /// 最近一次拉取的阅微完整阅读数据。
  ReaMicroCloudStats? get cloudStats => _cloudStats;

  /// 上次拉取完整阅读数据的时间。
  DateTime? get cloudStatsAt => _cloudStatsAt;

  /// 正在拉取阅微完整阅读数据。
  bool get loadingCloudStats => _loadingCloudStats;

  /// 完整阅读数据拉取失败原因。
  String? get cloudStatsError => _cloudStatsError;

  /// 阅微读完里程碑。
  List<ReaMicroMilestone> get milestones => _milestones;

  /// 正在读取里程碑。
  bool get loadingMilestones => _loadingMilestones;

  /// 里程碑读取失败原因。
  String? get milestonesError => _milestonesError;

  /// 是否已配置 S3 同步。
  bool get s3Configured => _s3Config?.usable ?? false;

  /// 当前 S3 同步配置。
  ReaMicroS3Config? get s3Config => _s3Config;

  /// 正在执行 S3 同步。
  bool get s3Syncing => _s3Syncing;

  /// 最近一次 S3 同步提示。
  String? get s3Message => _s3Message;

  /// 上次 S3 同步时间。
  DateTime? get s3LastSyncAt => _s3LastSyncAt;

  /// 首次加载本地令牌、账号缓存、书籍关联和同步时间。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _token = await _store.loadToken();
    _user = await _store.loadCachedUser();
    _links = await _store.loadLinks();
    _lastSyncAt = await _store.loadLastSyncAt();
    _progressStates = await _store.loadProgressStates();
    _markIds = await _store.loadMarkIds();
    _deviceId = await _store.loadOrCreateDeviceId();
    _cloudAsPrimary = await _store.loadCloudPrimary();
    _s3Config = await _store.loadS3Config();
    _s3BookmarkBases = await _store.loadS3BookmarkBases();
    _s3LastSyncAt = await _store.loadS3LastSyncAt();
    if (_token == null && _cloudAsPrimary) {
      _cloudAsPrimary = false;
      await _store.saveCloudPrimary(false);
    }
    _notify();
    if (_token != null) {
      await refresh(silent: true);
      if (!_disposed && _token != null) {
        if (_cloudAsPrimary) {
          _startCloudAutoSync();
          await syncAll();
          await refreshCloudStats(silent: true);
        } else if (_links.isNotEmpty) {
          scheduleReadingSync(delay: const Duration(seconds: 5));
          scheduleProgressSync(delay: const Duration(seconds: 7));
        }
        if (_s3Config != null) {
          scheduleS3Sync(delay: const Duration(seconds: 9));
        }
      }
    }
  }

  /// 保存 S3 同步配置。
  Future<void> saveS3Config(ReaMicroS3Config config) async {
    _s3Config = config.usable ? config : null;
    _s3Message = null;
    if (_s3Config == null) {
      await _store.clearS3Config();
      await _clearS3BookmarkBases();
    } else {
      await _store.saveS3Config(_s3Config!);
      await _clearS3BookmarkBases();
    }
    _notify();
  }

  /// 清除 S3 同步配置。
  Future<void> clearS3Config() async {
    _s3Config = null;
    _s3Message = null;
    _s3SyncTimer?.cancel();
    await _store.clearS3Config();
    await _clearS3BookmarkBases();
    _notify();
  }

  Future<void> _clearS3BookmarkBases() async {
    _s3BookmarkBases = <String, String>{};
    await _store.clearS3BookmarkBases();
  }

  /// 账号变化后清空与云端标识绑定的同步状态，避免复用上一账号的映射。
  Future<void> _resetAccountSyncState() async {
    if (_markIds.isNotEmpty) {
      _markIds = <String, int>{};
      await _store.saveMarkIds(_markIds);
    }
    await _clearS3BookmarkBases();
    _milestones = const <ReaMicroMilestone>[];
    _loadingMilestones = false;
    _milestonesError = null;
  }

  /// 延迟执行 S3 同步，避免启动阶段与账号刷新重叠。
  void scheduleS3Sync({Duration delay = const Duration(seconds: 6)}) {
    if (_disposed || !signedIn || !s3Configured) return;
    _s3SyncTimer?.cancel();
    _s3SyncTimer = Timer(delay, () async {
      if (_disposed || !signedIn || !s3Configured) return;
      await syncS3(silent: true);
    });
  }

  /// 立即同步 S3 书籍与元数据。
  Future<ReaMicroS3SyncResult?> syncS3({
    bool silent = false,
    bool restoreMissing = true,
  }) async {
    if (_s3Syncing) {
      if (!silent) {
        _s3Message = '正在同步 S3，请稍后';
        _notify();
      }
      return null;
    }
    final config = _s3Config;
    final user = _user;
    final deviceId = _deviceId;
    if (config == null || !config.usable || user == null || deviceId == null) {
      if (!silent) {
        _s3Message = '请先配置 S3 对象存储';
        _notify();
      }
      return null;
    }
    _s3Syncing = true;
    _s3Message = restoreMissing ? '正在读取云端书籍…' : '正在上传本地变更…';
    _error = null;
    _notify();
    try {
      final client =
          _s3ClientFactory?.call(config) ?? ReaMicroS3HttpClient(config);
      final engine = ReaMicroS3SyncEngine(
        library: _library,
        config: config,
        client: client,
        userId: user.id.toString(),
        deviceId: deviceId,
        cloudIds: <String, int>{
          for (final entry in _links.entries)
            entry.key: entry.value.cloudBookId,
        },
        bookmarkBases: _s3BookmarkBases,
        onStatus: (message) {
          if (_disposed) return;
          _s3Message = message;
          _notify();
        },
      );
      final result = await engine.sync(restoreMissing: restoreMissing);
      _s3LastSyncAt = DateTime.now();
      _s3Message = result.message;
      await _store.saveS3LastSyncAt(_s3LastSyncAt!);
      if (result.bookmarkBases.isNotEmpty || _s3BookmarkBases.isNotEmpty) {
        _s3BookmarkBases = Map<String, String>.of(result.bookmarkBases);
        await _store.saveS3BookmarkBases(_s3BookmarkBases);
      }
      if (result.links.isNotEmpty) {
        final nextLinks = Map<String, ReaMicroBookLink>.of(_links);
        var changed = false;
        for (final entry in result.links.entries) {
          if (entry.value <= 0 ||
              nextLinks[entry.key]?.cloudBookId == entry.value) {
            continue;
          }
          final book = await _library.bookById(entry.key);
          if (book == null) continue;
          nextLinks[entry.key] = ReaMicroBookLink(
            cloudBookId: entry.value,
            name: book.title,
            author: book.author,
            linkedAt: DateTime.now(),
          );
          changed = true;
        }
        if (changed) {
          _links = nextLinks;
          await _store.saveLinks(nextLinks);
          for (final bookId in result.links.keys) {
            await _seedProgressStatesForBook(bookId, markDirty: false);
          }
        }
      }
      if (result.downloaded > 0 && _links.isNotEmpty) {
        scheduleProgressSync(delay: const Duration(seconds: 2));
      }
      return result;
    } catch (error) {
      _s3Message = 'S3 同步失败：${_messageOf(error)}';
      return null;
    } finally {
      _s3Syncing = false;
      _notify();
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
      if (_syncing || _syncingProgress || _syncingMarks) {
        scheduleReadingSync(delay: delay);
        return;
      }
      await syncAll();
    });
  }

  /// 阅读位置变化后延迟上报，避免每次翻页都触发网络请求。
  void scheduleProgressSync({Duration delay = const Duration(seconds: 4)}) {
    if (_disposed || !signedIn || _links.isEmpty) return;
    _progressSyncTimer?.cancel();
    _progressSyncTimer = Timer(delay, () async {
      if (_disposed) return;
      if (_syncing || _syncingProgress || _syncingMarks) {
        scheduleProgressSync(delay: delay);
        return;
      }
      await syncProgress();
    });
  }

  /// 刷新账号与阅读图表；[silent] 为静默刷新时不覆盖已有数据。
  Future<void> refresh({bool silent = false}) async {
    final token = _token;
    if (token == null || _busy) return;
    await _refreshInternal(token, silent: silent);
    if (!_disposed && _token == token && _cloudAsPrimary) {
      await refreshCloudStats(force: true, silent: silent);
    }
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

  /// 切换是否把阅微作为唯一阅读数据源。
  Future<void> setCloudAsPrimary(bool value) async {
    if (value && !signedIn) {
      _error = '请先登录阅微账号';
      _notify();
      return;
    }
    if (_cloudAsPrimary == value) return;
    _cloudAsPrimary = value;
    _error = null;
    await _store.saveCloudPrimary(value);
    if (!value) {
      _stopCloudAutoSync();
      _notice = '已改为使用本地阅读数据';
      _notify();
      return;
    }
    _startCloudAutoSync();
    _notice = '已开启阅微唯一数据源，正在同步';
    _notify();
    try {
      final linked = await autoLinkMatchingBooks();
      await syncAll();
      await refreshCloudStats(force: true, silent: true);
      _notice = linked == 0 ? '已开启阅微唯一数据源' : '已开启阅微唯一数据源并自动关联 $linked 本书';
      _notify();
    } catch (error) {
      await _handleError(error);
      _notify();
    }
  }

  /// 按书名与作者自动关联本地书籍和阅微云端阅读记录。
  Future<int> autoLinkMatchingBooks() async {
    final token = _token;
    if (token == null) return 0;
    final List<ReaMicroBookRecord> records;
    try {
      records = _cloudStats?.books ?? await _api.fetchBookRecords(token);
    } catch (error) {
      await _handleError(error);
      rethrow;
    }
    final localBooks = await _library.list();
    final next = Map<String, ReaMicroBookLink>.of(_links);
    var linked = 0;
    for (final record in records) {
      if (record.cloudBookId <= 0 || record.name.trim().isEmpty) continue;
      if (next.values.any((link) => link.cloudBookId == record.cloudBookId)) {
        continue;
      }
      final title = _normalizeBookText(record.name);
      final author = _normalizeBookText(record.author);
      final candidates = <BookEntry>[
        for (final book in localBooks)
          if (!next.containsKey(book.id) &&
              _normalizeBookText(book.title) == title &&
              (author.isEmpty || _normalizeBookText(book.author) == author))
            book,
      ];
      if (candidates.length != 1) continue;
      final book = candidates.single;
      next[book.id] = ReaMicroBookLink(
        cloudBookId: record.cloudBookId,
        name: record.name,
        author: record.author,
        linkedAt: DateTime.now(),
      );
      linked += 1;
    }
    if (linked == 0) return 0;
    _links = next;
    await _store.saveLinks(_links);
    for (final bookId in next.keys) {
      await _seedProgressStatesForBook(bookId, markDirty: false);
    }
    await _persistProgressStatesNow();
    _notice = '已自动关联 $linked 本阅微书籍';
    _notify();
    return linked;
  }

  /// 拉取阅微完整阅读概览、周期统计、趋势和全部书籍记录。
  Future<void> refreshCloudStats({
    bool force = false,
    bool silent = false,
  }) async {
    final token = _token;
    if (token == null || !_cloudAsPrimary || _loadingCloudStats) return;
    final last = _cloudStatsAt;
    if (!force &&
        _cloudStats != null &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _loadingCloudStats = true;
    if (!silent) _cloudStatsError = null;
    _notify();
    try {
      final now = DateTime.now();
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _api.fetchOverview(token),
        _api.fetchWeekStats(token, date: now),
        _api.fetchMonthStats(token, year: now.year, month: now.month),
        _api.fetchYearStats(token, year: now.year),
        _api.fetchReadTimeChart(token),
        _api.fetchBookRecords(token),
      ]);
      if (_token != token) return;
      final books =
          List<ReaMicroBookRecord>.of(results[5]! as List<ReaMicroBookRecord>)
            ..sort((left, right) {
              final compared = right.totalReadTimeSeconds.compareTo(
                left.totalReadTimeSeconds,
              );
              return compared != 0 ? compared : left.name.compareTo(right.name);
            });
      _cloudStats = ReaMicroCloudStats(
        overview: results[0]! as ReaMicroOverview,
        week: results[1]! as ReaMicroPeriodStats,
        month: results[2]! as ReaMicroPeriodStats,
        year: results[3]! as ReaMicroPeriodStats,
        chart: List<ReaMicroChartPoint>.unmodifiable(
          results[4]! as List<ReaMicroChartPoint>,
        ),
        books: List<ReaMicroBookRecord>.unmodifiable(books),
        fetchedAt: DateTime.now(),
      );
      _cloudStatsAt = _cloudStats!.fetchedAt;
      _cloudStatsError = null;
    } catch (error) {
      await _handleError(error);
      _cloudStatsError = _messageOf(error);
    } finally {
      _loadingCloudStats = false;
      _notify();
    }
  }

  /// 拉取阅微读完里程碑。
  Future<void> refreshMilestones({bool silent = false}) async {
    final token = _token;
    if (token == null || _loadingMilestones) return;
    _loadingMilestones = true;
    if (!silent) _milestonesError = null;
    _notify();
    try {
      final items = await _api.fetchMilestones(token);
      if (_token != token) return;
      _milestones = List<ReaMicroMilestone>.unmodifiable(items);
      _milestonesError = null;
    } catch (error) {
      _milestonesError = _messageOf(error);
      await _handleError(error);
    } finally {
      _loadingMilestones = false;
      _notify();
    }
  }

  /// 读取一本书在阅微的书评。
  Future<ReaMicroBookReview?> loadBookReview(int cloudBookId) async {
    final token = _token;
    if (token == null || cloudBookId <= 0) return null;
    try {
      return await _api.fetchBookReview(token, cloudBookId: cloudBookId);
    } catch (error) {
      await _handleError(error);
      return null;
    }
  }

  /// 提交一本书的评分与书评。
  Future<ReaMicroActionResult> saveReview({
    required int cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  }) async {
    final token = _token;
    if (token == null) {
      return const ReaMicroActionResult(
        success: false,
        message: '请先登录阅微账号',
        unauthorized: true,
      );
    }
    if (cloudBookId <= 0) {
      return const ReaMicroActionResult(
        success: false,
        message: '当前书籍尚未关联阅微云端书籍',
      );
    }
    try {
      await _api.rateReview(
        token,
        cloudBookId: cloudBookId,
        rating: rating,
        comment: comment,
        publish: publish,
      );
      await refreshMilestones(silent: true);
      return ReaMicroActionResult(
        success: true,
        message: publish ? '书评已发布到阅微' : '书评已保存到阅微',
      );
    } catch (error) {
      await _handleError(error);
      return ReaMicroActionResult(
        success: false,
        message: _messageOf(error),
        unauthorized: error is ReaMicroException && error.unauthorized,
      );
    }
  }

  /// 删除一条读完里程碑。
  Future<ReaMicroActionResult> deleteMilestone(int milestoneId) async {
    final token = _token;
    if (token == null) {
      return const ReaMicroActionResult(
        success: false,
        message: '请先登录阅微账号',
        unauthorized: true,
      );
    }
    if (milestoneId <= 0) {
      return const ReaMicroActionResult(success: false, message: '当前里程碑无法删除');
    }
    try {
      await _api.deleteMilestone(token, milestoneId: milestoneId);
      await refreshMilestones(silent: true);
      return const ReaMicroActionResult(success: true, message: '里程碑已删除');
    } catch (error) {
      await _handleError(error);
      return ReaMicroActionResult(
        success: false,
        message: _messageOf(error),
        unauthorized: error is ReaMicroException && error.unauthorized,
      );
    }
  }

  /// 应用回到前台时按当前数据源模式执行同步。
  void handleAppResumed() {
    if (_disposed || !signedIn) return;
    if (_cloudAsPrimary) {
      unawaited(_syncCloudNow());
    } else {
      scheduleReadingSync();
      scheduleProgressSync();
    }
  }

  Future<void> _syncCloudNow() async {
    await syncAll();
    await refreshCloudStats(force: true, silent: true);
  }

  void _startCloudAutoSync() {
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_disposed ||
          !_cloudAsPrimary ||
          !signedIn ||
          _syncing ||
          _syncingProgress ||
          _syncingMarks ||
          _loadingCloudStats) {
        return;
      }
      unawaited(_syncCloudNow());
    });
  }

  void _stopCloudAutoSync() {
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = null;
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
      await _resetAccountSyncState();
      _links = await _store.loadLinks();
      _notice = '登录成功';
      await _refreshInternal(token, silent: true);
      await _seedProgressStatesFromLocal(markDirty: false);
      scheduleReadingSync(delay: const Duration(seconds: 2));
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
    _stopCloudAutoSync();
    _cloudAsPrimary = false;
    await _store.saveCloudPrimary(false);
    await _store.clearAuth();
    await _resetAccountSyncState();
    await _progressPersist;
    _progressStates = <String, ReaMicroProgressState>{};
    await _store.clearProgressStates();
    _progressPersist = Future<void>.value();
    _token = null;
    _user = null;
    _chart = const <ReaMicroChartPoint>[];
    _lastRefreshAt = null;
    _lanLoginDevices = const <ReaMicroLanLoginDevice>[];
    _lanSyncPeers = const <ReaMicroLanSyncPeer>[];
    _lanMessage = null;
    _cloudStats = null;
    _cloudStatsAt = null;
    _cloudStatsError = null;
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
    await _seedProgressStatesForBook(bookId);
    _notice = '已关联《${book.name}》';
    _notify();
  }

  /// 解除本地书籍关联。
  Future<void> unlinkBook(String bookId) async {
    final next = Map<String, ReaMicroBookLink>.of(_links)..remove(bookId);
    _links = next;
    await _store.saveLinks(_links);
    final state = _progressStates[bookId];
    if (state != null && state.dirty) {
      _progressStates[bookId] = state.copyWith(dirty: false);
      _persistProgressStates();
    }
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

  /// 双向同步阅微划线与想法。
  Future<ReaMicroSyncResult> syncMarks() async {
    final token = _token;
    if (token == null) {
      return const ReaMicroSyncResult(success: false, message: '请先登录阅微账号');
    }
    if (_syncingMarks) {
      return const ReaMicroSyncResult(success: false, message: '正在同步标注，请稍后');
    }
    if (_links.isEmpty) {
      return const ReaMicroSyncResult(success: false, message: '尚未关联任何阅微书籍');
    }
    _syncingMarks = true;
    _error = null;
    _notify();
    final nextMarkIds = Map<String, int>.of(_markIds);
    var uploaded = 0;
    var downloaded = 0;
    var deleted = 0;
    String? failure;
    try {
      final remoteMarks = await _api.fetchMarks(token);
      final remoteById = <int, ReaMicroMark>{
        for (final mark in remoteMarks)
          if (mark.id > 0) mark.id: mark,
      };
      for (final linkEntry in List<MapEntry<String, ReaMicroBookLink>>.of(
        _links.entries,
      )) {
        if (_token != token) break;
        final localBookId = linkEntry.key;
        final link = linkEntry.value;
        final localBook = await _library.bookById(localBookId);
        if (localBook == null) continue;
        final prefix = '$localBookId|';
        final remoteForBook = <ReaMicroMark>[
          for (final mark in remoteMarks)
            if (_remoteMarkBelongsTo(mark, localBook, link)) mark,
        ];
        var localAnnotations = await _library.listBookAnnotations(localBookId);
        final localById = <String, ReaderAnnotation>{
          for (final annotation in localAnnotations) annotation.id: annotation,
        };

        for (final key
            in nextMarkIds.keys
                .where((key) => key.startsWith(prefix))
                .toList(growable: false)) {
          final localId = key.substring(prefix.length);
          final remote = remoteById[nextMarkIds[key]];
          if (localById.containsKey(localId)) continue;
          if (remote != null && _remoteMarkBelongsTo(remote, localBook, link)) {
            try {
              await _api.deleteMark(token, id: remote.id);
              deleted += 1;
              nextMarkIds.remove(key);
            } catch (error) {
              failure ??= _messageOf(error);
            }
          } else {
            nextMarkIds.remove(key);
          }
        }

        for (final remote in remoteForBook) {
          String? mappedKey;
          for (final entry in nextMarkIds.entries) {
            if (entry.key.startsWith(prefix) && entry.value == remote.id) {
              mappedKey = entry.key;
              break;
            }
          }
          final mappedLocalId = mappedKey?.substring(prefix.length);
          var local = mappedLocalId == null ? null : localById[mappedLocalId];
          local ??= _findMatchingLocalMark(localAnnotations, remote);
          final localId = local?.id ?? 'mark-cloud-${remote.id}';
          final remoteIsNewer =
              local == null ||
              remote.updatedAt > local.updatedAt.millisecondsSinceEpoch;
          nextMarkIds['$prefix$localId'] = remote.id;
          if (!remoteIsNewer) continue;
          try {
            final imported = _readerAnnotationFromRemote(localId, remote);
            await _library.importBookAnnotation(localBookId, imported);
            localById[localId] = imported;
            downloaded += 1;
          } catch (error) {
            failure ??= _messageOf(error);
          }
        }

        localAnnotations = await _library.listBookAnnotations(localBookId);
        final cloudIdsByLocal = <String, int>{
          for (final entry in nextMarkIds.entries)
            if (entry.key.startsWith(prefix))
              entry.key.substring(prefix.length): entry.value,
        };
        for (final annotation in localAnnotations) {
          if (annotation.startCfi.trim().isEmpty ||
              annotation.endCfi.trim().isEmpty) {
            continue;
          }
          final cloudId = cloudIdsByLocal[annotation.id];
          final remote = cloudId == null ? null : remoteById[cloudId];
          if (remote != null &&
              remote.updatedAt > annotation.updatedAt.millisecondsSinceEpoch) {
            continue;
          }
          if (remote != null &&
              remote.updatedAt == annotation.updatedAt.millisecondsSinceEpoch &&
              !_markDiffers(annotation, remote)) {
            continue;
          }
          try {
            var nextId = await _api.upsertMark(
              token,
              _markDraftFromLocal(annotation, link, remote: remote),
            );
            nextId ??= await _resolveUploadedMarkId(
              token,
              link: link,
              annotation: annotation,
            );
            if (nextId != null && nextId > 0) {
              nextMarkIds['$prefix${annotation.id}'] = nextId;
              uploaded += 1;
            } else {
              failure ??= '阅微未返回标注标识';
            }
          } catch (error) {
            failure ??= _messageOf(error);
            if (error is ReaMicroException && error.unauthorized) {
              await _handleError(error);
              break;
            }
          }
        }
      }
    } catch (error) {
      await _handleError(error);
      failure = _error ?? _messageOf(error);
    } finally {
      _markIds = nextMarkIds;
      await _store.saveMarkIds(_markIds);
      _syncingMarks = false;
      _notify();
    }
    final requests = uploaded + downloaded + deleted;
    final message = failure == null
        ? requests == 0
              ? '标注已是最新'
              : '已上传 $uploaded 条标注、同步 $downloaded 条、删除 $deleted 条'
        : requests == 0
        ? failure
        : '已上传 $uploaded 条、同步 $downloaded 条，其余失败：$failure';
    _notice = message;
    return ReaMicroSyncResult(
      success: failure == null || requests > 0,
      message: message,
      requests: requests,
    );
  }

  bool _remoteMarkBelongsTo(
    ReaMicroMark mark,
    BookEntry local,
    ReaMicroBookLink link,
  ) {
    final remoteBookId = mark.bookId.trim();
    if (remoteBookId == link.cloudBookId.toString() ||
        remoteBookId == local.id) {
      return true;
    }
    if (mark.bookName.trim().isEmpty) return false;
    return _normalizeBookText(mark.bookName) ==
            _normalizeBookText(local.title) &&
        (mark.bookAuthor.trim().isEmpty ||
            _normalizeBookText(mark.bookAuthor) ==
                _normalizeBookText(local.author));
  }

  ReaderAnnotation? _findMatchingLocalMark(
    List<ReaderAnnotation> local,
    ReaMicroMark remote,
  ) {
    for (final annotation in local) {
      if (annotation.type.storageValue != remote.kind) continue;
      if (annotation.startCfi != remote.startCfi) continue;
      if (remote.endCfi.isNotEmpty && annotation.endCfi != remote.endCfi) {
        continue;
      }
      return annotation;
    }
    return null;
  }

  ReaderAnnotation _readerAnnotationFromRemote(
    String localId,
    ReaMicroMark remote,
  ) {
    final createdAt = remote.createdAt > 0
        ? remote.createdAt
        : DateTime.now().millisecondsSinceEpoch;
    final updatedAt = remote.updatedAt > 0 ? remote.updatedAt : createdAt;
    return ReaderAnnotation(
      id: localId,
      type: remote.kind == 1
          ? ReaderAnnotationType.thought
          : ReaderAnnotationType.mark,
      startCfi: remote.startCfi,
      endCfi: remote.endCfi.isEmpty ? remote.startCfi : remote.endCfi,
      quote: remote.quote,
      color: _colorFromRemote(remote.color),
      style: ReaderAnnotationStyle.fromStorage(remote.style),
      note: remote.note.trim().isEmpty ? null : remote.note,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
    );
  }

  ReaMicroMarkDraft _markDraftFromLocal(
    ReaderAnnotation annotation,
    ReaMicroBookLink link, {
    ReaMicroMark? remote,
  }) => ReaMicroMarkDraft(
    cloudId: remote?.id ?? 0,
    bookId: link.cloudBookId.toString(),
    chapter: remote?.chapter ?? '',
    kind: annotation.type.storageValue,
    startCfi: annotation.startCfi,
    endCfi: annotation.endCfi,
    quote: annotation.quote,
    note: annotation.note ?? '',
    style: annotation.style.storageValue,
    color: _colorToRemote(annotation.color),
    createdAt: annotation.createdAt.millisecondsSinceEpoch,
    updatedAt: annotation.updatedAt.millisecondsSinceEpoch,
  );

  Future<int?> _resolveUploadedMarkId(
    String token, {
    required ReaMicroBookLink link,
    required ReaderAnnotation annotation,
  }) async {
    final marks = await _api.fetchMarks(
      token,
      bookId: link.cloudBookId.toString(),
    );
    for (final mark in marks) {
      if (mark.startCfi == annotation.startCfi &&
          mark.endCfi == annotation.endCfi &&
          mark.kind == annotation.type.storageValue) {
        return mark.id;
      }
    }
    return null;
  }

  bool _markDiffers(ReaderAnnotation local, ReaMicroMark remote) {
    if (local.startCfi != remote.startCfi ||
        local.endCfi != remote.endCfi ||
        local.type.storageValue != remote.kind ||
        local.style.storageValue != remote.style ||
        local.quote != remote.quote ||
        (local.note ?? '') != remote.note) {
      return true;
    }
    if (remote.color.trim().isEmpty) return false;
    final remoteColor = _colorFromRemote(remote.color);
    return remoteColor != null && local.color != remoteColor;
  }

  int? _colorFromRemote(String value) {
    var text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('#')) text = text.substring(1);
    if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    if (text.length == 6) text = 'ff$text';
    return text.length == 8 ? int.tryParse(text, radix: 16) : null;
  }

  String _colorToRemote(int? value) {
    if (value == null) return '';
    return '#${value.toRadixString(16).padLeft(8, '0')}';
  }

  /// 同时同步阅读时长与阅读位置。
  Future<ReaMicroSyncResult> syncAll() async {
    final durations = await syncReadingSessions();
    final progress = await syncProgress();
    final marks = await syncMarks();
    final messages = <String>{
      durations.message,
      progress.message,
      marks.message,
    }.where((message) => message.trim().isNotEmpty).toList(growable: false);
    return ReaMicroSyncResult(
      success: durations.success && progress.success && marks.success,
      message: messages.join('；'),
      requests: durations.requests + progress.requests + marks.requests,
      durationSeconds: durations.durationSeconds,
    );
  }

  /// 上报本地待同步位置，并按需拉取云端较新的位置。
  Future<ReaMicroSyncResult> syncProgress({bool pullCloud = true}) async {
    final token = _token;
    final store = _rawProgressStore;
    if (token == null) {
      return const ReaMicroSyncResult(success: false, message: '请先登录阅微账号');
    }
    if (store == null) {
      return const ReaMicroSyncResult(success: false, message: '本地阅读进度暂不可用');
    }
    if (_syncingProgress) {
      return const ReaMicroSyncResult(success: false, message: '正在同步阅读进度，请稍后');
    }
    if (_links.isEmpty) {
      return const ReaMicroSyncResult(success: false, message: '尚未关联任何阅微书籍');
    }
    _syncingProgress = true;
    _error = null;
    _notify();
    var uploaded = 0;
    var pulled = 0;
    final handledBooks = <String>{};
    String? failure;
    try {
      for (final entry in List<MapEntry<String, ReaMicroProgressState>>.of(
        _progressStates.entries,
      )) {
        if (_token != token) break;
        final state = entry.value;
        if (!state.dirty) continue;
        final link = _links[entry.key];
        if (link == null) continue;
        if (state.cfi.trim().isEmpty) {
          _progressStates[entry.key] = state.copyWith(dirty: false);
          continue;
        }
        try {
          if (pullCloud) {
            final remote = await _api.fetchReadProgress(
              token,
              cloudBookId: link.cloudBookId.toString(),
            );
            if (remote != null && remote.usable) {
              if (remote.cfi == state.cfi) {
                _progressStates[entry.key] = state.copyWith(
                  dirty: false,
                  remoteUpdatedAt: remote.readFinishTime > state.remoteUpdatedAt
                      ? remote.readFinishTime
                      : state.remoteUpdatedAt,
                );
                handledBooks.add(entry.key);
                continue;
              }
              if (remote.readFinishTime > state.localUpdatedAt) {
                final applied = await _applyRemoteProgress(
                  entry.key,
                  cfi: remote.cfi,
                  chapterName: remote.chapterName,
                  progress: remote.progress,
                  updatedAt: remote.readFinishTime,
                  queueCloud: false,
                );
                if (applied) {
                  handledBooks.add(entry.key);
                  pulled += 1;
                  continue;
                }
              }
            }
          }
          await _uploadProgressState(token, entry.key, state, link);
          handledBooks.add(entry.key);
          uploaded += 1;
        } catch (error) {
          failure ??= _messageOf(error);
          if (error is ReaMicroException && error.unauthorized) {
            await _handleError(error);
            break;
          }
        }
      }
      await _persistProgressStatesNow();

      if (pullCloud && failure == null && _token == token) {
        for (final entry in Map<String, ReaMicroBookLink>.of(_links).entries) {
          final bookId = entry.key;
          final link = entry.value;
          final state = _progressStates[bookId];
          if (state?.dirty == true) continue;
          if (handledBooks.contains(bookId)) continue;
          try {
            final remote = await _api.fetchReadProgress(
              token,
              cloudBookId: link.cloudBookId.toString(),
            );
            if (remote == null || !remote.usable) {
              if (state != null && state.cfi.trim().isNotEmpty) {
                try {
                  await _uploadProgressState(token, bookId, state, link);
                  uploaded += 1;
                } catch (error) {
                  failure ??= _messageOf(error);
                  if (error is ReaMicroException && error.unauthorized) {
                    await _handleError(error);
                    break;
                  }
                }
              }
              continue;
            }
            final localUpdatedAt = state?.localUpdatedAt ?? 0;
            if (state?.cfi == remote.cfi) {
              if (remote.readFinishTime > (state?.remoteUpdatedAt ?? 0)) {
                _progressStates[bookId] = state!.copyWith(
                  remoteUpdatedAt: remote.readFinishTime,
                );
              }
              continue;
            }
            if (remote.readFinishTime <= 0 &&
                state != null &&
                state.cfi.isNotEmpty) {
              continue;
            }
            if (remote.readFinishTime > 0 &&
                remote.readFinishTime <= localUpdatedAt) {
              if (state != null &&
                  state.cfi.trim().isNotEmpty &&
                  state.cfi != remote.cfi) {
                try {
                  await _uploadProgressState(token, bookId, state, link);
                  uploaded += 1;
                } catch (error) {
                  failure ??= _messageOf(error);
                  if (error is ReaMicroException && error.unauthorized) {
                    await _handleError(error);
                    break;
                  }
                }
              }
              continue;
            }
            final applied = await _applyRemoteProgress(
              bookId,
              cfi: remote.cfi,
              chapterName: remote.chapterName,
              progress: remote.progress,
              updatedAt: remote.readFinishTime,
              queueCloud: false,
            );
            if (applied) pulled += 1;
          } catch (error) {
            failure ??= _messageOf(error);
            if (error is ReaMicroException && error.unauthorized) {
              await _handleError(error);
              break;
            }
          }
        }
      }
      await _persistProgressStatesNow();
    } finally {
      _syncingProgress = false;
    }

    if (failure != null) _error = failure;
    final requests = uploaded + pulled;
    final message = failure == null
        ? requests == 0
              ? '阅读进度已是最新'
              : '已上报 $uploaded 本、同步 $pulled 本阅读进度'
        : requests == 0
        ? failure
        : '已上报 $uploaded 本、同步 $pulled 本，其余失败：$failure';
    _notice = message;
    _notify();
    return ReaMicroSyncResult(
      success: failure == null || requests > 0,
      message: message,
      requests: requests,
    );
  }

  /// 上报一本书的当前位置，并在成功后清除待上报标记。
  Future<void> _uploadProgressState(
    String token,
    String bookId,
    ReaMicroProgressState state,
    ReaMicroBookLink link,
  ) async {
    await _api.updateReadProgress(
      token,
      cloudBookId: link.cloudBookId,
      cfi: state.cfi,
      chapterName: _chapterNameOf(state),
      progress: state.progress,
    );
    _progressStates[bookId] = state.copyWith(
      dirty: false,
      uploadedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 从局域网设备下载缺失图书并合并阅读位置。
  Future<String> syncWithLanPeer(ReaMicroLanSyncPeer peer) async {
    if (_user == null) {
      throw const ReaMicroException('请先登录阅微账号');
    }
    if (_lanSyncing) {
      return '正在与局域网设备同步，请稍后';
    }
    _lanSyncing = true;
    _lanMessage = null;
    _error = null;
    _notify();
    try {
      final manifest = await _lan.fetchManifest(peer);
      if (manifest.userId != _user!.id) {
        throw const ReaMicroException('该设备与当前阅微账号不一致');
      }
      final device = peer.deviceName.isNotEmpty
          ? peer.deviceName
          : peer.nickname.isNotEmpty
          ? peer.nickname
          : '局域网设备';
      final nextLinks = Map<String, ReaMicroBookLink>.of(_links);
      var linksChanged = false;
      var imported = 0;
      var downloadFailed = 0;
      var applied = 0;
      var skipped = 0;
      var failed = 0;
      var unmatched = 0;
      var mergedMarks = 0;
      for (final remote in manifest.books) {
        var localBook = await _matchLanBook(remote);
        if (localBook == null && remote.hasFiles && remote.title.isNotEmpty) {
          _lanMessage = '正在从 $device 下载《${remote.title}》…';
          _notify();
          try {
            final bytes = await _lan.downloadBookArchive(peer, remote);
            final importedBook = await _library.importBytes(
              bytes,
              fallbackTitle: remote.title,
            );
            localBook = importedBook;
            imported += 1;
          } catch (error) {
            downloadFailed += 1;
            _lanMessage = '《${remote.title}》文件下载失败：${_messageOf(error)}';
            _notify();
          }
        }
        if (localBook == null) {
          unmatched += 1;
          continue;
        }
        final bookId = localBook.id;
        if (remote.cloudId > 0 && !nextLinks.containsKey(bookId)) {
          nextLinks[bookId] = ReaMicroBookLink(
            cloudBookId: remote.cloudId,
            name: remote.title,
            author: remote.author,
            linkedAt: DateTime.now(),
          );
          _links = nextLinks;
          linksChanged = true;
          await _seedProgressStatesForBook(bookId, markDirty: false);
        }
        mergedMarks += await _mergeLanMarks(bookId, remote.marks);
        if (!remote.usable) continue;
        final state = _progressStates[bookId];
        if (state?.dirty == true) {
          skipped += 1;
          continue;
        }
        if (remote.updatedAt > 0 &&
            remote.updatedAt <= (state?.remoteUpdatedAt ?? 0)) {
          skipped += 1;
          continue;
        }
        if (remote.updatedAt == 0 &&
            state != null &&
            state.cfi.isNotEmpty &&
            state.cfi != remote.cfi) {
          skipped += 1;
          continue;
        }
        if (state?.cfi == remote.cfi) {
          _progressStates[bookId] = state!.copyWith(
            remoteUpdatedAt: remote.updatedAt,
          );
          skipped += 1;
          continue;
        }
        final ok = await _applyRemoteProgress(
          bookId,
          cfi: remote.cfi,
          chapterName: remote.chapterName,
          progress: remote.progress,
          updatedAt: remote.updatedAt,
          finished: remote.finished,
          queueCloud: true,
        );
        if (ok) {
          applied += 1;
        } else {
          failed += 1;
        }
      }
      if (linksChanged) {
        _links = nextLinks;
        await _store.saveLinks(nextLinks);
      }
      await _persistProgressStatesNow();
      final hints = <String>[
        if (unmatched > 0) '$unmatched 本未匹配本地书籍',
        if (downloadFailed > 0) '$downloadFailed 本文件下载失败',
        if (mergedMarks > 0) '合并 $mergedMarks 条标注',
      ];
      final hintText = hints.isEmpty ? '' : '，${hints.join('、')}';
      final progressText = failed == 0
          ? applied == 0
                ? '没有新的阅读位置'
                : '合并 $applied 本阅读位置'
          : '合并 $applied 本，$failed 本位置不可用';
      final message = imported > 0
          ? '已从 $device 下载 $imported 本图书，$progressText$hintText'
          : failed == 0
          ? applied == 0
                ? unmatched > 0 || downloadFailed > 0
                      ? '与 $device 没有可合并的阅读位置$hintText'
                      : '与 $device 没有新的阅读位置$hintText'
                : '已从 $device 合并 $applied 本阅读位置$hintText'
          : '已从 $device 合并 $applied 本，$failed 本位置不可用$hintText';
      _lanMessage = message;
      if (applied > 0 || imported > 0 || mergedMarks > 0) {
        if (_links.isNotEmpty) {
          scheduleProgressSync(delay: const Duration(seconds: 1));
          if (mergedMarks > 0) {
            scheduleReadingSync(delay: const Duration(seconds: 2));
          }
        }
      } else if (skipped > 0) {
        _lanMessage = '$message（$skipped 本保留本地较新位置）';
      }
      return _lanMessage!;
    } catch (error) {
      _lanMessage = _messageOf(error);
      rethrow;
    } finally {
      _lanSyncing = false;
      _notify();
    }
  }

  /// 合并局域网清单中的划线与想法，按更新时间保留较新内容。
  Future<int> _mergeLanMarks(String bookId, List<ReaMicroLanMark> marks) async {
    if (marks.isEmpty) return 0;
    final annotations = List<ReaderAnnotation>.of(
      await _library.listBookAnnotations(bookId),
    );
    var merged = 0;
    for (final remote in marks) {
      if (!remote.usable) continue;
      final createdAt = remote.createdAt > 0
          ? remote.createdAt
          : remote.updatedAt > 0
          ? remote.updatedAt
          : DateTime.now().millisecondsSinceEpoch;
      final updatedAt = remote.updatedAt > 0 ? remote.updatedAt : createdAt;
      var existingIndex = -1;
      for (var index = 0; index < annotations.length; index++) {
        final annotation = annotations[index];
        if (annotation.type.storageValue != remote.kind) continue;
        if (annotation.startCfi != remote.startCfi) continue;
        if (remote.endCfi.isNotEmpty && annotation.endCfi != remote.endCfi) {
          continue;
        }
        existingIndex = index;
        break;
      }
      final existing = existingIndex < 0 ? null : annotations[existingIndex];
      if (existing != null &&
          existing.updatedAt.millisecondsSinceEpoch >= updatedAt) {
        continue;
      }
      final annotation = ReaderAnnotation(
        id: existing?.id ?? _lanMarkId(remote),
        type: ReaderAnnotationType.fromStorage(remote.kind),
        startCfi: remote.startCfi,
        endCfi: remote.endCfi.isEmpty ? remote.startCfi : remote.endCfi,
        quote: remote.quote,
        color: _colorFromRemote(remote.color),
        style: ReaderAnnotationStyle.fromStorage(remote.style),
        note: remote.note.trim().isEmpty ? null : remote.note,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      );
      await _library.importBookAnnotation(bookId, annotation);
      if (existingIndex < 0) {
        annotations.add(annotation);
      } else {
        annotations[existingIndex] = annotation;
      }
      merged += 1;
    }
    return merged;
  }

  String _lanMarkId(ReaMicroLanMark mark) {
    if (mark.cloudId > 0) return 'mark-lan-${mark.cloudId}';
    return 'mark-lan-${mark.kind}-${mark.startCfi}-${mark.endCfi}';
  }

  /// 在本地书库中定位阅微设备上报的书。
  ///
  /// 阅微的书籍 UUID 与 Spectacular 的本地书籍标识来源不同，不能只按 UUID
  /// 查找；依次尝试本地标识、已有云端关联和唯一的书名加作者匹配。
  Future<BookEntry?> _matchLanBook(ReaMicroLanBookProgress remote) async {
    final direct = await _library.bookById(remote.uuid);
    if (direct != null) return direct;
    if (remote.cloudId > 0) {
      for (final entry in _links.entries) {
        if (entry.value.cloudBookId != remote.cloudId) continue;
        final linked = await _library.bookById(entry.key);
        if (linked != null) return linked;
      }
    }
    final title = _normalizeBookText(remote.title);
    if (title.isEmpty) return null;
    final author = _normalizeBookText(remote.author);
    final matches = <BookEntry>[];
    for (final book in await _library.list()) {
      if (_normalizeBookText(book.title) != title) continue;
      if (author.isNotEmpty && _normalizeBookText(book.author) != author) {
        continue;
      }
      final existing = _links[book.id];
      if (existing != null &&
          remote.cloudId > 0 &&
          existing.cloudBookId != remote.cloudId) {
        continue;
      }
      matches.add(book);
    }
    return matches.length == 1 ? matches.single : null;
  }

  /// 扫描局域网授权登录设备。
  Future<List<ReaMicroLanLoginDevice>> discoverLanLoginDevices() async {
    if (_lanScanning) return _lanLoginDevices;
    _lanScanning = true;
    _error = null;
    _notify();
    try {
      _lanLoginDevices = await _lan.discoverLoginDevices(
        excludeUserId: _user?.id.toString(),
      );
      _lanMessage = _lanLoginDevices.isEmpty
          ? '未发现开启局域网登录的阅微设备'
          : '发现 ${_lanLoginDevices.length} 台可登录设备';
      return _lanLoginDevices;
    } catch (error) {
      _error = _messageOf(error);
      rethrow;
    } finally {
      _lanScanning = false;
      _notify();
    }
  }

  /// 使用局域网设备返回的令牌登录。
  Future<bool> loginWithLanDevice(ReaMicroLanLoginDevice device) async {
    if (_lanLoggingIn) return false;
    _lanLoggingIn = true;
    _error = null;
    _notice = null;
    _lanMessage = null;
    _notify();
    try {
      final token = await _lan.login(device);
      final user = await _api.fetchUser(token);
      _token = token;
      await _store.saveToken(token);
      await _resetAccountSyncState();
      _user = user;
      await _store.saveCachedUser(user);
      _links = await _store.loadLinks();
      _lastRefreshAt = DateTime.now();
      await _seedProgressStatesFromLocal(markDirty: false);
      _notice = '已通过局域网授权登录';
      await _refreshInternal(token, silent: true);
      scheduleReadingSync(delay: const Duration(seconds: 2));
      return true;
    } catch (error) {
      await _handleError(error);
      return false;
    } finally {
      _lanLoggingIn = false;
      _notify();
    }
  }

  /// 扫描局域网同步设备。
  Future<List<ReaMicroLanSyncPeer>> discoverLanSyncPeers() async {
    if (_lanScanning) return _lanSyncPeers;
    _lanScanning = true;
    _error = null;
    _notify();
    try {
      final peers = await _lan.discoverSyncPeers(excludeDeviceId: _deviceId);
      final userId = _user?.id;
      _lanSyncPeers = userId == null
          ? peers
          : peers
                .where((peer) => peer.userId == userId)
                .toList(growable: false);
      _lanMessage = _lanSyncPeers.isEmpty
          ? '未发现同账号的局域网设备'
          : '发现 ${_lanSyncPeers.length} 台同账号设备';
      return _lanSyncPeers;
    } catch (error) {
      _error = _messageOf(error);
      rethrow;
    } finally {
      _lanScanning = false;
      _notify();
    }
  }

  void _onLocalProgressSaved(String bookId, ReaderProgress progress) {
    if (_disposed) return;
    final existing = _progressStates[bookId];
    final cfi = progress.cfi?.trim() ?? '';
    if (cfi.isEmpty) return;
    final linked = _links.containsKey(bookId);
    _progressStates[bookId] = ReaMicroProgressState(
      cfi: cfi,
      chapterName: progress.chapterTitle?.trim().isNotEmpty == true
          ? progress.chapterTitle!.trim()
          : existing?.chapterName ?? '',
      progress: progress.readingPercent ?? existing?.progress ?? 0,
      localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      remoteUpdatedAt: existing?.remoteUpdatedAt ?? 0,
      uploadedAt: existing?.uploadedAt ?? 0,
      dirty: linked,
    );
    _persistProgressStates();
    if (linked && _token != null) {
      scheduleProgressSync();
    }
  }

  Future<void> _seedProgressStatesFromLocal({bool markDirty = true}) async {
    for (final bookId in _links.keys.toList(growable: false)) {
      await _seedProgressStatesForBook(bookId, markDirty: markDirty);
    }
    await _persistProgressStatesNow();
  }

  Future<void> _seedProgressStatesForBook(
    String bookId, {
    bool markDirty = true,
  }) async {
    final store = _rawProgressStore;
    if (store == null) return;
    final progress = await store.load(bookId);
    final cfi = progress?.cfi?.trim() ?? '';
    if (cfi.isEmpty) return;
    final existing = _progressStates[bookId];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing != null && existing.cfi == cfi) {
      if (markDirty && !existing.dirty) {
        _progressStates[bookId] = existing.copyWith(
          dirty: true,
          localUpdatedAt: now,
        );
        _persistProgressStates();
      }
      return;
    }
    _progressStates[bookId] = ReaMicroProgressState(
      cfi: cfi,
      chapterName: progress?.chapterTitle?.trim().isNotEmpty == true
          ? progress!.chapterTitle!.trim()
          : existing?.chapterName ?? '',
      progress: progress?.readingPercent ?? existing?.progress ?? 0,
      localUpdatedAt: markDirty ? now : existing?.localUpdatedAt ?? 0,
      remoteUpdatedAt: existing?.remoteUpdatedAt ?? 0,
      uploadedAt: existing?.uploadedAt ?? 0,
      dirty: markDirty,
    );
    _persistProgressStates();
  }

  Future<bool> _applyRemoteProgress(
    String bookId, {
    required String cfi,
    required String chapterName,
    required double progress,
    required int updatedAt,
    required bool queueCloud,
    bool finished = false,
  }) async {
    final store = _rawProgressStore;
    if (store == null) return false;
    final book = await _library.bookById(bookId);
    if (book == null) return false;
    final revision = book.contentRevision?.trim() ?? '';
    if (revision.isEmpty) return false;
    final parsed = EpubCfi.parse(cfi);
    if (parsed == null) return false;
    final spineIndex = spineIndexOfCfi(parsed);
    if (spineIndex == null || spineIndex < 0) return false;
    final spineCount = book.spineCount ?? 0;
    if (spineCount > 0 && spineIndex >= spineCount) return false;
    final remoteProgress = progress.clamp(0.0, 1.0).toDouble();
    final mapped = await mapReaMicroProgressToBook(
      sourcePath: book.filePath,
      cfi: cfi,
      progress: remoteProgress,
    );
    final localCfi = mapped?.cfi ?? cfi;
    final localSpineIndex = mapped?.spineIndex ?? spineIndex;
    final normalized = mapped?.progress ?? remoteProgress;
    try {
      await store.save(
        bookId,
        ReaderProgress(
          spineIndex: localSpineIndex,
          pageIndex: 0,
          finished: finished,
          cfi: localCfi,
          contentRevision: revision,
          readingPercent: normalized,
          chapterTitle: chapterName.trim().isEmpty ? null : chapterName.trim(),
        ),
      );
    } on Object {
      return false;
    }
    final existing = _progressStates[bookId];
    final timestamp = updatedAt > 0
        ? updatedAt
        : DateTime.now().millisecondsSinceEpoch;
    _progressStates[bookId] = ReaMicroProgressState(
      cfi: localCfi,
      chapterName: chapterName.trim().isEmpty
          ? existing?.chapterName ?? ''
          : chapterName.trim(),
      progress: normalized,
      localUpdatedAt: timestamp,
      remoteUpdatedAt: updatedAt > 0
          ? updatedAt
          : existing?.remoteUpdatedAt ?? 0,
      uploadedAt: existing?.uploadedAt ?? 0,
      dirty: queueCloud && _links.containsKey(bookId),
    );
    return true;
  }

  String _chapterNameOf(ReaMicroProgressState state) {
    final chapter = state.chapterName.trim();
    return chapter.isEmpty ? '阅读位置' : chapter;
  }

  void _persistProgressStates() {
    _enqueueProgressPersist();
  }

  Future<void> _persistProgressStatesNow() => _enqueueProgressPersist();

  Future<void> _enqueueProgressPersist() {
    final snapshot = Map<String, ReaMicroProgressState>.of(_progressStates);
    _progressPersist = _progressPersist
        .then((_) => _store.saveProgressStates(snapshot))
        .catchError((Object _) {});
    return _progressPersist;
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
    _stopCloudAutoSync();
    if (_cloudAsPrimary) {
      _cloudAsPrimary = false;
      await _store.saveCloudPrimary(false);
    }
    await _store.clearAuth();
    await _resetAccountSyncState();
    _token = null;
    _user = null;
    _chart = const <ReaMicroChartPoint>[];
    _lastRefreshAt = null;
    _cloudStats = null;
    _cloudStatsAt = null;
    _cloudStatsError = null;
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
    _progressSyncTimer?.cancel();
    _cloudSyncTimer?.cancel();
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

String _normalizeBookText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\u3000《》〈〉]'), '').trim();
