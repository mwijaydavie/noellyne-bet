import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_pick.dart';
import '../noellyne_config.dart';

/// Combined snapshot of live published picks + settled performance history.
class DailyPicksBoard {
  const DailyPicksBoard({
    required this.published,
    required this.settled,
    this.errorMessage,
    this.syncNotice,
    this.fromCache = false,
    this.fetchedAt,
  });

  final List<DailyPick> published;
  final List<DailyPick> settled;

  /// Hard error shown ONLY when both network AND local cache are empty.
  final String? errorMessage;

  /// Soft non-blocking banner shown when network flickered while displaying
  /// cached picks (zero blank screens on patchy mobile connections).
  final String? syncNotice;
  final bool fromCache;
  final DateTime? fetchedAt;

  bool get isEmpty => published.isEmpty && settled.isEmpty;
  bool get hasData => !isEmpty;

  DailyPicksBoard copyWith({
    List<DailyPick>? published,
    List<DailyPick>? settled,
    String? errorMessage,
    String? syncNotice,
    bool? fromCache,
    DateTime? fetchedAt,
  }) =>
      DailyPicksBoard(
        published: published ?? this.published,
        settled: settled ?? this.settled,
        errorMessage: errorMessage,
        syncNotice: syncNotice,
        fromCache: fromCache ?? this.fromCache,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
}

/// Offline-first, Stale-While-Revalidate repository for Noellyne Daily Picks &
/// Settled Results (`picksSupabaseUrl`).
///
/// Architecture designed for unreliable / high-latency mobile networks:
///   - L1 memory cache (TTL 3 min): tab revisits paint in 0ms with 0 DB hits.
///   - L2 persistent disk cache (`SharedPreferences`, max age 72h): cold starts
///     paint cached picks immediately even with zero internet signal.
///   - Single-flight request deduplication: concurrent callers (`HomePage` +
///     `DailyPicksPage`) share one network fetch.
///   - Automatic single retry (700ms backoff) on transient socket/timeout drops.
///   - Zero-blank fallback: a failed refresh NEVER wipes already-loaded picks.
///   - Security: uses ONLY the public read-only publishable key.
class DailyPicksRepository {
  const DailyPicksRepository();

  static const _enableDemo = bool.fromEnvironment(
    'DAILY_PICKS_DEMO',
    defaultValue: false,
  );

  static const _selectCols =
      'id,match,league,pick,odds,confidence,reasoning,stream_id,'
      'kickoff_time,tags,slip_code,sport,tier,units,edge_pct,'
      'injury_note,status,result,score,profit_units,settled_at';

  static const _diskCacheKey = 'noellyne_daily_picks_board_v1';
  static const _freshTtl = Duration(minutes: 3);
  static const _maxDiskAge = Duration(hours: 72);
  static const _requestTimeout = Duration(seconds: 9);

  static DailyPicksBoard? _memBoard;
  static DateTime? _memFetchedAt;
  static Future<DailyPicksBoard>? _inFlight;

  /// True when what the UI is showing came from [_demo], not the pipeline.
  static bool get showsSampleData => _enableDemo;

  /// Synchronous L1 cache peek so UI renders in 0ms without a skeleton flash.
  DailyPicksBoard? peekCachedBoard() => _memBoard;

  /// True when the L1 memory cache is still fresh enough to skip hitting DB.
  bool get isCacheFresh {
    final ts = _memFetchedAt;
    if (_memBoard == null || ts == null) return false;
    final age = DateTime.now().difference(ts);
    return age >= Duration.zero && age < _freshTtl;
  }

  /// Fast L2 disk cache load for cold app starts (prevents blank screens when
  /// opening the app offline or on slow 3G).
  Future<DailyPicksBoard?> loadCachedBoard() async {
    if (_memBoard != null) return _memBoard;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskCacheKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final fetchedAt = DateTime.tryParse('${decoded['fetchedAt'] ?? ''}');
      if (fetchedAt != null &&
          DateTime.now().difference(fetchedAt) > _maxDiskAge) {
        return null;
      }

      final published = _parseList(decoded['published']);
      final settled = _parseList(decoded['settled']);
      if (published.isEmpty && settled.isEmpty) return null;

      final cached = DailyPicksBoard(
        published: published,
        settled: settled,
        fromCache: true,
        fetchedAt: fetchedAt,
      );
      _memBoard ??= cached;
      return cached;
    } catch (error) {
      debugPrint('daily_picks disk cache read skipped: $error');
      return null;
    }
  }

  Future<DailyPicksBoard> fetchBoard({
    int limit = 40,
    bool force = false,
  }) async {
    if (!force && isCacheFresh && _memBoard != null) {
      return _memBoard!;
    }
    final pending = _inFlight;
    if (pending != null) return pending;

    final operation = _fetchBoardLive(limit: limit);
    _inFlight = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    }));
    return operation;
  }

  Future<DailyPicksBoard> _fetchBoardLive({required int limit}) async {
    try {
      final results = await _withRetry(
        () => Future.wait<List<DailyPick>>([
          _query(status: 'published', order: 'kickoff_time.asc', limit: limit),
          _query(
            status: 'settled',
            order: 'settled_at.desc.nullslast,kickoff_time.desc',
            limit: limit,
          ),
        ]),
      );

      final now = DateTime.now();
      final board = DailyPicksBoard(
        published: results[0].isNotEmpty || !_enableDemo ? results[0] : _demo,
        settled: results[1],
        fromCache: false,
        fetchedAt: now,
      );
      _memBoard = board;
      _memFetchedAt = now;
      unawaited(_persistBoard(board));
      return board;
    } catch (error) {
      debugPrint('daily_picks board fetch failed: $error');
      final fallback = _memBoard ?? await loadCachedBoard();
      if (fallback != null && fallback.hasData) {
        return fallback.copyWith(
          fromCache: true,
          errorMessage: null,
          syncNotice:
              'Mtandao umecheza — unaona picks zilizohifadhiwa kwenye simu.',
        );
      }
      return DailyPicksBoard(
        published: _enableDemo ? _demo : const [],
        settled: const [],
        errorMessage:
            'Imeshindwa kuunganisha na server ya picks. Hakikisha data iko on kisha jaribu tena.',
      );
    }
  }

  Future<List<DailyPick>> fetch({int limit = 40, bool force = false}) async {
    final board = await fetchBoard(limit: limit, force: force);
    if (board.published.isNotEmpty) {
      return board.published.take(limit).toList(growable: false);
    }
    return _enableDemo ? _demo : const [];
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return action();
    }
  }

  Future<void> _persistBoard(DailyPicksBoard board) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'fetchedAt': (board.fetchedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'published': board.published.map((p) => p.toJson()).toList(growable: false),
        'settled': board.settled.map((p) => p.toJson()).toList(growable: false),
      });
      await prefs.setString(_diskCacheKey, payload);
    } catch (error) {
      debugPrint('daily_picks disk cache write skipped: $error');
    }
  }

  List<DailyPick> _parseList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => DailyPick.fromJson(row.cast<String, dynamic>()))
        .where((p) => p.pick.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<DailyPick>> _query({
    required String status,
    required String order,
    required int limit,
  }) async {
    if (!NoellyneConfig.picksSupabaseEnabled) return const [];
    final base = NoellyneConfig.picksSupabaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/rest/v1/daily_picks'
      '?select=$_selectCols'
      '&status=eq.$status'
      '&order=$order'
      '&limit=$limit',
    );
    final response = await http
        .get(
          uri,
          headers: const {
            'apikey': NoellyneConfig.picksSupabaseAnonKey,
            'Authorization': 'Bearer ${NoellyneConfig.picksSupabaseAnonKey}',
            'Accept': 'application/json',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    return _parseList(decoded);
  }

  /// Clears in-memory cache (for unit tests or manual cache reset).
  static void clearCache() {
    _memBoard = null;
    _memFetchedAt = null;
    _inFlight = null;
  }

  static final List<DailyPick> _demo = [
    DailyPick(
      id: 'demo-1',
      match: 'Arsenal vs Chelsea',
      league: 'Premier League',
      pick: 'Arsenal Win & Over 1.5',
      odds: 1.85,
      confidence: 84,
      reasoning:
          'Arsenal have scored 2+ in 7 of 9 home games; Chelsea concede '
          '1.6 per away match. Model leans to a home win with goals.',
      streamId: 'demo-ars-che',
      tags: const ['sure2+', 'strong', 'over2.5'],
      slipCode: 'NLY-8K2F',
      tier: 'STRONG',
      units: 3.0,
      edgePct: 9.4,
    ),
  ];
}
