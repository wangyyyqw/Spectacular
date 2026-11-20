import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import '../storage/reading_session_store.dart';
import 'rea_micro_api_client.dart';
import 'rea_micro_github.dart';
import 'rea_micro_lan.dart';
import 'rea_micro_lan_server.dart';
import 'rea_micro_models.dart';
import 'rea_micro_progress_mapping.dart';
import 'rea_micro_progress_store.dart';
import 'rea_micro_s3.dart';
import 'rea_micro_store.dart';
import 'rea_micro_webdav.dart';

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
    ReaMicroLanLoginServer? lanLoginServer,
    bool enableLanLoginServer = true,
    ReaMicroS3Client Function(ReaMicroS3Config config)? s3ClientFactory,
  }) : _library = library,
       _api = api ?? ReaMicroApiClient(),
       _store = store ?? ReaMicroStore(library),
       _rawProgressStore = progressStore,
       // ignore: prefer_initializing_formals
       _s3ClientFactory = s3ClientFactory,
       _lanLoginServerEnabled = enableLanLoginServer,
       _lanLoginServer = lanLoginServer ?? ReaMicroLanLoginServer(),
       _lan = lan ?? ReaMicroLanClient() {
    _trackedProgressStore = progressStore == null
        ? null
        : ReaMicroTrackingProgressStore(progressStore, _onLocalProgressSaved);
    _lanLoginServer.onRequestsChanged = _onLanLoginRequestsChanged;
  }

  final LibraryStore _library;
  final ReaMicroApi _api;
  final ReaMicroStore _store;
  final ReaderProgressStore? _rawProgressStore;
  final ReaMicroLanClient _lan;
  final ReaMicroLanLoginServer _lanLoginServer;
  final bool _lanLoginServerEnabled;
  final ReaMicroS3Client Function(ReaMicroS3Config config)? _s3ClientFactory;
  late final ReaderProgressStore? _trackedProgressStore;

  String? _token;
  ReaMicroUser? _user;
  List<ReaMicroChartPoint> _chart = const <ReaMicroChartPoint>[];
  Map<String, ReaMicroBookLink> _links = <String, ReaMicroBookLink>{};
  Map<String, ReaMicroBookSyncIdentity> _syncBooks =
      <String, ReaMicroBookSyncIdentity>{};
  final Map<String, Future<ReaMicroBookSyncIdentity?>> _identityRequests =
      <String, Future<ReaMicroBookSyncIdentity?>>{};
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
  List<ReaMicroLanLoginRequest> _lanLoginRequests =
      const <ReaMicroLanLoginRequest>[];
  String? _lanAuthorizationError;
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
  Map<String, String> _s3LocalBookUuids = <String, String>{};
  Set<String> _s3PendingDeletions = <String>{};
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

  /// 本地书籍的阅微阅读数据身份；不要求已经公开关联。
  Map<String, ReaMicroBookSyncIdentity> get syncBooks =>
      Map<String, ReaMicroBookSyncIdentity>.unmodifiable(_syncBooks);

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

  /// 其他设备发往本机、等待批准的登录申请。
  List<ReaMicroLanLoginRequest> get lanLoginRequests => _lanLoginRequests;

  /// 本机局域网授权服务是否正在监听。
  bool get lanAuthorizationRunning => _lanLoginServer.running;

  /// 本机局域网授权服务错误。
  String? get lanAuthorizationError => _lanAuthorizationError;

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
    _syncBooks = await _store.loadSyncBooks();
    _lastSyncAt = await _store.loadLastSyncAt();
    _progressStates = await _store.loadProgressStates();
    _markIds = await _store.loadMarkIds();
    _deviceId = await _store.loadOrCreateDeviceId();
    _cloudAsPrimary = await _store.loadCloudPrimary();
    _s3Config = await _store.loadS3Config();
    _s3BookmarkBases = await _store.loadS3BookmarkBases();
    _s3LocalBookUuids = await _store.loadS3LocalBookUuids();
    _s3PendingDeletions = await _store.loadS3PendingDeletions();
    _s3LastSyncAt = await _store.loadS3LastSyncAt();
    if (_token == null && _cloudAsPrimary) {
      _cloudAsPrimary = false;
      await _store.saveCloudPrimary(false);
    }
    _notify();
    if (_token != null) {
      await refresh(silent: true);
      if (!_disposed && _token != null) {
        await _startLanAuthorization();
        await _restoreCloudS3Config(silent: true);
        if (_cloudAsPrimary) {
          _startCloudAutoSync();
          await _syncCloudNow();
        } else {
          await _seedProgressStatesFromLocal(markDirty: false);
          scheduleReadingSync(delay: const Duration(seconds: 5));
          scheduleProgressSync(delay: const Duration(seconds: 7));
        }
        if (!_cloudAsPrimary && _s3Config != null) {
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
      await _clearS3BookState();
    } else {
      await _store.saveS3Config(_s3Config!);
      await _clearS3BookState();
    }
    _notify();
  }

  /// 清除 S3 同步配置。
  Future<void> clearS3Config() async {
    _s3Config = null;
    _s3Message = null;
    _s3SyncTimer?.cancel();
    await _store.clearS3Config();
    await _clearS3BookState();
    _notify();
  }

  /// 读取阅微账号保存的 S3 配置并解密。
  Future<ReaMicroS3CloudConfig> fetchCloudS3Config() async {
    final token = _token;
    final user = _user;
    if (token == null || user == null) {
      throw const ReaMicroException('请先登录阅微账号');
    }
    try {
      final result = await _api.fetchS3CloudConfig(token);
      final config = result.encryptedConfig.trim().isEmpty
          ? null
          : ReaMicroS3ConfigCrypto.decrypt(result.encryptedConfig, user.id);
      return ReaMicroS3CloudConfig(
        enabled: result.enabled,
        encryptedConfig: result.encryptedConfig,
        config: config,
      );
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 加密保存 S3 配置到阅微账号；[enabled] 为假时移除云端配置。
  Future<void> saveCloudS3Config(
    ReaMicroS3Config config, {
    required bool enabled,
  }) async {
    final token = _token;
    final user = _user;
    if (token == null || user == null) {
      throw const ReaMicroException('请先登录阅微账号');
    }
    if (enabled && !config.usable) {
      throw const ReaMicroException('S3 配置不完整，无法保存到阅微账号');
    }
    try {
      await _api.updateS3CloudConfig(
        token,
        enabled: enabled,
        encryptedConfig: enabled
            ? ReaMicroS3ConfigCrypto.encrypt(config, user.id)
            : '',
      );
      _s3Message = enabled ? '已加密保存到阅微账号' : '已移除阅微账号中的 S3 配置';
      _notify();
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 本机没有 S3 配置时，从阅微账号恢复已加密保存的配置。
  Future<void> _restoreCloudS3Config({required bool silent}) async {
    if (_s3Config != null || !signedIn) return;
    try {
      final cloud = await fetchCloudS3Config();
      final config = cloud.config;
      if (!cloud.enabled || config == null || !config.usable) return;
      _s3Config = config;
      await _store.saveS3Config(config);
      await _clearS3BookState();
      if (!silent) {
        _s3Message = '已从阅微账号恢复 S3 同步配置';
        _notify();
      }
    } on ReaMicroException catch (error) {
      if (!silent || error.unauthorized) await _handleError(error);
    }
  }

  /// 读取阅微对象存储配额。
  Future<ReaMicroStorageQuota> fetchStorageQuota() async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchStorageQuota(token);
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 使用积分扩容阅微对象存储；[credit] 必须为 60 的整数倍。
  Future<ReaMicroStorageQuota> expandStorageQuota({required int credit}) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    if (credit <= 0 || credit % 60 != 0) {
      throw const ReaMicroException('扩容积分必须为 60 的整数倍');
    }
    try {
      final quota = await _api.expandStorageQuota(token, credit: credit);
      _s3Message = '对象存储已扩容到 ${quota.capacityGib} GiB';
      _notify();
      return quota;
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取阅微对象存储积分流水。
  Future<ReaMicroCreditLedgerPage> fetchCreditLedger({
    int page = 1,
    int pageSize = 20,
  }) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchCreditLedger(
        token,
        page: page,
        pageSize: pageSize,
      );
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取阅微离线朗读引擎与官方音色目录。
  Future<ReaMicroTtsCatalog> fetchTtsCatalog() async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchTtsVoices(token);
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取指定周期的书籍阅读记录。
  Future<List<ReaMicroBookRecord>> loadBookRecords(
    ReaMicroRecordPeriod period,
    DateTime anchor,
  ) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await switch (period) {
        ReaMicroRecordPeriod.week => _api.fetchBookRecordsByWeek(
          token,
          date: anchor,
        ),
        ReaMicroRecordPeriod.month => _api.fetchBookRecordsByMonth(
          token,
          year: anchor.year,
          month: anchor.month,
        ),
        ReaMicroRecordPeriod.year => _api.fetchBookRecordsByYear(
          token,
          year: anchor.year,
        ),
      };
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取账号有划线或想法的书籍。
  Future<List<ReaMicroMarkBook>> loadMarkBooks() async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchMarkBooks(token);
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取一本书在阅微的划线或想法，供书评页直接展示云端笔记。
  Future<List<ReaMicroMark>> loadBookMarks({
    required int cloudBookId,
    int bookId = 0,
  }) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    final cloudId = cloudBookId > 0 ? cloudBookId.toString() : '';
    final internalId = bookId > 0 ? bookId.toString() : '';
    if (cloudId.isEmpty && internalId.isEmpty) {
      return const <ReaMicroMark>[];
    }
    try {
      final ids = <String>[
        if (cloudId.isNotEmpty) cloudId,
        if (internalId.isNotEmpty && internalId != cloudId) internalId,
      ];
      for (final id in ids) {
        final marks = await _api.fetchMarks(token, bookId: id);
        if (marks.isNotEmpty) return marks;
      }
      final all = await _api.fetchMarks(token);
      return <ReaMicroMark>[
        for (final mark in all)
          if (ids.contains(mark.bookId.trim())) mark,
      ];
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 从阅微阅读记录中隐藏一本书；[bookId] 为阅微内部书籍标识。
  Future<ReaMicroActionResult> hideBookRecord(int bookId) async {
    final token = _token;
    if (token == null) {
      return const ReaMicroActionResult(
        success: false,
        message: '请先登录阅微账号',
        unauthorized: true,
      );
    }
    if (bookId <= 0) {
      return const ReaMicroActionResult(success: false, message: '当前记录无法隐藏');
    }
    try {
      await _api.hideBookRecord(token, bookId: bookId);
      return const ReaMicroActionResult(success: true, message: '已从阅读记录中隐藏');
    } catch (error) {
      await _handleError(error);
      return ReaMicroActionResult(
        success: false,
        message: _messageOf(error),
        unauthorized: error is ReaMicroException && error.unauthorized,
      );
    }
  }

  /// 读取当前账号对一条书评的互动状态。
  Future<ReaMicroReviewActionState> loadReviewAction(int reviewId) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    if (reviewId <= 0) return ReaMicroReviewActionState.empty;
    try {
      return await _api.checkReviewAction(token, reviewId: reviewId);
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取一条书评的互动用户。
  Future<ReaMicroReviewActorPage> loadReviewActors(
    int reviewId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    if (reviewId <= 0) {
      return const ReaMicroReviewActorPage(
        items: <ReaMicroReviewActor>[],
        total: 0,
      );
    }
    try {
      return await _api.fetchReviewActors(
        token,
        reviewId: reviewId,
        page: page,
        pageSize: pageSize,
      );
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 读取书评流；[cloudBookId] 为空时读取全站书评。
  Future<List<ReaMicroBookReview>> loadReviewFlow({
    int? cloudBookId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchReviewFlow(
        token,
        cloudBookId: cloudBookId,
        page: page,
        pageSize: pageSize,
      );
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 点赞或取消点赞一条书评。
  Future<ReaMicroActionResult> setReviewLiked(int reviewId, bool liked) async {
    final token = _token;
    if (token == null) {
      return const ReaMicroActionResult(
        success: false,
        message: '请先登录阅微账号',
        unauthorized: true,
      );
    }
    if (reviewId <= 0) {
      return const ReaMicroActionResult(success: false, message: '书评尚未发布');
    }
    try {
      if (liked) {
        await _api.actReview(token, reviewId: reviewId);
      } else {
        await _api.unactReview(token, reviewId: reviewId);
      }
      return ReaMicroActionResult(
        success: true,
        message: liked ? '已点赞' : '已取消点赞',
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

  Future<void> _clearS3BookmarkBases() async {
    _s3BookmarkBases = <String, String>{};
    await _store.clearS3BookmarkBases();
  }

  Future<void> _clearS3BookState() async {
    await _clearS3BookmarkBases();
    _s3LocalBookUuids = <String, String>{};
    _s3PendingDeletions = <String>{};
    await _store.clearS3LocalBookUuids();
    await _store.clearS3PendingDeletions();
  }

  /// 账号变化后清空与云端标识绑定的同步状态，避免复用上一账号的映射。
  Future<void> _resetAccountSyncState() async {
    _cloudStats = null;
    _cloudStatsAt = null;
    _cloudStatsError = null;
    // 公开版本可跨账号复用，内部用户书标识必须在新账号重新解析或登记。
    _links = {
      for (final entry in _links.entries)
        entry.key: ReaMicroBookLink(
          cloudBookId: entry.value.cloudBookId,
          name: entry.value.name,
          author: entry.value.author,
          publisherId: entry.value.publisherId,
          linkedAt: entry.value.linkedAt,
        ),
    };
    await _store.saveLinks(_links);
    if (_markIds.isNotEmpty) {
      _markIds = <String, int>{};
      await _store.saveMarkIds(_markIds);
    }
    if (_syncBooks.isNotEmpty) {
      _syncBooks = <String, ReaMicroBookSyncIdentity>{};
      await _store.clearSyncBooks();
    }
    await _clearS3BookState();
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
    bool scheduleFollowUp = true,
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
        _s3Message = '请先配置云端同步';
        _notify();
      }
      return null;
    }
    _s3Syncing = true;
    _s3Message = restoreMissing ? '正在读取云端书籍…' : '正在上传本地变更…';
    _error = null;
    _notify();
    try {
      final moteApi = _api is ReaMicroMoteSyncApi
          ? _api as ReaMicroMoteSyncApi
          : null;
      final client =
          _s3ClientFactory?.call(config) ??
          (config.isMote && moteApi != null
              ? ReaMicroMoteS3Client(api: moteApi, token: _token!)
              : config.isWebDav
              ? ReaMicroWebDavClient(config)
              : config.isGitHub
              ? ReaMicroGitHubClient(config)
              : ReaMicroS3HttpClient(config));
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
        localBookUuids: _s3LocalBookUuids,
        pendingDeletions: _s3PendingDeletions,
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
      _s3LocalBookUuids = Map<String, String>.of(result.localBookUuids);
      _s3PendingDeletions = Set<String>.of(result.pendingDeletions);
      await _store.saveS3LocalBookUuids(_s3LocalBookUuids);
      await _store.saveS3PendingDeletions(_s3PendingDeletions);
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
      if (scheduleFollowUp &&
          _links.isNotEmpty &&
          (result.downloaded > 0 ||
              result.links.isNotEmpty ||
              result.syncedBookmarks > 0)) {
        scheduleReadingSync(delay: const Duration(seconds: 2));
      }
      return result;
    } catch (error) {
      _s3Message = '${config.displayName} 同步失败：${_messageOf(error)}';
      return null;
    } finally {
      _s3Syncing = false;
      _notify();
    }
  }

  /// 读取本地书架，供书籍匹配页展示。
  Future<List<BookEntry>> listLocalBooks() => _library.list();

  /// 获取本地书籍的阅微阅读数据身份。
  ///
  /// 公开关联优先；没有关联时使用已保存的登记结果，必要时把本地书登记为
  /// 阅微用户书。登记只建立阅读数据所需的身份，不会关联出版社版本。
  Future<ReaMicroBookSyncIdentity?> _ensureSyncIdentity(
    String bookId, {
    bool createCloudBook = true,
  }) async {
    final link = _links[bookId];
    if (link != null && link.cloudBookId > 0) {
      final existing = _syncBooks[bookId];
      final identity = ReaMicroBookSyncIdentity(
        cloudBookId: link.cloudBookId,
        userBookId: link.userBookId > 0
            ? link.userBookId
            : existing?.cloudBookId == link.cloudBookId
            ? existing!.userBookId
            : 0,
      );
      if (existing?.cloudBookId != identity.cloudBookId ||
          existing?.userBookId != identity.userBookId) {
        _syncBooks = <String, ReaMicroBookSyncIdentity>{
          ..._syncBooks,
          bookId: identity,
        };
        await _store.saveSyncBooks(_syncBooks);
      }
      return identity;
    }
    final existing = _syncBooks[bookId];
    if (existing != null && existing.cloudBookId > 0) return existing;
    final pending = _identityRequests[bookId];
    if (pending != null) return pending;
    final future = _registerSyncIdentity(
      bookId,
      createCloudBook: createCloudBook,
    );
    _identityRequests[bookId] = future;
    try {
      return await future;
    } finally {
      _identityRequests.remove(bookId)?.ignore();
    }
  }

  Future<ReaMicroBookSyncIdentity?> _registerSyncIdentity(
    String bookId, {
    required bool createCloudBook,
  }) async {
    final token = _token;
    if (token == null) return null;
    final book = await _library.bookById(bookId);
    if (book == null) return null;
    final file = File(book.filePath);
    if (!await file.exists()) return null;
    final digest = md5.convert(await file.readAsBytes()).toString();
    final registration = await _api.registerUserBook(
      token,
      name: book.title,
      author: book.author,
      md5: digest,
    );
    var cloudBookId = registration.cloudBookId;
    if (cloudBookId <= 0 && createCloudBook) {
      final created = await _api.createCloudBook(
        token,
        name: book.title,
        author: book.author,
        intro: book.description,
      );
      cloudBookId = created.cloudBookId;
      await _api.relateCloudBook(
        token,
        userBookId: registration.userBookId,
        publisherId: created.publisherId,
      );
    }
    if (cloudBookId <= 0) return null;
    final identity = ReaMicroBookSyncIdentity(
      cloudBookId: cloudBookId,
      userBookId: registration.userBookId,
    );
    _syncBooks = <String, ReaMicroBookSyncIdentity>{
      ..._syncBooks,
      bookId: identity,
    };
    await _store.saveSyncBooks(_syncBooks);
    return identity;
  }

  /// 阅读页关闭后延迟合并同步，避免连续开关书产生重复网络请求。
  void scheduleReadingSync({Duration delay = const Duration(seconds: 3)}) {
    if (_disposed || !signedIn) return;
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
    if (_disposed || !signedIn) return;
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

  void _schedulePendingReadingRetry() {
    if (_disposed || !signedIn) return;
    scheduleReadingSync(delay: const Duration(minutes: 1));
    scheduleProgressSync(delay: const Duration(minutes: 1));
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
      await _seedProgressStatesFromLocal();
      await _restoreCloudS3Config(silent: true);
      if (s3Configured) {
        await syncS3(silent: true, scheduleFollowUp: false);
      }
      await syncAll();
      await refreshCloudStats(force: true, silent: true);
      _notice = '已开启阅微唯一数据源';
      _notify();
    } catch (error) {
      await _handleError(error);
      _notify();
    }
  }

  /// 手动按书名与作者匹配本地书籍和阅微云端阅读记录。
  ///
  /// 仅用于「关联阅微书籍」页的批量匹配按钮，登录或开启唯一数据源时
  /// 不会自动调用。
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
    if (token == null || _loadingCloudStats) return;
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
        monthDate: DateTime(now.year, now.month),
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

  /// 读取指定月份，并拒绝账号切换前的旧响应。
  Future<ReaMicroPeriodStats> loadCloudMonth(DateTime month) async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    final result = await _api.fetchMonthStats(
      token,
      year: month.year,
      month: month.month,
    );
    if (_token != token) throw const ReaMicroException('账号已变更，请重新加载统计');
    return result;
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

  /// 读取当前账号的读完里程碑与书评，不写入控制器缓存。
  Future<List<ReaMicroMilestone>> loadMilestones() async {
    final token = _token;
    if (token == null) throw const ReaMicroException('请先登录阅微账号');
    try {
      return await _api.fetchMilestones(token);
    } on ReaMicroException catch (error) {
      await _handleError(error);
      rethrow;
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
    if (!_disposed && s3Configured) {
      await syncS3(silent: true, scheduleFollowUp: false);
    }
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
      await _restoreCloudS3Config(silent: true);
      await _startLanAuthorization();
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
    _token = null;
    _stopCloudAutoSync();
    await _stopLanAuthorization();
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
    _lanLoginRequests = const <ReaMicroLanLoginRequest>[];
    _lanMessage = null;
    _cloudStats = null;
    _cloudStatsAt = null;
    _cloudStatsError = null;
    _error = null;
    _notice = '已退出阅微账号';
    _notify();
  }

  /// 搜索全部云端书籍候选。
  Future<List<ReaMicroCloudBook>> searchCloudBooks({
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
      return await _api.searchCloudBooks(
        token,
        name: query,
        author: author.trim(),
      );
    } catch (error) {
      await _handleError(error);
      rethrow;
    }
  }

  /// 搜索并整理公开阅读候选；同一出版方的版本归入一组。
  Future<List<ReaMicroPublicReadingGroup>> searchPublicReadingCandidates({
    required String name,
    String author = '',
  }) async {
    final books = await searchCloudBooks(name: name, author: author);
    return groupPublicReadingCandidates(books, title: name, author: author);
  }

  /// 将云端搜索结果整理为按出版方分组的公开阅读候选。
  ///
  /// 无出版方的云端书仍保留在“阅微书库”组中，界面可引导用户新建
  /// 出版书后再完成公开关联。
  List<ReaMicroPublicReadingGroup> groupPublicReadingCandidates(
    List<ReaMicroCloudBook> books, {
    String title = '',
    String author = '',
  }) {
    final queryTitle = _normalizeBookText(title);
    final queryAuthor = _normalizeBookText(author);
    final groups = <String, List<ReaMicroPublicReadingCandidate>>{};
    final groupOrder = <String>[];
    final seen = <String>{};
    for (final book in books) {
      final publishers = book.publishers.isEmpty
          ? const <ReaMicroCloudPublisher?>[null]
          : book.publishers
                .map<ReaMicroCloudPublisher?>((publisher) => publisher)
                .toList(growable: false);
      for (final publisher in publishers) {
        final publisherName = (publisher?.displayName ?? '').trim();
        final groupName = publisherName.isEmpty ? '阅微书库' : publisherName;
        final candidate = ReaMicroPublicReadingCandidate(
          book: book,
          publisher: publisher,
          publisherName: groupName,
        );
        if (!seen.add(candidate.key)) continue;
        groups
            .putIfAbsent(groupName, () {
              groupOrder.add(groupName);
              return <ReaMicroPublicReadingCandidate>[];
            })
            .add(candidate);
      }
    }
    final ordered = <ReaMicroPublicReadingGroup>[];
    for (final name in groupOrder) {
      final candidates = groups[name]!;
      candidates.sort((left, right) {
        final rank = _publicReadingRank(
          left.book,
          queryTitle,
          queryAuthor,
        ).compareTo(_publicReadingRank(right.book, queryTitle, queryAuthor));
        if (rank != 0) return rank;
        return left.book.cloudBookId.compareTo(right.book.cloudBookId);
      });
      ordered.add(
        ReaMicroPublicReadingGroup(
          publisherName: name,
          candidates: List<ReaMicroPublicReadingCandidate>.unmodifiable(
            candidates,
          ),
        ),
      );
    }
    ordered.sort((left, right) {
      final leftRank = _publicReadingRank(
        left.candidates.first.book,
        queryTitle,
        queryAuthor,
      );
      final rightRank = _publicReadingRank(
        right.candidates.first.book,
        queryTitle,
        queryAuthor,
      );
      if (leftRank != rightRank) return leftRank.compareTo(rightRank);
      return groupOrder
          .indexOf(left.publisherName)
          .compareTo(groupOrder.indexOf(right.publisherName));
    });
    return List<ReaMicroPublicReadingGroup>.unmodifiable(ordered);
  }

  /// 关联本地书籍与云端书籍。
  Future<void> linkBook(
    String bookId,
    ReaMicroCloudBook book, {
    int userBookId = 0,
    int publisherId = 0,
  }) async {
    final previous = _links[bookId];
    _links = <String, ReaMicroBookLink>{
      ..._links,
      bookId: ReaMicroBookLink(
        cloudBookId: book.cloudBookId,
        name: book.name,
        author: book.author,
        userBookId: userBookId > 0 ? userBookId : previous?.userBookId ?? 0,
        publisherId: publisherId > 0 ? publisherId : previous?.publisherId ?? 0,
        linkedAt: DateTime.now(),
      ),
    };
    await _store.saveLinks(_links);
    await _seedProgressStatesForBook(bookId);
    _notice = '已关联《${book.name}》';
    _notify();
  }

  /// 将本地书登记到阅微，并建立用户书与出版书的关联。
  ///
  /// [cloudBook] 为空时按本地元数据新建出版书；传入搜索结果时优先复用
  /// 其中的出版方标识，避免同一本书在阅微生成重复条目。
  Future<ReaMicroBookLink> registerAndLinkBook(
    String bookId, {
    ReaMicroCloudBook? cloudBook,
    ReaMicroCloudPublisher? publisher,
  }) async {
    final token = _token;
    if (token == null) {
      throw const ReaMicroException('请先登录阅微账号');
    }
    final book = await _library.bookById(bookId);
    if (book == null) {
      throw const ReaMicroException('本地书籍不存在，请刷新书架');
    }
    final file = File(book.filePath);
    if (!await file.exists()) {
      throw const ReaMicroException('本地书籍文件不存在，无法登记到阅微');
    }
    final digest = md5.convert(await file.readAsBytes()).toString();
    final registration = await _api.registerUserBook(
      token,
      name: book.title,
      author: book.author,
      md5: digest,
    );
    var cloudBookId = cloudBook?.cloudBookId ?? registration.cloudBookId;
    var publisherId = <int>[
      publisher?.publisherId ?? 0,
      registration.publisherId,
      cloudBook?.linkablePublisher?.publisherId ?? 0,
    ].firstWhere((value) => value > 0, orElse: () => 0);
    ReaMicroCloudBook? resolvedCloudBook = cloudBook;
    if (cloudBookId > 0 && publisherId <= 0) {
      try {
        final fetched = await _api.fetchCloudBookInfo(
          token,
          bookId: cloudBookId,
        );
        if (fetched != null) {
          resolvedCloudBook = fetched;
          publisherId = fetched.linkablePublisher?.publisherId ?? 0;
        }
      } catch (_) {
        // 出版方补全失败不应阻断已匹配云端书的阅读数据关联。
      }
    }
    if (cloudBookId <= 0) {
      final created = await _api.createCloudBook(
        token,
        name: resolvedCloudBook?.name ?? book.title,
        author: resolvedCloudBook?.author.isNotEmpty == true
            ? resolvedCloudBook!.author
            : book.author,
        intro: book.description,
      );
      cloudBookId = created.cloudBookId;
      publisherId = created.publisherId;
    }
    if (cloudBookId <= 0) {
      throw const ReaMicroException('阅微未返回云端书标识');
    }
    if (publisherId > 0) {
      await _api.relateCloudBook(
        token,
        userBookId: registration.userBookId,
        publisherId: publisherId,
      );
    }
    final link = ReaMicroBookLink(
      cloudBookId: cloudBookId,
      name: resolvedCloudBook?.name ?? book.title,
      author: resolvedCloudBook?.author ?? book.author,
      userBookId: registration.userBookId,
      publisherId: publisherId,
      linkedAt: DateTime.now(),
    );
    _links = <String, ReaMicroBookLink>{..._links, bookId: link};
    await _store.saveLinks(_links);
    _syncBooks = <String, ReaMicroBookSyncIdentity>{
      ..._syncBooks,
      bookId: ReaMicroBookSyncIdentity(
        cloudBookId: cloudBookId,
        userBookId: registration.userBookId,
      ),
    };
    await _store.saveSyncBooks(_syncBooks);
    await _seedProgressStatesForBook(bookId);
    _notice = '已登记并关联《${link.name}》';
    _notify();
    return link;
  }

  /// 将本地书公开关联到阅微，并立即补传已有阅读数据。
  ///
  /// 关联成功后，即使阅读数据因断网暂时上传失败，也保留本地关联和
  /// 待上报记录，由自动重试在联网后继续补传。
  Future<ReaMicroBookLink> publishBookForPublicReading(
    String bookId, {
    ReaMicroCloudBook? cloudBook,
    ReaMicroCloudPublisher? publisher,
  }) async {
    final link = await registerAndLinkBook(
      bookId,
      cloudBook: cloudBook,
      publisher: publisher,
    );
    final result = await syncAll();
    if (!result.success) {
      _notice = '已公开关联《${link.name}》；阅读数据将在联网后自动补传';
      _notify();
    }
    return link;
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
  ///
  /// 未公开关联的书籍也会上报总阅读时长；只有已取得阅微书籍身份的书
  /// 才附带书籍标识和会话明细，与阅微自身的上报行为一致。
  Future<ReaMicroSyncResult> syncReadingSessions() async {
    final token = _token;
    if (token == null) {
      return const ReaMicroSyncResult(success: false, message: '请先登录阅微账号');
    }
    if (_syncing) {
      return const ReaMicroSyncResult(success: false, message: '正在同步，请稍后');
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
    final readingBookIds = <String, int>{};
    try {
      sessions = await sessionStore.list();
      uploaded = await _store.loadUploadedSessionKeys();
      watermarks = await _store.loadSessionWatermarks();
      final records = await _api.fetchBookRecords(token);
      if (_token != token) {
        _syncing = false;
        _notify();
        return const ReaMicroSyncResult(success: false, message: '账号已变更，同步已停止');
      }
      for (final session in sessions) {
        if (readingBookIds.containsKey(session.bookId)) continue;
        final link = _links[session.bookId];
        final identity = link == null
            ? _syncBooks[session.bookId]
            : ReaMicroBookSyncIdentity(
                cloudBookId: link.cloudBookId,
                userBookId: link.userBookId > 0
                    ? link.userBookId
                    : _syncBooks[session.bookId]?.userBookId ?? 0,
              );
        if (identity == null) continue;
        readingBookIds[session.bookId] = await _resolveReadingBookId(
          token,
          session.bookId,
          identity,
          records: records,
        );
      }
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
      final cloudBookId = readingBookIds[session.bookId] ?? 0;
      for (final portion in _splitSession(session)) {
        if (uploaded.contains(portion.key)) continue;
        final key = '$cloudBookId|${portion.date}';
        final group = groups.putIfAbsent(
          key,
          () => _SyncGroup(cloudBookId: cloudBookId, date: portion.date),
        );
        group.durationSeconds += portion.durationSeconds;
        group.keys.add(portion.key);
        group.bookIds.add(session.bookId);
        if (cloudBookId > 0) {
          group.logs.add(
            ReaMicroReadSessionLog(
              id: 'spectacular-${portion.key}',
              cloudBookId: cloudBookId,
              startedAt: portion.startedAt,
              endedAt: portion.endedAt,
              durationSeconds: portion.durationSeconds,
              recordDay: portion.date,
            ),
          );
        }
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
      if (_token != token) {
        failure = '账号已变更，同步已停止';
        break;
      }
      try {
        await _api.updateReadTimeByDate(
          token,
          <ReaMicroReadTimeEntry>[
            ReaMicroReadTimeEntry(
              cloudBookId: group.cloudBookId,
              date: group.date,
              durationSeconds: group.durationSeconds,
            ),
          ],
          sessionLogs: group.logs,
          sessionAccounting: group.logs.isNotEmpty,
        );
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

    if (_token == token) await saveAdvancedWatermarks();
    if (requests > 0 && _token == token) {
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
    _schedulePendingReadingRetry();
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
      final readingBooks = await _api.fetchBookRecords(token);
      if (_token != token) {
        return const ReaMicroSyncResult(success: false, message: '账号已变更，同步已停止');
      }
      final remoteById = <int, ReaMicroMark>{
        for (final mark in remoteMarks)
          if (mark.id > 0) mark.id: mark,
      };
      final candidateBookIds = <String>{..._links.keys, ..._syncBooks.keys};
      for (final book in await _library.list()) {
        if (candidateBookIds.contains(book.id)) continue;
        final prefix = '${book.id}|';
        if (nextMarkIds.keys.any((key) => key.startsWith(prefix))) {
          candidateBookIds.add(book.id);
          continue;
        }
        try {
          final annotations = await _library.listBookAnnotations(book.id);
          if (annotations.isNotEmpty) candidateBookIds.add(book.id);
        } catch (error) {
          failure ??= _messageOf(error);
        }
      }
      for (final localBookId in candidateBookIds) {
        if (_token != token) break;
        final localBook = await _library.bookById(localBookId);
        if (localBook == null) continue;
        final ReaMicroBookSyncIdentity? identity;
        try {
          identity = await _ensureSyncIdentity(localBookId);
        } catch (error) {
          failure ??= _messageOf(error);
          if (error is ReaMicroException && error.unauthorized) {
            await _handleError(error);
            break;
          }
          continue;
        }
        if (identity == null) continue;
        final int markBookId;
        try {
          markBookId = await _resolveMarkBookId(
            token,
            localBook,
            identity,
            readingBooks,
          );
        } catch (error) {
          failure ??= _messageOf(error);
          continue;
        }
        try {
          await _library.repairBookAnnotationAnchors(localBookId);
        } catch (error) {
          failure ??= _messageOf(error);
        }
        final prefix = '$localBookId|';
        final remoteForBook = <ReaMicroMark>[
          for (final mark in remoteMarks)
            if (_remoteMarkBelongsTo(mark, localBook, markBookId) ||
                nextMarkIds.entries.any(
                  (entry) =>
                      entry.key.startsWith(prefix) && entry.value == mark.id,
                ))
              mark,
        ];
        var localAnnotations = await _library.listBookAnnotations(localBookId);
        final localById = <String, ReaderAnnotation>{
          for (final annotation in localAnnotations) annotation.id: annotation,
        };
        final deletedRemoteIds = <int>{};
        final deletedLocalIds = <String>{};

        for (final key
            in nextMarkIds.keys
                .where((key) => key.startsWith(prefix))
                .toList(growable: false)) {
          final localId = key.substring(prefix.length);
          var remote = remoteById[nextMarkIds[key]];
          final importedId = localId.startsWith('mark-cloud-')
              ? int.tryParse(localId.substring('mark-cloud-'.length))
              : null;
          if (remote != null &&
              importedId != null &&
              importedId != remote.id &&
              !remoteById.containsKey(importedId) &&
              remote.bookId == identity.cloudBookId.toString() &&
              remote.bookId != markBookId.toString()) {
            // 导入标识仍保留原云端 ID；旧版覆盖映射后也可识别删除重传副本。
            deletedRemoteIds.add(remote.id);
            deletedLocalIds.add(localId);
            try {
              await _api.deleteMark(token, id: remote.id);
              remoteById.remove(remote.id);
              remote = null;
              deleted += 1;
            } catch (error) {
              failure ??= _messageOf(error);
              continue;
            }
          }
          if (localById.containsKey(localId)) {
            if (remote != null) continue;
            // 已有云端身份的记录从完整清单消失，表示远端删除。
            // 删除失败时仍阻止本轮上传，保留映射供下次重试。
            deletedLocalIds.add(localId);
            try {
              // 旧版可能已把删除记录重传到公开书库 ID 下；
              // 仅清理与原记录内容和创建时间完全相同的错误副本。
              final local = localById[localId]!;
              for (final legacy in remoteMarks) {
                if (legacy.bookId != identity.cloudBookId.toString() ||
                    deletedRemoteIds.contains(legacy.id) ||
                    legacy.bookId == markBookId.toString() ||
                    legacy.kind != local.type.storageValue ||
                    legacy.createdAt !=
                        local.createdAt.millisecondsSinceEpoch ||
                    legacy.quote != local.quote ||
                    legacy.note != (local.note ?? '')) {
                  continue;
                }
                deletedRemoteIds.add(legacy.id);
                await _api.deleteMark(token, id: legacy.id);
                deleted += 1;
              }
              await _library.removeBookAnnotation(localBookId, localId);
              localById.remove(localId);
              nextMarkIds.remove(key);
              deleted += 1;
            } catch (error) {
              failure ??= _messageOf(error);
            }
            continue;
          }
          // 远端清单是本轮开始时的快照，本地已删除的记录不可再导入。
          if (remote != null) deletedRemoteIds.add(remote.id);
          if (remote != null && remoteForBook.contains(remote)) {
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

        localAnnotations = [
          for (final annotation in localAnnotations)
            if (!deletedLocalIds.contains(annotation.id)) annotation,
        ];
        for (final remote in remoteForBook) {
          if (deletedRemoteIds.contains(remote.id)) continue;
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
          if (deletedLocalIds.contains(annotation.id)) continue;
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
              _markDraftFromLocal(annotation, markBookId, remote: remote),
            );
            nextId ??= await _resolveUploadedMarkId(
              token,
              markBookId: markBookId,
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
      if (_token == token) {
        _markIds = nextMarkIds;
        await _store.saveMarkIds(_markIds);
      }
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
    if (failure != null) _schedulePendingReadingRetry();
    return ReaMicroSyncResult(
      success: failure == null || requests > 0,
      message: message,
      requests: requests,
    );
  }

  Future<int> _resolveMarkBookId(
    String token,
    BookEntry book,
    ReaMicroBookSyncIdentity identity,
    List<ReaMicroBookRecord> records,
  ) async {
    // 阅读接口 bookId 对应阅微内部书籍，不是公开书库 cloudBookId。
    final matches = records
        .where(
          (record) =>
              record.bookId > 0 &&
              record.cloudBookId == identity.cloudBookId &&
              _normalizeBookText(record.name) ==
                  _normalizeBookText(book.title) &&
              _normalizeBookText(record.author) ==
                  _normalizeBookText(book.author),
        )
        .toList();
    if (matches.length == 1) return matches.single.bookId;
    if (matches.length > 1) {
      throw const ReaMicroException('阅微存在多个同版阅读记录，暂不上传阅读数据');
    }
    if (identity.userBookId > 0) return identity.userBookId;
    final file = File(book.filePath);
    final registration = await _api.registerUserBook(
      token,
      name: book.title,
      author: book.author,
      md5: md5.convert(await file.readAsBytes()).toString(),
    );
    if (_token != token) throw const ReaMicroException('账号已变更，同步已停止');
    if (registration.userBookId <= 0) {
      throw const ReaMicroException('阅微未返回标注所需的内部书籍标识');
    }
    _syncBooks = {
      ..._syncBooks,
      book.id: ReaMicroBookSyncIdentity(
        cloudBookId: identity.cloudBookId,
        userBookId: registration.userBookId,
      ),
    };
    await _store.saveSyncBooks(_syncBooks);
    return registration.userBookId;
  }

  Future<int> _resolveReadingBookId(
    String token,
    String bookId,
    ReaMicroBookSyncIdentity identity, {
    List<ReaMicroBookRecord>? records,
  }) async {
    final book = await _library.bookById(bookId);
    final readingRecords = records ?? await _api.fetchBookRecords(token);
    if (book != null) {
      return _resolveMarkBookId(token, book, identity, readingRecords);
    }
    final matches = readingRecords
        .where(
          (record) =>
              record.bookId > 0 && record.cloudBookId == identity.cloudBookId,
        )
        .toList();
    if (matches.length == 1) return matches.single.bookId;
    if (identity.userBookId > 0) return identity.userBookId;
    throw const ReaMicroException('无法取得阅微内部书籍身份，阅读记录保留待重试');
  }

  bool _remoteMarkBelongsTo(
    ReaMicroMark mark,
    BookEntry local,
    int markBookId,
  ) {
    final remoteBookId = mark.bookId.trim();
    if (remoteBookId == markBookId.toString() || remoteBookId == local.id) {
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
    int markBookId, {
    ReaMicroMark? remote,
  }) => ReaMicroMarkDraft(
    cloudId: remote?.id ?? 0,
    bookId: markBookId.toString(),
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
    required int markBookId,
    required ReaderAnnotation annotation,
  }) async {
    final marks = await _api.fetchMarks(token, bookId: markBookId.toString());
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

  /// 同时同步阅读位置、阅读时长与标注。
  ///
  /// 先同步位置以建立书籍身份，让尚未公开关联的书籍也能把阅读时长
  /// 归到正确的阅微书籍记录。
  Future<ReaMicroSyncResult> syncAll() async {
    final progress = await syncProgress();
    final durations = await syncReadingSessions();
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

  /// 手动完整同步：按配置先同步 S3 书籍，再上报阅读数据。
  ///
  /// S3 只负责书籍文件与书签；阅读时长、进度和标注仍走阅微阅读接口，
  /// 避免在对象存储清单中写入不兼容字段。
  Future<ReaMicroSyncResult> syncEverything({
    bool silent = false,
    bool refreshStats = false,
  }) async {
    final s3 = s3Configured
        ? await syncS3(silent: silent, scheduleFollowUp: false)
        : null;
    final result = await syncAll();
    if (refreshStats && cloudAsPrimary) {
      await refreshCloudStats(force: true, silent: silent);
    }
    if (s3 == null) return result;
    final messages = <String>[
      s3.message,
      result.message,
    ].where((message) => message.trim().isNotEmpty).join('；');
    return ReaMicroSyncResult(
      success: result.success && s3.failed == 0,
      message: messages,
      requests: result.requests + s3.uploaded + s3.downloaded,
      durationSeconds: result.durationSeconds,
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
        final ReaMicroBookSyncIdentity? identity;
        try {
          identity = await _ensureSyncIdentity(entry.key);
        } catch (error) {
          failure ??= _messageOf(error);
          if (error is ReaMicroException && error.unauthorized) {
            await _handleError(error);
            break;
          }
          continue;
        }
        if (identity == null) continue;
        if (_token != token || !identical(_progressStates[entry.key], state)) {
          continue;
        }
        if (state.cfi.trim().isEmpty) {
          _progressStates[entry.key] = state.copyWith(dirty: false);
          continue;
        }
        try {
          if (pullCloud) {
            final remote = await _api.fetchReadProgress(
              token,
              cloudBookId: (await _resolveReadingBookId(
                token,
                entry.key,
                identity,
              )).toString(),
            );
            if (_token != token ||
                !identical(_progressStates[entry.key], state)) {
              continue;
            }
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
          await _uploadProgressState(token, entry.key, state, identity);
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
        final knownBookIds = <String>{..._links.keys, ..._syncBooks.keys};
        for (final bookId in knownBookIds) {
          final state = _progressStates[bookId];
          if (state?.dirty == true) continue;
          if (handledBooks.contains(bookId)) continue;
          final ReaMicroBookSyncIdentity? identity;
          try {
            identity = await _ensureSyncIdentity(
              bookId,
              createCloudBook: false,
            );
          } catch (error) {
            failure ??= _messageOf(error);
            if (error is ReaMicroException && error.unauthorized) {
              await _handleError(error);
              break;
            }
            continue;
          }
          if (identity == null) continue;
          try {
            final remote = await _api.fetchReadProgress(
              token,
              cloudBookId: (await _resolveReadingBookId(
                token,
                bookId,
                identity,
              )).toString(),
            );
            if (_token != token || !identical(_progressStates[bookId], state)) {
              continue;
            }
            if (remote == null || !remote.usable) {
              if (state != null && state.cfi.trim().isNotEmpty) {
                try {
                  await _uploadProgressState(token, bookId, state, identity);
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
                  await _uploadProgressState(token, bookId, state, identity);
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
    if (failure != null) _schedulePendingReadingRetry();
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
    ReaMicroBookSyncIdentity identity,
  ) async {
    final readingBookId = await _resolveReadingBookId(token, bookId, identity);
    if (_token != token || !identical(_progressStates[bookId], state)) return;
    await _api.updateReadProgress(
      token,
      cloudBookId: readingBookId,
      cfi: state.cfi,
      chapterName: _chapterNameOf(state),
      progress: state.progress,
    );
    if (_token != token || !identical(_progressStates[bookId], state)) return;
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
      _logLanSync(
        _LanSyncStage.start,
        peer: peer,
        fields: const <String, Object?>{'books': 0},
      );
      final manifest = await _lan.fetchManifest(peer);
      if (manifest.userId != _user!.id) {
        throw const ReaMicroException('该设备与当前阅微账号不一致');
      }
      _logLanSync(
        _LanSyncStage.manifestReady,
        peer: peer,
        fields: <String, Object?>{
          'books': manifest.books.length,
          'marks': manifest.books.fold<int>(
            0,
            (count, book) => count + book.marks.length,
          ),
        },
      );
      final device = peer.deviceName.isNotEmpty
          ? peer.deviceName
          : peer.nickname.isNotEmpty
          ? peer.nickname
          : '局域网设备';
      final nextLinks = Map<String, ReaMicroBookLink>.of(_links);
      var linksChanged = false;
      var imported = 0;
      var downloadFailed = 0;
      var importFailed = 0;
      var linkFailed = 0;
      var markFailed = 0;
      var applied = 0;
      var skipped = 0;
      var failed = 0;
      var unmatched = 0;
      var mergedMarks = 0;
      final matchedBooks = <String, (BookEntry, ReaMicroLanBookProgress)>{};
      for (final remote in manifest.books) {
        BookEntry? localBook;
        try {
          localBook = await _matchLanBook(remote);
        } catch (error) {
          failed += 1;
          _logLanSyncError(
            _LanSyncStage.matchFailed,
            peer: peer,
            cloudId: remote.cloudId,
            error: error,
          );
          continue;
        }
        if (localBook == null && remote.hasFiles && remote.title.isNotEmpty) {
          _logLanSync(
            _LanSyncStage.downloadStart,
            peer: peer,
            cloudId: remote.cloudId,
            fields: <String, Object?>{'files': remote.files.length},
          );
          _lanMessage = '正在从 $device 下载《${remote.title}》…';
          _notify();
          late final Uint8List bytes;
          try {
            bytes = await _lan.downloadBookArchive(peer, remote);
            _logLanSync(
              _LanSyncStage.downloadReady,
              peer: peer,
              cloudId: remote.cloudId,
              fields: <String, Object?>{
                'files': remote.files.length,
                'bytes': bytes.length,
              },
            );
          } catch (error) {
            downloadFailed += 1;
            _logLanSyncError(
              _LanSyncStage.downloadFailed,
              peer: peer,
              cloudId: remote.cloudId,
              error: error,
              fields: <String, Object?>{'files': remote.files.length},
            );
            _lanMessage = '《${remote.title}》文件下载失败：${_messageOf(error)}';
            _notify();
            continue;
          }
          try {
            final importedBook = await _library.importBytes(
              bytes,
              fallbackTitle: remote.title,
            );
            localBook = importedBook;
            if (importedBook.importOutcome != BookImportOutcome.unchanged) {
              imported += 1;
            }
            _logLanSync(
              _LanSyncStage.importReady,
              peer: peer,
              cloudId: remote.cloudId,
              fields: <String, Object?>{
                'bytes': bytes.length,
                'outcome': importedBook.importOutcome,
              },
            );
          } catch (error) {
            importFailed += 1;
            _logLanSyncError(
              _LanSyncStage.importFailed,
              peer: peer,
              cloudId: remote.cloudId,
              error: error,
              fields: <String, Object?>{
                'bytes': bytes.length,
                if (error is LibraryImportException && error.errorCode != null)
                  'import_code': error.errorCode,
              },
            );
            _lanMessage = '《${remote.title}》文件导入失败：${_messageOf(error)}';
            _notify();
            continue;
          }
        }
        if (localBook == null) {
          unmatched += 1;
          continue;
        }
        final bookId = localBook.id;
        matchedBooks[bookId] = (localBook, remote);
        if (remote.cloudId > 0 && !nextLinks.containsKey(bookId)) {
          try {
            nextLinks[bookId] = ReaMicroBookLink(
              cloudBookId: remote.cloudId,
              name: remote.title,
              author: remote.author,
              linkedAt: DateTime.now(),
            );
            _links = nextLinks;
            linksChanged = true;
            await _seedProgressStatesForBook(bookId, markDirty: false);
          } catch (error) {
            linkFailed += 1;
            nextLinks.remove(bookId);
            _logLanSyncError(
              _LanSyncStage.linkFailed,
              peer: peer,
              cloudId: remote.cloudId,
              error: error,
            );
          }
        }
        try {
          mergedMarks += await _mergeLanMarks(bookId, remote.marks);
        } catch (error) {
          markFailed += 1;
          _logLanSyncError(
            _LanSyncStage.markFailed,
            peer: peer,
            cloudId: remote.cloudId,
            error: error,
            fields: <String, Object?>{'marks': remote.marks.length},
          );
        }
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
        var ok = false;
        try {
          ok = await _applyRemoteProgress(
            bookId,
            cfi: remote.cfi,
            chapterName: remote.chapterName,
            progress: remote.progress,
            updatedAt: remote.updatedAt,
            finished: remote.finished,
            queueCloud: true,
          );
        } catch (error) {
          _logLanSyncError(
            _LanSyncStage.progressFailed,
            peer: peer,
            cloudId: remote.cloudId,
            error: error,
          );
        }
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
      var pushedBooks = 0;
      var pushedMarks = 0;
      var pushFailed = 0;
      for (final entry in matchedBooks.values) {
        final (localBook, remote) = entry;
        try {
          final marks = await _lanMarksOf(localBook);
          if (marks.isEmpty) continue;
          final merged = await _lan.pushBookMarks(
            peer,
            uuid: remote.uuid,
            marks: marks,
          );
          if (merged > 0) {
            pushedBooks += 1;
            pushedMarks += merged;
          }
        } catch (error) {
          pushFailed += 1;
          _logLanSyncError(
            _LanSyncStage.markPushFailed,
            peer: peer,
            cloudId: remote.cloudId,
            error: error,
          );
        }
      }
      final hints = <String>[
        if (unmatched > 0) '$unmatched 本未匹配本地书籍',
        if (downloadFailed > 0) '$downloadFailed 本文件下载失败',
        if (importFailed > 0) '$importFailed 本文件导入失败',
        if (linkFailed > 0) '$linkFailed 本云端关联失败',
        if (markFailed > 0) '$markFailed 本标注合并失败',
        if (mergedMarks > 0) '合并 $mergedMarks 条标注',
        if (pushedBooks > 0) '回传 $pushedBooks 本、$pushedMarks 条标注',
        if (pushFailed > 0) '$pushFailed 本标注回传失败',
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
      _logLanSync(
        _LanSyncStage.complete,
        peer: peer,
        fields: <String, Object?>{
          'books': manifest.books.length,
          'imported': imported,
          'download_failed': downloadFailed,
          'import_failed': importFailed,
          'link_failed': linkFailed,
          'mark_failed': markFailed,
          'applied': applied,
          'skipped': skipped,
          'failed': failed,
          'unmatched': unmatched,
          'marks': mergedMarks,
          'marks_pushed': pushedMarks,
          'mark_push_failed': pushFailed,
        },
      );
      return _lanMessage!;
    } catch (error) {
      _logLanSyncError(_LanSyncStage.failed, peer: peer, error: error);
      _lanMessage = _messageOf(error);
      rethrow;
    } finally {
      _lanSyncing = false;
      _notify();
    }
  }

  void _logLanSync(
    _LanSyncStage stage, {
    required ReaMicroLanSyncPeer peer,
    int? cloudId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_sync',
        fields: <String, Object?>{
          'stage': stage,
          'host': peer.host,
          'port': peer.port,
          if (cloudId != null && cloudId > 0) 'cloud_id': cloudId,
          ...fields,
        },
      ),
    );
  }

  void _logLanSyncError(
    _LanSyncStage stage, {
    required ReaMicroLanSyncPeer peer,
    required Object error,
    int? cloudId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_sync',
        fields: <String, Object?>{
          'stage': stage,
          'host': peer.host,
          'port': peer.port,
          if (cloudId != null && cloudId > 0) 'cloud_id': cloudId,
          'error': error,
          ...fields,
        },
      ),
    );
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
      _lanLoginDevices = await _withLanAdvertisementPaused(
        () => _lan.discoverLoginDevices(excludeUserId: _user?.id.toString()),
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
      await _restoreCloudS3Config(silent: true);
      await _startLanAuthorization();
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
      final peers = await _withLanAdvertisementPaused(
        () => _lan.discoverSyncPeers(excludeDeviceId: _deviceId),
      );
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

  /// 批准其他设备的局域网授权登录申请。
  Future<void> approveLanLoginRequest(String requestId) async {
    _lanAuthorizationError = null;
    _lanMessage = null;
    try {
      await _lanLoginServer.approve(requestId);
      _lanMessage = '已批准该设备登录';
    } catch (error) {
      _lanAuthorizationError = _messageOf(error);
    }
    _notify();
  }

  /// 拒绝其他设备的局域网授权登录申请。
  Future<void> rejectLanLoginRequest(String requestId) async {
    _lanAuthorizationError = null;
    _lanMessage = null;
    try {
      await _lanLoginServer.reject(requestId);
      _lanMessage = '已拒绝该设备登录';
    } catch (error) {
      _lanAuthorizationError = _messageOf(error);
    }
    _notify();
  }

  /// 重试启动本机局域网授权服务。
  Future<void> retryLanAuthorization() async {
    await _startLanAuthorization(force: true);
    _notify();
  }

  Future<void> _startLanAuthorization({bool force = false}) async {
    if (!_lanLoginServerEnabled) return;
    final token = _token;
    final user = _user;
    if (token == null || user == null) return;
    if (_lanLoginServer.running && !force) {
      _lanLoginServer.updateToken(token);
      return;
    }
    try {
      await _lanLoginServer.start(
        userId: user.id,
        nickname: user.nickName,
        avatar: user.avatar,
        token: token,
        deviceId: _deviceId ?? 'spectacular',
        deviceName: Platform.isWindows ? 'Windows 电脑' : 'Spectacular 设备',
        syncBooks: _buildLanSyncBooks,
        mergeMarks: _mergeLanMarksFromPeer,
      );
      _lanAuthorizationError = _lanLoginServer.lastError;
    } catch (error) {
      _lanAuthorizationError = _messageOf(error);
    }
  }

  Future<void> _stopLanAuthorization() async {
    _lanLoginRequests = const <ReaMicroLanLoginRequest>[];
    _lanAuthorizationError = null;
    await _lanLoginServer.stop();
  }

  /// 构造同账号设备可读取的本地书籍快照。
  Future<List<ReaMicroLanServedBook>> _buildLanSyncBooks() async {
    final entries = await _library.list();
    final progress =
        await _rawProgressStore?.snapshot() ?? const <String, ReaderProgress>{};
    final books = <ReaMicroLanServedBook>[];
    for (final entry in entries) {
      if (entry.filePath.trim().isEmpty) continue;
      books.add(
        ReaMicroLanServedBook(
          uuid: entry.id,
          title: entry.title,
          author: entry.author,
          filePath: entry.filePath,
          cloudId: _links[entry.id]?.cloudBookId ?? 0,
          cfi: progress[entry.id]?.cfi ?? '',
          chapterName: progress[entry.id]?.chapterTitle ?? '',
          progress: progress[entry.id]?.readingPercent ?? 0,
          updatedAt:
              _progressStates[entry.id]?.localUpdatedAt ??
              entry.lastReadAt?.millisecondsSinceEpoch ??
              0,
          finished: progress[entry.id]?.finished ?? false,
          marks: await _lanMarksOf(entry),
        ),
      );
    }
    return books;
  }

  /// 将本机标注转换为局域网清单可用的快照。
  Future<List<ReaMicroLanMark>> _lanMarksOf(BookEntry entry) async {
    try {
      final annotations = await _library.listBookAnnotations(entry.id);
      return <ReaMicroLanMark>[
        for (final annotation in annotations)
          if (annotation.startCfi.trim().isNotEmpty)
            ReaMicroLanMark(
              startCfi: annotation.startCfi,
              endCfi: annotation.endCfi,
              kind: annotation.type.storageValue,
              chapter: '',
              quote: annotation.quote,
              note: annotation.note ?? '',
              style: annotation.style.storageValue,
              color: _colorToRemote(annotation.color),
              synced: (_markIds['${entry.id}|${annotation.id}'] ?? 0) > 0
                  ? 1
                  : 0,
              cloudId: _markIds['${entry.id}|${annotation.id}'] ?? 0,
              createdAt: annotation.createdAt.millisecondsSinceEpoch,
              updatedAt: annotation.updatedAt.millisecondsSinceEpoch,
            ),
      ];
    } catch (_) {
      return const <ReaMicroLanMark>[];
    }
  }

  /// 合并局域网设备回传的标注。
  Future<int> _mergeLanMarksFromPeer(
    String uuid,
    List<ReaMicroLanMark> marks,
  ) async {
    final book = await _library.bookById(uuid);
    if (book == null) return 0;
    return _mergeLanMarks(book.id, marks);
  }

  void _onLanLoginRequestsChanged(List<ReaMicroLanLoginRequest> requests) {
    _lanLoginRequests = requests;
    _notify();
  }

  Future<T> _withLanAdvertisementPaused<T>(Future<T> Function() action) async {
    final shouldResume = _lanLoginServer.running;
    if (shouldResume) await _lanLoginServer.pauseAdvertisement();
    try {
      return await action();
    } finally {
      if (shouldResume) {
        await _lanLoginServer.resumeAdvertisement();
        if (_lanLoginServer.lastError != null) {
          _lanAuthorizationError = _lanLoginServer.lastError;
        }
      }
    }
  }

  void _onLocalProgressSaved(String bookId, ReaderProgress progress) {
    if (_disposed) return;
    final existing = _progressStates[bookId];
    final cfi = progress.cfi?.trim() ?? '';
    if (cfi.isEmpty) return;
    _progressStates[bookId] = ReaMicroProgressState(
      cfi: cfi,
      chapterName: progress.chapterTitle?.trim().isNotEmpty == true
          ? progress.chapterTitle!.trim()
          : existing?.chapterName ?? '',
      progress: progress.readingPercent ?? existing?.progress ?? 0,
      localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      remoteUpdatedAt: existing?.remoteUpdatedAt ?? 0,
      uploadedAt: existing?.uploadedAt ?? 0,
      dirty: true,
    );
    _persistProgressStates();
    if (_token != null) {
      scheduleProgressSync();
    }
  }

  Future<void> _seedProgressStatesFromLocal({bool markDirty = true}) async {
    final books = await _library.list();
    for (final book in books) {
      await _seedProgressStatesForBook(book.id, markDirty: markDirty);
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
    final storedAt = markDirty
        ? await _library.bookProgressUpdatedAt(bookId)
        : null;
    final knownLocalAt = existing?.localUpdatedAt ?? 0;
    final localUpdatedAt = storedAt != null && storedAt > knownLocalAt
        ? storedAt
        : knownLocalAt;
    if (existing != null && existing.cfi == cfi) {
      if (markDirty && !existing.dirty) {
        _progressStates[bookId] = existing.copyWith(
          dirty: true,
          localUpdatedAt: localUpdatedAt > 0 ? localUpdatedAt : now,
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
      localUpdatedAt: markDirty
          ? (localUpdatedAt > 0 ? localUpdatedAt : now)
          : localUpdatedAt,
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
    final initialState = _progressStates[bookId];
    final token = _token;
    final book = await _library.bookById(bookId);
    if (book == null) return false;
    final revision = book.contentRevision?.trim() ?? '';
    if (revision.isEmpty) return false;
    final remoteProgress = progress.clamp(0.0, 1.0).toDouble();
    final mapped = await mapReaMicroProgressToBook(
      sourcePath: book.filePath,
      cfi: cfi,
      progress: remoteProgress,
    );
    final String localCfi;
    final int localSpineIndex;
    final double normalized;
    if (mapped != null) {
      localCfi = mapped.cfi;
      localSpineIndex = mapped.spineIndex;
      normalized = mapped.progress;
    } else {
      // 本地原书不可读时仍可保留结构合法且章节存在的 CFI；章节编号越界
      // 不能直接写入，否则阅读页会拒绝恢复。
      final spineCount = book.spineCount ?? 0;
      String? fallbackCfi;
      int? fallbackSpine;
      for (final candidate in epubCfiCandidates(cfi)) {
        final parsed = EpubCfi.parse(candidate);
        final spine = parsed == null ? null : spineIndexOfCfi(parsed);
        if (spine == null || spine < 0) continue;
        if (spineCount > 0 && spine >= spineCount) continue;
        fallbackCfi = candidate;
        fallbackSpine = spine;
        break;
      }
      if (fallbackCfi == null || fallbackSpine == null) {
        unawaited(
          ReaderLog.instance.log(
            'reamicro_progress_apply_failed',
            fields: <String, Object?>{
              'book_id': bookId,
              'reason': 'cfi_not_mappable',
              'cfi': cfi,
            },
          ),
        );
        return false;
      }
      localCfi = fallbackCfi;
      localSpineIndex = fallbackSpine;
      normalized = remoteProgress;
    }
    if (_token != token || !identical(_progressStates[bookId], initialState)) {
      return false;
    }
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
    } on Object catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_progress_apply_failed',
          fields: <String, Object?>{
            'book_id': bookId,
            'reason': '$error',
            'cfi': localCfi,
          },
        ),
      );
      return false;
    }
    if (_token != token || !identical(_progressStates[bookId], initialState)) {
      return false;
    }
    final existing = initialState;
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
    await _stopLanAuthorization();
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
    unawaited(_lanLoginServer.stop());
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
  final List<ReaMicroReadSessionLog> logs = <ReaMicroReadSessionLog>[];
  int durationSeconds = 0;
}

enum _LanSyncStage {
  start,
  manifestReady,
  downloadStart,
  downloadReady,
  downloadFailed,
  importReady,
  importFailed,
  matchFailed,
  linkFailed,
  markFailed,
  markPushFailed,
  progressFailed,
  complete,
  failed,
}

class _SessionPortion {
  const _SessionPortion({
    required this.date,
    required this.durationSeconds,
    required this.key,
    required this.startedAt,
    required this.endedAt,
  });

  final String date;
  final int durationSeconds;
  final String key;
  final int startedAt;
  final int endedAt;
}

List<_SessionPortion> _splitSession(ReadingSession session) {
  if (session.duration <= Duration.zero ||
      !session.endedAt.isAfter(session.startedAt)) {
    return const <_SessionPortion>[];
  }
  final start = _chinaTime(session.startedAt);
  final end = _chinaTime(session.endedAt);
  final portions = <_SessionPortion>[];
  final span = end.difference(start).inMicroseconds;
  final totalSeconds = session.duration.inSeconds;
  var assigned = 0;
  var cursor = start;
  while (cursor.isBefore(end)) {
    // start/end 已平移为北京时间墙钟值并保留 UTC 标志，日期边界也必须
    // 使用同一表示，避免与设备本地时区午夜混算。
    final dayStart = DateTime.utc(cursor.year, cursor.month, cursor.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final segmentEnd = end.isBefore(dayEnd) ? end : dayEnd;
    // 按累计比例分配有效时长，跨日小数秒只在整段会话取整一次。
    final cumulative =
        totalSeconds * segmentEnd.difference(start).inMicroseconds ~/ span;
    final seconds = cumulative - assigned;
    assigned = cumulative;
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
          startedAt:
              session.startedAt.millisecondsSinceEpoch +
              cursor.difference(start).inMilliseconds,
          endedAt:
              session.startedAt.millisecondsSinceEpoch +
              segmentEnd.difference(start).inMilliseconds,
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

int _publicReadingRank(
  ReaMicroCloudBook book,
  String normalizedTitle,
  String normalizedAuthor,
) {
  final titleMatches =
      normalizedTitle.isNotEmpty &&
      _normalizeBookText(book.name) == normalizedTitle;
  final authorMatches =
      normalizedAuthor.isNotEmpty &&
      _normalizeBookText(book.author) == normalizedAuthor;
  return switch ((titleMatches, authorMatches)) {
    (true, true) => 0,
    (true, false) when normalizedAuthor.isEmpty => 0,
    (true, _) => 1,
    (_, true) => 2,
    _ => 3,
  };
}
