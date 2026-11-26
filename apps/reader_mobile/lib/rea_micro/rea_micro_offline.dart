part of 'rea_micro_controller.dart';

typedef _ReadingBaseline = ({
  Map<String, int> watermarks,
  Map<String, int> ends,
});

extension _OfflinePages on ReaMicroController {
  Future<void> _restoreOutbox(String token) async {
    final saved = await _library.getSetting(_reviewQueueKey(token));
    final deleted = await _library.getSetting(_deletesKey(token));
    if (_token != token) return;
    _pendingReviews = saved == null || saved.isEmpty
        ? {}
        : jsonDecode(saved) as Map<String, dynamic>;
    _pendingNoteDeletes = deleted == null || deleted.isEmpty
        ? {}
        : (jsonDecode(deleted) as List).cast<int>().toSet();
  }

  String _outboxOwner(String token) {
    final id = _user?.id ?? 0;
    return pageCache.key([
      ReaMicroApiClient.transportOf(_api)?.baseUrl,
      if (id > 0) id else token,
    ]);
  }

  String _deletesKey(String token) =>
      'reamicro.pendingNoteDeletes.${_outboxOwner(token)}';
  Future<void> _saveNoteDeletes(String token) => _library.setSetting(
    _deletesKey(token),
    jsonEncode(_pendingNoteDeletes.toList()),
  );

  Future<List<ReaMicroMarkBook>> _mergeOfflineMarkBooks(
    List<ReaMicroMarkBook> remote,
    List<ReaMicroMark> marks,
  ) async {
    final rows = [
      for (final row in remote)
        ReaMicroMarkBook(
          bookId: row.bookId,
          cloudBookId: row.cloudBookId,
          name: row.name,
          author: row.author,
          cover: row.cover,
          updatedAt: row.updatedAt,
          thoughtCount: _visibleMarkCount(row, marks, 1, row.thoughtCount),
          underlineCount: _visibleMarkCount(row, marks, 0, row.underlineCount),
        ),
    ];
    final counts = await _library.bookNoteCounts();
    final books = await _library.list();
    for (final book in books) {
      final ids = annotationCloudIds(book.id);
      if (!counts.containsKey(book.id) && ids.isEmpty) continue;
      final identity = _syncBooks[book.id];
      final link = _links[book.id];
      final cloud = link?.cloudBookId ?? identity?.cloudBookId ?? 0;
      final internal = identity?.userBookId ?? link?.userBookId ?? 0;
      var index = rows.indexWhere(
        (row) =>
            (internal > 0 && row.bookId == internal) ||
            (cloud > 0 && row.cloudBookId == cloud),
      );
      if (index < 0 &&
          internal <= 0 &&
          cloud <= 0 &&
          books
                  .where(
                    (other) =>
                        other.title == book.title &&
                        other.author == book.author,
                  )
                  .length ==
              1) {
        final matches = rows.indexed.where(
          (entry) =>
              entry.$2.name == book.title && entry.$2.author == book.author,
        );
        if (matches.length == 1) index = matches.first.$1;
      }
      final old = index < 0 ? null : rows[index];
      final local = await _library.listBookAnnotations(book.id);
      final cloudMarks = marks
          .where(
            (mark) =>
                (old != null && mark.bookId == '${old.bookId}') ||
                (internal > 0 && mark.bookId == '$internal') ||
                (cloud > 0 && mark.bookId == '$cloud') ||
                ids.containsValue(mark.id),
          )
          .toList();
      final localIds = local.map((note) => note.id).toSet();
      final gone = {
        for (final entry in ids.entries)
          if (!localIds.contains(entry.key) &&
              !_pendingNoteDeletes.contains(entry.value))
            entry.value,
      };
      int merged(int kind, int base) {
        final overlaps = <int>{};
        for (final note in local.where(
          (note) => note.type.storageValue == kind,
        )) {
          for (final mark in cloudMarks) {
            if (mark.kind == kind &&
                (ids[note.id] == mark.id ||
                    note.id == 'mark-cloud-${mark.id}' ||
                    (note.startCfi == mark.startCfi &&
                        note.endCfi == mark.endCfi))) {
              overlaps.add(mark.id);
              break;
            }
          }
        }
        final locals = local
            .where((note) => note.type.storageValue == kind)
            .length;
        if (cloudMarks.isEmpty && old != null) {
          return locals > base ? locals : base;
        }
        return (base -
                    overlaps.length -
                    cloudMarks
                        .where((m) => m.kind == kind && gone.contains(m.id))
                        .length)
                .clamp(0, base) +
            locals;
      }

      final row = ReaMicroMarkBook(
        bookId: old?.bookId ?? internal,
        cloudBookId: old?.cloudBookId ?? cloud,
        name: old?.name ?? book.title,
        author: old?.author ?? book.author,
        cover: old?.cover ?? book.remoteCoverUrl ?? '',
        thoughtCount: merged(1, old?.thoughtCount ?? 0),
        underlineCount: merged(0, old?.underlineCount ?? 0),
        updatedAt: [
          old?.updatedAt ?? 0,
          counts[book.id]?.updatedAt.millisecondsSinceEpoch ?? 0,
        ].reduce((left, right) => left > right ? left : right),
      );
      if (index >= 0) {
        rows[index] = row;
      } else {
        rows.add(row);
      }
    }
    return rows.where((row) => row.markCount > 0).toList();
  }

  int _visibleMarkCount(
    ReaMicroMarkBook book,
    List<ReaMicroMark> marks,
    int kind,
    int count,
  ) {
    if (_pendingNoteDeletes.isEmpty) return count;
    final deleted = marks.where(
      (mark) =>
          mark.kind == kind &&
          _pendingNoteDeletes.contains(mark.id) &&
          (mark.bookId == '${book.bookId}' ||
              mark.bookId == '${book.cloudBookId}'),
    );
    return (count - deleted.length).clamp(0, count);
  }

  String _reviewQueueKey(String token) =>
      'reamicro.pendingReviews.${_outboxOwner(token)}';

  Future<void> _saveReviewQueue(String token) =>
      _library.setSetting(_reviewQueueKey(token), jsonEncode(_pendingReviews));

  ReaMicroBookReview _draftReview(int cloudId, Map<String, dynamic> draft) {
    final link = _links.values
        .where((link) => link.cloudBookId == cloudId)
        .firstOrNull;
    return ReaMicroBookReview.fromJson({
      ...draft,
      'bookName': link?.name,
      'bookAuthor': link?.author,
    });
  }

  Future<String?> _flushReviews(String token) => _reviewUploads.putIfAbsent(
    token,
    () => _uploadReviews(token).whenComplete(() {
      _reviewUploads.remove(token);
    }),
  );

  Future<String?> _uploadReviews(String token) async {
    for (final entry in _pendingReviews.entries.toList()) {
      if (_disposed || _token != token) return null;
      final draft = entry.value as Map<String, dynamic>;
      try {
        final cloudId = draft['cloudBookId'] as int;
        final bookId = draft['bookId'] as int?;
        final publish = draft['preservePublish'] == true
            ? (await _api.fetchBookReview(
                    token,
                    cloudBookId: cloudId,
                    bookId: bookId,
                  ))?.published ??
                  false
            : draft['status'] == 2;
        if (_token != token || !identical(_pendingReviews[entry.key], draft)) {
          continue;
        }
        await _api.rateReview(
          token,
          cloudBookId: cloudId,
          bookId: bookId,
          rating: draft['rating'] as int,
          comment: draft['comment'] as String,
          publish: publish,
        );
        if (_token != token || !identical(_pendingReviews[entry.key], draft)) {
          continue;
        }
        _pendingReviews.remove(entry.key);
        await _saveReviewQueue(token);
      } catch (error) {
        if (_token == token) await _handleError(error);
        return _messageOf(error);
      }
    }
    return null;
  }

  Future<List<ReaMicroMark>> _displayMarks(String token, {String? bookId}) =>
      _page(token, [
        'marks',
        bookId,
      ], (api, _) => api.fetchMarks(token, bookId: bookId));

  Future<_LocalReading> _localReading(_ReadingBaseline baseline) async {
    final sessions =
        await _library.readingSessionStore()?.list() ??
        const <ReadingSession>[];
    final portions = <String, List<_SessionPortion>>{};
    for (final session in sessions) {
      final watermark = baseline.watermarks[session.bookId] ?? 0;
      if (session.endedAt.millisecondsSinceEpoch <= watermark) continue;
      final tail = _splitSession(
        session,
        watermark: watermark,
        uploadedEnds: baseline.ends,
      );
      if (tail.isNotEmpty) (portions[session.bookId] ??= []).addAll(tail);
    }
    return _LocalReading(
      this,
      portions,
      portions.isEmpty
          ? {}
          : {for (final book in await _library.list()) book.id: book},
    );
  }

  void _disconnected(String token) {
    if (_disposed || _token != token) return;
    if (!_offline) {
      _offline = true;
      if (!_busy && !_loadingCloudStats && _cloudStats != null) {
        unawaited(refreshCloudStats(force: true, silent: true));
      }
      _notify();
    }
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 15), _checkConnection);
  }

  Future<void> _checkConnection() async {
    final token = _token;
    if (_disposed || token == null || !_offline || _recovering) return;
    _recovering = true;
    try {
      await _api.fetchUser(token);
      if (_disposed || _token != token) return;
      _offline = false;
      _reconnectTimer?.cancel();
      await syncAll();
      if (_disposed || _token != token || _offline) return;
      await refresh(silent: true);
      if (!_disposed && _token == token && !_offline) _pagesChanged();
    } catch (error) {
      if (!_disposed &&
          _token == token &&
          error is ReaMicroException &&
          error.unauthorized) {
        await _handleError(error);
        _notify();
      }
    } finally {
      _recovering = false;
      if (_offline && !_disposed && _token == token) _disconnected(token);
    }
  }

  Future<_ReadingBaseline> _readingBaseline() async {
    final watermarks = await _store.loadSessionWatermarks();
    final ends = _uploadedEnds(await _store.loadUploadedSessionKeys());
    ends.removeWhere(
      (key, end) => end <= (watermarks[key.split('|').first] ?? 0),
    );
    return (watermarks: watermarks, ends: ends);
  }

  Future<T> _withSessionSnapshot<T>(
    Future<T> Function() work, {
    bool write = false,
  }) async {
    final wait = write
        ? Future.wait([_sessionWrite, ..._sessionReaders])
        : _sessionWrite;
    final done = Completer<void>();
    if (write) {
      _sessionWrite = done.future;
    } else {
      _sessionReaders.add(done.future);
    }
    try {
      await wait;
      return await work();
    } finally {
      _sessionReaders.remove(done.future);
      done.complete();
    }
  }

  Future<T> _page<T>(
    String token,
    List<Object?> identity,
    Future<T> Function(ReaMicroApi api, DateTime at) load, {
    Future<T> Function(T, _ReadingBaseline, DateTime)? merge,
  }) => merge == null
      ? _readPage(token, identity, load, null)
      : _withSessionSnapshot(() => _readPage(token, identity, load, merge));

  Future<T> _readPage<T>(
    String token,
    List<Object?> identity,
    Future<T> Function(ReaMicroApi api, DateTime at) load,
    Future<T> Function(T, _ReadingBaseline, DateTime)? merge,
  ) async {
    final client = ReaMicroApiClient.transportOf(_api);
    final key = pageCache.key([
      '阅微',
      client?.baseUrl ?? '',
      token,
      ...identity,
    ]);
    void checkAccount() {
      if (_disposed || _token != token) {
        throw const ReaMicroException('账号已变更，请重新加载页面');
      }
    }

    final at = _now();
    final responses = <String, Object?>{};
    var baseline = merge == null ? null : await _readingBaseline();
    late T result;
    var snapshotAt = at;
    try {
      if (_offline) {
        throw const ReaMicroException('暂时无法连接阅微服务器', transportFailure: true);
      }
      result = client != null
          ? await client.readPage((api) => load(api, at), (name, send) async {
              final response = await send();
              responses[name] = response;
              return response;
            })
          : await load(_api, at);
      checkAccount();
      if (client != null) {
        try {
          await pageCache.write(key, {
            'at': at.millisecondsSinceEpoch,
            'responses': responses,
            if (baseline != null) 'watermarks': baseline.watermarks,
            if (baseline != null) 'ends': baseline.ends,
          });
        } catch (_) {}
      }
    } on ReaMicroException catch (error, stack) {
      checkAccount();
      if (!error.unavailable) rethrow;
      _disconnected(token);
      if (client == null) rethrow;
      try {
        final saved = await pageCache.read(key) as Map<String, dynamic>;
        snapshotAt = DateTime.fromMillisecondsSinceEpoch(saved['at'] as int);
        final raw = saved['responses'] as Map;
        result = await client.readPage((api) => load(api, snapshotAt), (
          name,
          _,
        ) async {
          if (!raw.containsKey(name)) throw const FormatException('页面缓存不完整');
          return raw[name];
        });
        if (merge != null) {
          baseline = (
            watermarks: Map<String, int>.from(saved['watermarks'] as Map),
            ends: Map<String, int>.from(saved['ends'] as Map),
          );
        }
      } catch (_) {
        Error.throwWithStackTrace(error, stack);
      }
    }
    checkAccount();
    if (merge != null) result = await merge(result, baseline!, snapshotAt);
    checkAccount();
    return result;
  }
}

String _periodKey(ReaMicroRecordPeriod period, DateTime date) =>
    _dateString(switch (period) {
      ReaMicroRecordPeriod.week => DateTime.utc(
        date.year,
        date.month,
        date.day - date.weekday + 1,
      ),
      ReaMicroRecordPeriod.month => DateTime.utc(date.year, date.month),
      ReaMicroRecordPeriod.year => DateTime.utc(date.year),
    });

class _LocalReading {
  _LocalReading(this.controller, this.byBook, this.books);
  final ReaMicroController controller;
  final Map<String, List<_SessionPortion>> byBook;
  final Map<String, BookEntry> books;

  Map<String, int> get days {
    final result = <String, int>{};
    for (final portions in byBook.values) {
      for (final portion in portions) {
        result.update(
          portion.date,
          (n) => n + portion.durationSeconds,
          ifAbsent: () => portion.durationSeconds,
        );
      }
    }
    return result;
  }

  List<ReaMicroChartPoint> chart(List<ReaMicroChartPoint> base) {
    if (byBook.isEmpty) return base;
    final points = {for (final point in base) point.day: point};
    for (final entry in days.entries) {
      final existing = points[entry.key];
      points[entry.key] = ReaMicroChartPoint(
        day: entry.key,
        durationSeconds: (existing?.durationSeconds ?? 0) + entry.value,
        readingDurationSeconds:
            (existing?.readingDurationSeconds ?? 0) + entry.value,
        listeningDurationSeconds: existing?.listeningDurationSeconds ?? 0,
      );
    }
    return points.values.toList()
      ..sort((left, right) => left.day.compareTo(right.day));
  }

  List<ReaMicroBookRecord> records(
    List<ReaMicroBookRecord> base, {
    ReaMicroRecordPeriod? period,
    DateTime? anchor,
  }) {
    final result = base.toList();
    final key = period == null ? null : _periodKey(period, anchor!);
    final localIds = {
      ...byBook.keys,
      ...controller._progressStates.keys.where(
        (id) => controller._progressStates[id]!.dirty,
      ),
      ...controller._pendingFinished.keys,
    };
    for (final id in localIds) {
      final portions = (byBook[id] ?? const <_SessionPortion>[]).where(
        (p) =>
            period == null || _periodKey(period, DateTime.parse(p.date)) == key,
      );
      final identity = controller._syncBooks[id];
      final link = controller._links[id];
      final internal = identity?.userBookId ?? link?.userBookId ?? 0;
      final cloud = link?.cloudBookId ?? identity?.cloudBookId ?? 0;
      final index = result.indexWhere(
        (row) =>
            (internal > 0 && row.bookId == internal) ||
            (cloud > 0 && row.cloudBookId == cloud),
      );
      final old = index == -1 ? null : result[index];
      if (old == null && portions.isEmpty) continue;
      final duration = portions.fold(
        0,
        (sum, part) => sum + part.durationSeconds,
      );
      final last = portions.fold(
        old?.lastReadTime ?? 0,
        (end, part) => part.endedAt > end ? part.endedAt : end,
      );
      final progress = controller._progressStates[id];
      final finished = controller._pendingFinished[id];
      final book = books[id];
      final record = ReaMicroBookRecord(
        bookId: old?.bookId ?? internal,
        cloudBookId: old?.cloudBookId ?? cloud,
        localBookId: id,
        name: old?.name ?? book?.title ?? link?.name ?? '本地书籍',
        author: old?.author ?? book?.author ?? '',
        cover: old?.cover ?? book?.remoteCoverUrl ?? '',
        progress: progress?.dirty == true
            ? progress!.progress
            : old?.progress ?? 0,
        totalReadTimeSeconds: (old?.totalReadTimeSeconds ?? 0) + duration,
        readingDurationSeconds: (old?.readingDurationSeconds ?? 0) + duration,
        listeningDurationSeconds: old?.listeningDurationSeconds ?? 0,
        readDays:
            (old?.readDays ?? 0) +
            portions
                .map((p) => p.date)
                .toSet()
                .where(
                  (date) =>
                      old == null ||
                      old.lastReadTime <= 0 ||
                      date.compareTo(
                            _dateString(
                              _chinaTime(
                                DateTime.fromMillisecondsSinceEpoch(
                                  old.lastReadTime,
                                ),
                              ),
                            ),
                          ) >
                          0,
                )
                .length,
        lastReadTime: last,
        finishReadTime: finished == null
            ? old?.finishReadTime ?? 0
            : finished > 0
            ? finished
            : 0,
      );
      if (index < 0) {
        result.add(record);
      } else {
        result[index] = record;
      }
    }
    return result;
  }

  ReaMicroPeriodStats period(
    ReaMicroPeriodStats base,
    ReaMicroRecordPeriod period,
    DateTime anchor, {
    List<ReaMicroChartPoint> chart = const [],
  }) {
    final key = _periodKey(period, anchor);
    final daily = Map.of(days)
      ..removeWhere(
        (date, _) => _periodKey(period, DateTime.parse(date)) != key,
      );
    if (daily.isEmpty) return base;
    final byDay = {for (final item in base.days) item.day: item};
    final byMonth = {for (final item in base.months) item.month: item};
    var addedDays = 0;
    final seen = {
      for (final point in chart)
        if (point.durationSeconds > 0) point.day,
    };
    for (final entry in daily.entries) {
      final date = DateTime.parse(entry.key);
      final bucket = period == ReaMicroRecordPeriod.week
          ? date.weekday
          : date.day;
      final day = byDay[bucket];
      if (!seen.contains(entry.key) &&
          (period == ReaMicroRecordPeriod.year
              ? chart.isNotEmpty ||
                    (byMonth[date.month]?.durationSeconds ?? 0) == 0
              : (day?.durationSeconds ?? 0) == 0)) {
        addedDays++;
      }
      if (period == ReaMicroRecordPeriod.year) {
        final month = byMonth[date.month];
        byMonth[date.month] = ReaMicroMonthDuration(
          month: date.month,
          durationSeconds: (month?.durationSeconds ?? 0) + entry.value,
          readingDurationSeconds:
              (month?.readingDurationSeconds ?? 0) + entry.value,
          listeningDurationSeconds: month?.listeningDurationSeconds ?? 0,
        );
      } else {
        byDay[bucket] = ReaMicroDayDuration(
          day: bucket,
          durationSeconds: (day?.durationSeconds ?? 0) + entry.value,
          readingDurationSeconds:
              (day?.readingDurationSeconds ?? 0) + entry.value,
          listeningDurationSeconds: day?.listeningDurationSeconds ?? 0,
        );
      }
    }
    final extra = daily.values.fold(0, (sum, seconds) => sum + seconds);
    final total = base.totalDurationSeconds + extra;
    final count = base.readDays + addedDays;
    return ReaMicroPeriodStats(
      days: byDay.values.toList(),
      months: byMonth.values.toList(),
      readDays: count,
      totalDurationSeconds: total,
      bookCount: base.bookCount,
      finishedBookCount: base.finishedBookCount,
      continuousReadDays: base.continuousReadDays,
      averageDailyDurationSeconds: count == 0 ? 0 : total ~/ count,
      topBooks: base.topBooks,
      listeningDurationSeconds: base.listeningDurationSeconds,
      readingDurationSeconds: base.readingDurationSeconds + extra,
    );
  }

  ReaMicroCloudStats stats(ReaMicroCloudStats base, DateTime now) {
    final merged = records(base.books);
    final overview = base.overview;
    final extra = days.values.fold(0, (sum, seconds) => sum + seconds);
    final seen = {
      for (final point in base.chart)
        if (point.durationSeconds > 0) point.day,
    };
    ReaMicroPeriodStats current(
      ReaMicroPeriodStats snapshot,
      ReaMicroRecordPeriod kind,
    ) => period(
      _periodKey(kind, now) == _periodKey(kind, base.fetchedAt)
          ? snapshot
          : ReaMicroPeriodStats.fromJson({}),
      kind,
      now,
      chart: base.chart,
    );
    return ReaMicroCloudStats(
      overview: ReaMicroOverview(
        years: {
          ...overview.years,
          ...days.keys.map((date) => DateTime.parse(date).year),
        }.toList()..sort(),
        readDays:
            overview.readDays +
            days.keys.where((date) => !seen.contains(date)).length,
        totalDurationSeconds: overview.totalDurationSeconds + extra,
        bookCount: overview.bookCount + merged.length - base.books.length,
        finishedBookCount:
            overview.finishedBookCount +
            merged.where((b) => b.finished).length -
            base.books.where((b) => b.finished).length,
        registerTimestamp: overview.registerTimestamp,
        topBooks: overview.topBooks,
        listeningDurationSeconds: overview.listeningDurationSeconds,
        readingDurationSeconds: overview.readingDurationSeconds + extra,
      ),
      week: current(base.week, ReaMicroRecordPeriod.week),
      month: current(base.month, ReaMicroRecordPeriod.month),
      year: current(base.year, ReaMicroRecordPeriod.year),
      chart: chart(base.chart),
      books: merged,
      fetchedAt: base.fetchedAt,
      periodDate: now,
      monthDate: DateTime(now.year, now.month),
    );
  }
}

Map<String, int> _uploadedEnds(Set<String> uploaded) {
  final ends = <String, int>{};
  for (final key in uploaded) {
    final fields = key.split('|');
    if (fields.length != 4) continue;
    final end = int.tryParse(fields[2]);
    final identity = '${fields[0]}|${fields[1]}|${fields[3]}';
    if (end != null && end > (ends[identity] ?? 0)) ends[identity] = end;
  }
  return ends;
}

extension on ReaMicroMilestone {
  ReaMicroMilestone withDraft(Map<String, dynamic> draft) => ReaMicroMilestone(
    id: id,
    rating: draft['rating'] as int,
    status: draft['status'] as int,
    ratingTime: draft['commentUpdateTime'] as int,
    comment: draft['comment'] as String,
    cloudBookId: cloudBookId,
    name: name,
    author: author,
    cover: cover,
    style: style,
    seal: seal,
    popularity: popularity,
    totalReadTimeSeconds: totalReadTimeSeconds,
    startReadTime: startReadTime,
    readDays: readDays,
    lastReadTime: lastReadTime,
    maxDayReadDurationSeconds: maxDayReadDurationSeconds,
    maxDayReadTime: maxDayReadTime,
    immersiveReadTimeSeconds: immersiveReadTimeSeconds,
    fragmentReadTimeSeconds: fragmentReadTimeSeconds,
    deepReadTimeSeconds: deepReadTimeSeconds,
    deepFragmentReadTimeSeconds: deepFragmentReadTimeSeconds,
    listeningDurationSeconds: listeningDurationSeconds,
    readingDurationSeconds: readingDurationSeconds,
  );
}
