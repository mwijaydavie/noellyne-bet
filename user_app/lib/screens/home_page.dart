import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics_service.dart';
import '../app_theme.dart';
import '../backend_endpoint.dart';
import '../network_endpoints.dart';
import '../noellyne_config.dart';
import '../playback_routes.dart';
import '../native_player.dart';
import 'source_browser_page.dart';
import '../viewer_navigation.dart';
import 'channels_page.dart';
import 'network_diagnostics_page.dart';
import '../design/noellyne_skeleton.dart';
import '../design/noellyne_ui.dart';
import '../services/daily_picks_repository.dart';
import '../models/daily_pick.dart';
import '../widgets/theme_mode_button.dart';
import '../services/match_reminders.dart';
import '../widgets/noellyne_dock_bar.dart';
import 'reminders_page.dart';
import 'settings_page.dart';
import '../widgets/noellyne_lobby.dart';
import '../widgets/premium_match_card.dart';
import '../widgets/compact_stream_line_title.dart';
import 'daily_picks_page.dart';
import '../app_update_service.dart';
import '../live_feed_controller.dart';
import '../player_loading.dart';
import '../football_english.dart';
import '../channel_match_search.dart';

class _MatchLoadResult {
  const _MatchLoadResult(this.rows, this.label);

  final List<Map<String, dynamic>> rows;
  final String? label;
}

class _StreamCacheEntry {
  const _StreamCacheEntry(this.rows, this.fetchedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime fetchedAt;
}

class _ProtectedStreamResult {
  const _ProtectedStreamResult(this.ok, this.rows);

  final bool ok;
  final List<Map<String, dynamic>> rows;
}

class _PersistedMatchCache {
  const _PersistedMatchCache(this.rows, this.fetchedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime fetchedAt;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.backendReady,
    this.initialMatchId,
    this.initialFilter,
  });

  final Future<void>? backendReady;
  final String? initialMatchId;

  /// `Live` dock tab opens with [LobbyFilter.liveNow], `Matches` with
  /// [LobbyFilter.all] — that is the whole difference between the two tabs.
  final LobbyFilter? initialFilter;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final LiveFeedController<List<Map<String, dynamic>>> _feed;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _feedRefresh;
  DateTime? _lastBackgroundPoll;
  DateTime? _lastLiveSuccess;
  bool get _liveNeedsRefresh => _lastLiveSuccess == null ||
      DateTime.now().difference(_lastLiveSuccess!) >=
          const Duration(seconds: 60);
  bool _openingPlayer = false;
  Map<String, dynamic>? _featuredPick;
  late LobbyFilter _lobbyFilter = widget.initialFilter ?? LobbyFilter.all;
  String? _leagueFilter;
  late Future<String> _versionLabel;
  late Future<String> _updateVersionLabel;
  final Map<String, _StreamCacheEntry> _streamLinkCache = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _streamLinkInflight =
      {};
  static List<Map<String, dynamic>>? _cachedTvSchedule;
  static DateTime? _cachedTvScheduleAt;
  static const _tvScheduleTtl = Duration(minutes: 5);

  static const _publicApiBase = NoellyneConfig.publicApiBase;
  List<String> get _publicApiBases {
    final bases = publicApiBases(
      primary: _publicApiBase,
      // Prefer Cloudflare and keep the operator backup for blocked networks.
      preferVercel: false,
    );
    return bases;
  }

  static const _mirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/matches.json';
  static const _mirrorStatusBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/status.json';
  static const _authoritativeCacheKey = 'viewer_authoritative_matches_v1';
  static const _authoritativeCacheFetchedAtKey =
      'viewer_authoritative_matches_fetched_at_v1';

  // Live APIs, including the Vercel transport, are authoritative. The former
  // mirror/cache fallback remains opt-in for special builds only.
  static final bool _enableNoVpnFallback =
      const String.fromEnvironment(
        'ENABLE_NO_VPN_FALLBACK',
        defaultValue: '0',
      ).trim() ==
      '1';

  // On GitHub Pages, use the mirrored files deployed beside the app.
  // They may include safe non-keyed direct backup lines for restricted networks.
  Uri _mirrorMatchesUri() =>
      kIsWeb ? Uri.base.resolve('matches.json') : Uri.parse(_mirrorBase);
  Uri _mirrorStatusUri() =>
      kIsWeb ? Uri.base.resolve('status.json') : Uri.parse(_mirrorStatusBase);

  SupabaseClient? _supabaseClientOrNull() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<T> _hedged<T>(
    List<Future<T> Function()> attempts, {
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (attempts.isEmpty) {
      return Future<T>.error(StateError('No fallback source is configured.'));
    }

    final completer = Completer<T>();
    var nextIndex = 0;
    var running = 0;
    Object? lastError;
    StackTrace? lastStack;
    Timer? timer;

    void startNext() {
      if (completer.isCompleted || nextIndex >= attempts.length) return;

      final run = attempts[nextIndex++];
      running += 1;

      run()
          .then((value) {
            if (!completer.isCompleted) {
              timer?.cancel();
              completer.complete(value);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            running -= 1;
            lastError = error;
            lastStack = stackTrace;

            if (!completer.isCompleted && nextIndex < attempts.length) {
              startNext();
            } else if (!completer.isCompleted &&
                nextIndex >= attempts.length &&
                running == 0) {
              timer?.cancel();
              completer.completeError(
                lastError ?? StateError('All fallback sources failed.'),
                lastStack ?? StackTrace.current,
              );
            }
          });
    }

    startNext();

    if (attempts.length > 1) {
      timer = Timer.periodic(delay, (value) {
        if (completer.isCompleted || nextIndex >= attempts.length) {
          value.cancel();
          return;
        }
        startNext();
      });
    }

    return completer.future;
  }

  List<Future<T> Function()> _apiJobs<T>(Future<T> Function(String) load) {
    var winnerRecorded = false;
    return publicApiRequests<T>(
      _publicApiBases, load, onHealthy: (base) {
        if (!winnerRecorded) {
          winnerRecorded = true;
          rememberVerifiedPublicApiBase(base);
        }
      },
    );
  }

  Timer? _reminderTick;

  @override
  void initState() {
    super.initState();
    unawaited(MatchReminders.instance.load());
    NativePlayer.onOpenMatch = (id) {
      if (!mounted) return;
      for (final m in [...?_feed.data]) {
        if (m['id']?.toString() == id) {
          unawaited(openPlayer(m));
          return;
        }
      }
    };
    _reminderTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final due = MatchReminders.instance.takeDue();
      if (due.isEmpty) return;
      final first = due.first;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text('🔔 ${first.title} starts ${first.countdown}'),
            action: SnackBarAction(
              label: 'Reminders',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RemindersPage()),
              ),
            ),
          ),
        );
    });
    _feed = LiveFeedController(_loadAndRememberMatches);
    // The saved public match list paints before a slow VPN/DNS connection
    // finishes; the real authoritative response then replaces it, even [].
    unawaited(_restoreSavedLive());
    unawaited(_feed.refresh());
    unawaited(_loadFeaturedPick());
    _versionLabel = _loadVersionLabel();
    _updateVersionLabel = AppUpdateService.versionSummary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdateService.check(context);
    });
    final backendReady = widget.backendReady;
    if (backendReady == null) {
      _subscribeToUpdates();
    } else {
      unawaited(
        backendReady.then((_) {
          if (mounted) _subscribeToUpdates();
        }),
      );
    }

    // Keep metadata fresh even when Realtime is unavailable.
    _feedRefresh = Timer.periodic(const Duration(seconds: 60), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          !_openingPlayer &&
          (state == null || state == AppLifecycleState.resumed) &&
          ModalRoute.of(context)?.isCurrent != false) {
        final live = _feed.data?.any((match) => match['is_live'] == true) ?? false;
        final now = DateTime.now();
        // Keep live matches fresh; avoid repeating unchanged off-air catalog
        // requests every minute when no match is in progress.
        if (!live && _lastBackgroundPoll != null &&
            now.difference(_lastBackgroundPoll!) < const Duration(minutes: 2)) {
          return;
        }
        _lastBackgroundPoll = now;
        unawaited(refresh(silent: true));
      }
    });
  }

  void _subscribeToUpdates() {
    // The HTTP backup cannot relay WebSockets; the existing 60-second poll
    // keeps matches and stream metadata fresh on this route.
    if (usesVercelBackend || _channel != null || !mounted) return;
    final supabase = _supabaseClientOrNull();
    if (supabase != null) {
      void scheduleRefresh({bool clearStreams = false}) {
        if (clearStreams) _streamLinkCache.clear();
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () {
          if (mounted) refresh(silent: true);
        });
      }

      _channel = supabase
          .channel('v7-pro-featured')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stream_links',
            callback: (_) => scheduleRefresh(clearStreams: true),
          )
          .subscribe();
    }
  }

  Future<String> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim().isEmpty
          ? '9.8.0'
          : info.version.trim();
      final build = info.buildNumber.trim();
      return build.isEmpty
          ? 'V$version • Live streams'
          : 'V$version • build $build • Live streams';
    } catch (_) {
      return 'V9.8 • Live streams';
    }
  }

  List<Map<String, dynamic>> _sortMatchesChronologically(
    List<Map<String, dynamic>> rows,
  ) {
    rows.sort((a, b) {
      final aText = a['kickoff_at']?.toString();
      final bText = b['kickoff_at']?.toString();

      final aTime = aText == null ? null : DateTime.tryParse(aText);
      final bTime = bText == null ? null : DateTime.tryParse(bText);

      if (aTime == null && bTime == null) {
        final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;

      final timeCompare = aTime.compareTo(bTime);
      if (timeCompare != 0) return timeCompare;

      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });

    return rows;
  }

  List<Map<String, dynamic>> _mergeAvailability(
    List<Map<String, dynamic>> primary,
    List<Map<String, dynamic>> secondary,
  ) {
    final secondaryById = <String, Map<String, dynamic>>{
      for (final row in secondary)
        if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
    };

    for (final row in primary) {
      final id = row['id']?.toString() ?? '';
      final other = secondaryById[id];
      if (other == null) continue;

      final a = (row['stream_count'] as num?)?.toInt() ?? 0;
      final b = (other['stream_count'] as num?)?.toInt() ?? 0;
      if (b > a) row['stream_count'] = b;
    }

    return primary;
  }

  List<Map<String, dynamic>> _decodeMatches(String body) {
    final decoded = jsonDecode(body);
    final raw = decoded is Map<String, dynamic> ? decoded['matches'] : decoded;

    if (raw is! List) {
      throw const FormatException('Match feed is invalid.');
    }

    // Admin owns Viewer visibility; sorting never auto-hides featured games.
    return _sortMatchesChronologically(
      raw.map((row) => Map<String, dynamic>.from(row as Map)).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiFrom(String base) async {
    final response = await http
        .get(
          Uri.parse('$base/matches').replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: publicApiHeaders(base, extra: const {'Cache-Control': 'no-cache'}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Public API returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (decoded is Map && decoded['source']?.toString() == 'github') {
      // Do not let the Worker's emergency GitHub mirror beat a fresher direct
      // database response. The mirror is still used explicitly as last resort.
      throw const FormatException('Public API is using the backup mirror.');
    }

    return _decodeMatches(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  Future<List<Map<String, dynamic>>> _loadPublicApi() {
    // These are aliases of the live API. DNS failures should not strand the
    // Viewer on one hostname, even when mirror fallbacks are disabled.
    return _hedged(
      _apiJobs(_loadPublicApiFrom),
      delay: const Duration(milliseconds: 400),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiStreamsFrom(
    String base,
    String matchId,
  ) async {
    final uri =
        Uri.parse('$base/matches/${Uri.encodeComponent(matchId)}/streams')
            .replace(
              queryParameters: {
                't': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            );

    final response = await http
        .get(
          uri,
          headers: publicApiHeaders(base, extra: const {'Cache-Control': 'no-cache'}),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Public stream API returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    final raw = decoded is Map<String, dynamic> ? decoded['streams'] : decoded;
    if (raw is! List) {
      throw const FormatException('Stream response is invalid.');
    }

    final rows = raw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    if (decoded is Map<String, dynamic> && decoded['blocked_streams'] is List) {
      final blocked = (decoded['blocked_streams'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => <String, dynamic>{
              ...row,
              // A local non-playable sentinel keeps the option visible in
              // the chooser without exposing an upstream URL or key.
              'stream_url': 'blocked://keyed-dash',
            },
          );
      rows.addAll(blocked);
    }

    // HTTP 200 + an empty stream list is authoritative: Admin may have
    // removed/disabled the final line. Treat it as success, not an API error.
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiStreams(String matchId) {
    return _loadPublicApiStreamsFrom(vercelBackupBase, matchId);
  }

  Future<List<Map<String, dynamic>>> _resolveLinks(
    Map<String, dynamic> match,
  ) async {
    final matchId = match['id']?.toString().trim() ?? '';
    if (matchId.isEmpty) return const [];

    final cached = _streamLinkCache[matchId];
    final advertisedCount = (match['stream_count'] as num?)?.toInt() ?? 0;
    final cachedRows = cached?.rows ?? const <Map<String, dynamic>>[];
    final cacheIsFresh =
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(seconds: 25);
    final cacheLooksComplete =
        advertisedCount > 0 && cachedRows.length == advertisedCount;
    if (cacheIsFresh && cachedRows.isNotEmpty && cacheLooksComplete) {
      return cachedRows;
    }

    final existing = _streamLinkInflight[matchId];
    if (existing != null) return existing;

    final request = () async {
      final epgChannels = _epgChannelsFor(match);
      final isScheduleOnly =
          match['noellyne_fixture'] == true && advertisedCount <= 0;

      if (isScheduleOnly) {
        try {
          final tvRows = epgChannels.isEmpty
              ? const <Map<String, dynamic>>[]
              : await _resolveChannelBridgeLinks(epgChannels);
          if (tvRows.isNotEmpty) {
            _streamLinkCache[matchId] = _StreamCacheEntry(tvRows, DateTime.now());
          } else {
            _streamLinkCache.remove(matchId);
          }
          return tvRows;
        } finally {
          _streamLinkInflight.remove(matchId);
        }
      }

      if (!_enableNoVpnFallback) {
        try {
          var rows = playableLinks(await _loadPublicApiStreams(matchId));
          if (rows.isEmpty && epgChannels.isNotEmpty) {
            rows = await _resolveChannelBridgeLinks(epgChannels);
          }
          if (rows.isNotEmpty) {
            _streamLinkCache[matchId] = _StreamCacheEntry(rows, DateTime.now());
          } else {
            _streamLinkCache.remove(matchId);
          }
          return rows;
        } finally {
          _streamLinkInflight.remove(matchId);
        }
      }

      List<Map<String, dynamic>> mirrorRows =
          playableLinks(match['stream_links']).where((row) {
            final url = (row['stream_url'] ?? '').toString().trim();
            if (url.isEmpty) return false;
            return true;
          }).toList();

      Future<_ProtectedStreamResult> loadProtected() async {
        try {
          return _ProtectedStreamResult(
            true,
            playableLinks(await _loadPublicApiStreams(matchId)),
          );
        } catch (_) {
          return const _ProtectedStreamResult(false, <Map<String, dynamic>>[]);
        }
      }

      List<Map<String, dynamic>> rows;
      if (mirrorRows.isNotEmpty) {
        final protectedFuture = loadProtected();
        final mirrorLooksIncomplete =
            advertisedCount > 0 && mirrorRows.length < advertisedCount;

        // A successful protected API response is authoritative. Do not union
        // it with an older mirror, otherwise a server deleted/disabled in
        // Admin can remain visible until the mirror refreshes.
        final first = await Future.any<_ProtectedStreamResult>([
          protectedFuture,
          Future<_ProtectedStreamResult>.delayed(
            Duration(
              milliseconds: kIsWeb
                  ? (mirrorLooksIncomplete ? 4200 : 3200)
                  : (mirrorLooksIncomplete ? 3800 : 3000),
            ),
            () => const _ProtectedStreamResult(false, <Map<String, dynamic>>[]),
          ),
        ]);

        rows = first.ok ? first.rows : mirrorRows;

        // If the protected endpoint answers after the initial timeout, replace
        // the fallback cache with its exact authoritative set (including an
        // empty set after every Admin line was removed).
        if (!first.ok) {
          unawaited(
            protectedFuture.then((protected) {
              if (!protected.ok) return;
              if (protected.rows.isEmpty) {
                _streamLinkCache.remove(matchId);
                return;
              }
              _streamLinkCache[matchId] = _StreamCacheEntry(
                protected.rows,
                DateTime.now(),
              );
            }),
          );
        }
      } else {
        final protected = await loadProtected();
        rows = protected.ok ? protected.rows : const <Map<String, dynamic>>[];
      }

      try {
        if (rows.isEmpty && epgChannels.isNotEmpty) {
          rows = await _resolveChannelBridgeLinks(epgChannels);
        }
        if (rows.isNotEmpty) {
          _streamLinkCache[matchId] = _StreamCacheEntry(rows, DateTime.now());
        } else {
          _streamLinkCache.remove(matchId);
        }
        return rows;
      } finally {
        _streamLinkInflight.remove(matchId);
      }
    }();

    _streamLinkInflight[matchId] = request;
    return request;
  }

  Future<void> _saveAuthoritativeCache(List<Map<String, dynamic>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await prefs.setString(_authoritativeCacheKey, jsonEncode(snapshot));
      await prefs.setString(
        _authoritativeCacheFetchedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Disk cache is only a resilience layer; never block the live feed.
    }
  }

  Future<_PersistedMatchCache?> _loadAuthoritativeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_authoritativeCacheKey);
      final fetchedText = prefs.getString(_authoritativeCacheFetchedAtKey);
      final fetchedAt = fetchedText == null
          ? null
          : DateTime.tryParse(fetchedText)?.toUtc();
      if (raw == null || raw.isEmpty || fetchedAt == null) return null;

      // A sports feed must not survive indefinitely just because all remote
      // transports are blocked. Six hours is enough to bridge VPN/network
      // changes without resurrecting yesterday's LIVE matches.
      if (DateTime.now().toUtc().difference(fetchedAt) >
          const Duration(hours: 6)) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final rows = decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final visible = _sortMatchesChronologically(rows);
      // A successful authoritative [] must survive fallback/network loss too.
      // Otherwise an older GitHub mirror can resurrect deleted fixtures.
      // Missing/malformed snapshots still return null above.
      return _PersistedMatchCache(visible, fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _loadMirrorUpdatedAt() async {
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 15000;
    final uri = _mirrorStatusUri().replace(
      queryParameters: {'v': bucket.toString()},
    );

    try {
      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (decoded is! Map) return null;
      final text = decoded['updated_at']?.toString();
      return text == null ? null : DateTime.tryParse(text)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadMirror() async {
    // GitHub Pages is the reliable transport on restricted networks. Use a
    // short cache bucket so a VPN toggle/refresh cannot keep an old snapshot
    // around for a full browser cache lifetime.
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 15000;
    final uri = _mirrorMatchesUri().replace(
      queryParameters: {'v': bucket.toString()},
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mirror returned HTTP ${response.statusCode}');
    }

    final rows = _decodeMatches(utf8.decode(response.bodyBytes, allowMalformed: true));
    // The mirror may contain safe non-keyed direct backup lines. Protected
    // Cloudflare playback remains first choice; these are used only when that
    // API is unreachable on restricted networks.
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseMatches() async {
    final client = _supabaseClientOrNull();
    if (client == null) {
      throw StateError('Supabase is unavailable on this network.');
    }

    // Complete this fallback only when its safe availability counts are ready.
    // If either query fails, another hedged source can still return a full feed.
    // The count view exposes no upstream URLs, headers, or playback keys.
    final data = await Future.wait<List<Map<String, dynamic>>>([
      client
          .from('matches')
          .select('''
            id,league,home_team,away_team,home_logo_url,away_logo_url,
            kickoff_at,is_live,sort_order,is_featured,publish_state,updated_at
          ''')
          .eq('is_active', true)
          .eq('publish_state', 'published')
          .eq('is_featured', true)
          .order('kickoff_at')
          .order('sort_order')
          .timeout(const Duration(seconds: 5)),
      client
          .from('match_stream_counts')
          .select('match_id,stream_count')
          .timeout(const Duration(seconds: 5)),
    ]);

    final rows = List<Map<String, dynamic>>.from(data[0]);
    for (final row in rows) {
      row['stream_count'] = 0;
      row['stream_links'] = const <Map<String, dynamic>>[];
    }
    final counts = data[1]
        .map(
          (row) => <String, dynamic>{
            'id': row['match_id'],
            'stream_count': (row['stream_count'] as num?)?.toInt() ?? 0,
          },
        )
        .toList();
    return _sortMatchesChronologically(_mergeAvailability(rows, counts));
  }

  List<Map<String, dynamic>> _mergeMirrorBackupsIntoMatches(
    List<Map<String, dynamic>> authoritative,
    List<Map<String, dynamic>> mirror,
  ) {
    final mirrorById = <String, Map<String, dynamic>>{
      for (final row in mirror)
        if ((row['id']?.toString().trim().isNotEmpty ?? false))
          row['id'].toString(): row,
    };

    return authoritative.map((row) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) return row;

      final backup = mirrorById[id];
      if (backup == null) return row;

      final existingLinks = playableLinks(row['stream_links']);
      final backupLinks = playableLinks(backup['stream_links']);

      final seenLinks = <String>{};
      final mergedLinks = <Map<String, dynamic>>[];

      String linkKey(Map<String, dynamic> link) {
        final id = link['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return 'id:$id';
        final url = link['stream_url']?.toString().trim() ?? '';
        return 'url:$url';
      }

      for (final link in [...existingLinks, ...backupLinks]) {
        final key = linkKey(link);
        if (key == 'url:' || !seenLinks.add(key)) continue;
        mergedLinks.add(link);
      }

      if (mergedLinks.isNotEmpty) {
        row['stream_links'] = mergedLinks;
        row['public_stream_count'] = mergedLinks.length;
      }

      // The authoritative feed owns stream_count, including zero. Never
      // resurrect a deleted final line from an older mirror count.

      return row;
    }).toList();
  }

  Future<void> _restoreSavedLive() async {
    final cached = await _loadAuthoritativeCache();
    if (mounted && cached != null) {
      _feed.seedIfMissing(cached.rows);
    }
  }

  Future<List<Map<String, dynamic>>> _loadAndRememberMatches() async {
    final rows = await loadMatches();
    _lastLiveSuccess = DateTime.now();
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadNoellyneFixtures() async {
    if (!NoellyneConfig.picksSupabaseEnabled) {
      return const <Map<String, dynamic>>[];
    }
    try {
      final base = NoellyneConfig.picksSupabaseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        '$base/rest/v1/fixtures'
        '?is_active=eq.true'
        '&order=kickoff_at.asc'
        '&limit=100',
      );
      final resp = await http
          .get(
            uri,
            headers: const {
              'apikey': NoellyneConfig.picksSupabaseAnonKey,
              'Authorization': 'Bearer ${NoellyneConfig.picksSupabaseAnonKey}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <Map<String, dynamic>>[];
      }
      final decoded =
          jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (decoded is! List) return const <Map<String, dynamic>>[];
      final nowUtc = DateTime.now().toUtc();
      return decoded
          .whereType<Map>()
          .map((row) {
            final m = Map<String, dynamic>.from(row);
            final kickoffStr = (m['kickoff_at'] ?? '').toString();
            final kickoffUtc = DateTime.tryParse(kickoffStr)?.toUtc();
            // Client-side defense-in-depth: never let a stale fixture older than
            // 3h45m masquerade as LIVE even if upstream sync lagged.
            final age = kickoffUtc == null ? null : nowUtc.difference(kickoffUtc);
            final stale = age != null && age > const Duration(hours: 3, minutes: 45);
            if (stale) return null;
            final withinLiveWindow = age == null ||
                (age >= const Duration(minutes: -20) &&
                    age <= const Duration(hours: 3, minutes: 30));
            return <String, dynamic>{
              'id': m['id']?.toString() ?? '',
              'league': (m['league'] ?? 'Football').toString(),
              'sport': (m['sport'] ?? 'football').toString(),
              'home_team': (m['home_team'] ?? '').toString(),
              'away_team': (m['away_team'] ?? '').toString(),
              'home_logo_url': (m['home_logo_url'] ?? '').toString(),
              'away_logo_url': (m['away_logo_url'] ?? '').toString(),
              'kickoff_at': kickoffStr,
              'is_live': m['is_live'] == true && withinLiveWindow,
              'home_score': m['home_score'],
              'away_score': m['away_score'],
              'clock': (m['clock'] ?? '').toString(),
              'odds_summary': (m['odds_summary'] ?? '').toString(),
              'stream_count': 0,
              'stream_links': const <Map<String, dynamic>>[],
              'noellyne_fixture': true,
            };
          })
          .whereType<Map<String, dynamic>>()
          .where((m) =>
              (m['home_team'] as String).isNotEmpty &&
              (m['away_team'] as String).isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Fetch EPG-linked TV channels (`/tv-schedule`) so Home fixtures without
  /// direct per-match stream lines automatically link to live TV channels
  /// (e.g. beIN Sports 2, Premier Sports 1 HD, TNT Sports).
  Future<List<Map<String, dynamic>>> _loadTvScheduleChannels() async {
    final cached = _cachedTvSchedule;
    final at = _cachedTvScheduleAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _tvScheduleTtl) {
      return cached;
    }

    final nowUtc = DateTime.now().toUtc();
    final windowStart = nowUtc.subtract(const Duration(hours: 6));
    final date =
        '${windowStart.year}-${windowStart.month.toString().padLeft(2, '0')}-${windowStart.day.toString().padLeft(2, '0')}';

    final bases = publicApiBases()
        .where((base) => base != vercelBackupBase)
        .toList(growable: false);
    if (bases.isEmpty) return cached ?? const <Map<String, dynamic>>[];

    for (final base in bases) {
      try {
        final resp = await http
            .get(
              Uri.parse('$base/tv-schedule?date=$date&days=3'),
              headers: publicApiHeaders(base),
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) continue;
        final decoded =
            jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (decoded is! Map || decoded['channels'] is! List) continue;
        final parsed = <Map<String, dynamic>>[];
        for (final raw in decoded['channels'] as List) {
          if (raw is! Map || raw['matchedEPG'] != true) continue;
          final id = raw['id']?.toString().trim() ?? '';
          final name = raw['name']?.toString().trim() ?? '';
          if (id.isEmpty || name.isEmpty) continue;
          final progs = (raw['programmes'] as List? ?? const [])
              .whereType<Map>()
              .where((p) => currentFootballProgramme(p, now: nowUtc))
              .map((p) => Map<String, dynamic>.from(p))
              .toList(growable: false);
          if (progs.isEmpty) continue;
          parsed.add(<String, dynamic>{
            'id': id,
            'name': name,
            'programmes': progs,
          });
        }
        _cachedTvSchedule = parsed;
        _cachedTvScheduleAt = DateTime.now();
        return parsed;
      } catch (_) {
        continue;
      }
    }
    return cached ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _epgChannelsFor(Map<String, dynamic> m) {
    final raw = m['epg_channels'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['id'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
  }

  String _cleanChannelDisplayName(String raw) {
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'_+'), ' ');
    name = name.replaceAll(
      RegExp(r'\b(Digital Mono EN|Digital Stereo EN)\b', caseSensitive: false),
      '',
    );
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<Map<String, dynamic>> _attachEpgChannels(
    List<Map<String, dynamic>> matches,
    List<Map<String, dynamic>> tvChannels,
  ) {
    if (tvChannels.isEmpty || matches.isEmpty) return matches;
    final nowUtc = DateTime.now().toUtc();
    for (final m in matches) {
      final matched = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      for (final ch in tvChannels) {
        final chId = (ch['id'] ?? '').toString();
        if (chId.isEmpty || seenIds.contains(chId)) continue;
        final progs = ch['programmes'];
        if (progs is! List) continue;
        for (final rawProg in progs) {
          if (rawProg is! Map) continue;
          if (!programmeCoversMatch(rawProg, m, now: nowUtc)) continue;
          seenIds.add(chId);
          final chName = _cleanChannelDisplayName((ch['name'] ?? '').toString());
          matched.add(<String, dynamic>{
            'id': chId,
            'name': chName.isEmpty ? (ch['name'] ?? 'TV Channel').toString() : chName,
            'raw_name': (ch['name'] ?? '').toString(),
            'programme': (rawProg['title'] ?? rawProg['subtitle'] ?? '').toString(),
            'is_live_now': programmeIsLiveNow(rawProg, now: nowUtc),
            'start': rawProg['start'],
            'end': rawProg['end'],
          });
          break;
        }
      }
      if (matched.isNotEmpty) {
        matched.sort((a, b) {
          final aLive = a['is_live_now'] == true ? 0 : 1;
          final bLive = b['is_live_now'] == true ? 0 : 1;
          if (aLive != bLive) return aLive.compareTo(bLive);
          final aClean = (a['raw_name'] ?? '').toString().contains('_') ? 1 : 0;
          final bClean = (b['raw_name'] ?? '').toString().contains('_') ? 1 : 0;
          if (aClean != bClean) return aClean.compareTo(bClean);
          return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
        });
        m['epg_channels'] = matched.take(8).toList(growable: false);
      }
    }
    return matches;
  }

  Future<List<Map<String, dynamic>>> _resolveSingleChannelStreams(
    Map<String, dynamic> ch,
  ) async {
    final chId = (ch['id'] ?? '').toString().trim();
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(chId)) {
      return const <Map<String, dynamic>>[];
    }
    final chName = (ch['name'] ?? 'TV Channel').toString().trim();
    final bases = publicApiBases()
        .where((base) => base != vercelBackupBase)
        .toList(growable: false);
    for (final base in bases) {
      try {
        final resp = await http
            .get(
              Uri.parse('$base/channels/$chId/streams'),
              headers: publicApiHeaders(base),
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        final decoded =
            jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (decoded is! Map || decoded['ok'] != true || decoded['streams'] is! List) {
          continue;
        }
        final out = <Map<String, dynamic>>[];
        for (final raw in decoded['streams'] as List) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final url = (row['stream_url'] ?? '').toString().trim();
          final uri = Uri.tryParse(url);
          if (uri == null ||
              uri.scheme != 'https' ||
              uri.host.isEmpty ||
              row['protected_proxy'] != true) {
            continue;
          }
          final rawLabel = (row['label'] ?? '').toString().trim();
          final label = rawLabel.isEmpty
              ? chName
              : (rawLabel.toLowerCase().contains(chName.toLowerCase())
                  ? rawLabel
                  : '$chName · $rawLabel');
          out.add(<String, dynamic>{
            'id': row['id']?.toString() ?? '$chId-${out.length}',
            'label': label,
            'stream_url': url,
            'stream_type': (row['stream_type'] ?? 'auto').toString(),
            'key_id': (row['key_id'] ?? '').toString(),
            'key_data': (row['key_data'] ?? '').toString(),
            'resolution': (row['resolution'] ?? '').toString(),
            'referer': (row['referer'] ?? '').toString(),
            'origin': (row['origin'] ?? '').toString(),
            'health_status': 'healthy',
            'priority': (row['priority'] as num?)?.toInt() ?? 10,
            'is_active': true,
            'use_webview': false,
            'from_tv_channel': true,
          });
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        continue;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _resolveChannelBridgeLinks(
    List<Map<String, dynamic>> epgChannels,
  ) async {
    if (epgChannels.isEmpty) return const <Map<String, dynamic>>[];
    final candidates = epgChannels.take(4).toList(growable: false);
    final batches = await Future.wait(
      candidates.map(_resolveSingleChannelStreams),
    );
    final seenUrls = <String>{};
    final combined = <Map<String, dynamic>>[];
    for (final list in batches) {
      for (final row in list) {
        final url = (row['stream_url'] ?? '').toString().trim();
        if (url.isEmpty || !seenUrls.add(url)) continue;
        combined.add(row);
      }
    }
    return combined;
  }

  String _normTeamForFixtureMerge(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(
        RegExp(r'\b(fc|sc|cf|ac|afc|united|city|club|de|da|do|sv|vfl|rb|cd|ud|rcd|as|ss|ssc|us|fk|sk|nk|if|bk|ik)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _sameTeamForFixtureMerge(String a, String b) {
    final na = _normTeamForFixtureMerge(a);
    final nb = _normTeamForFixtureMerge(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb || na.contains(nb) || nb.contains(na)) return true;
    final ta = na.split(' ').where((t) => t.length >= 3).toList();
    final tb = nb.split(' ').where((t) => t.length >= 3).toSet();
    return ta.isNotEmpty && ta.any(tb.contains);
  }

  List<Map<String, dynamic>> _mergeNoellyneFixtures(
    List<Map<String, dynamic>> streamRows,
    List<Map<String, dynamic>> fixtures,
  ) {
    if (fixtures.isEmpty) return streamRows;
    final merged = streamRows.map((r) => Map<String, dynamic>.from(r)).toList();

    for (final fx in fixtures) {
      final fh = (fx['home_team'] ?? '').toString();
      final fa = (fx['away_team'] ?? '').toString();
      Map<String, dynamic>? existing;
      for (final row in merged) {
        final rh = (row['home_team'] ?? '').toString();
        final ra = (row['away_team'] ?? '').toString();
        if ((_sameTeamForFixtureMerge(rh, fh) &&
                _sameTeamForFixtureMerge(ra, fa)) ||
            (_sameTeamForFixtureMerge(rh, fa) &&
                _sameTeamForFixtureMerge(ra, fh))) {
          existing = row;
          break;
        }
      }
      if (existing != null) {
        // Enrich existing stream match with live score/logos/odds if missing.
        if ((existing['home_logo_url'] ?? '').toString().trim().isEmpty &&
            (fx['home_logo_url'] ?? '').toString().trim().isNotEmpty) {
          existing['home_logo_url'] = fx['home_logo_url'];
        }
        if ((existing['away_logo_url'] ?? '').toString().trim().isEmpty &&
            (fx['away_logo_url'] ?? '').toString().trim().isNotEmpty) {
          existing['away_logo_url'] = fx['away_logo_url'];
        }
        if ((existing['odds_summary'] ?? '').toString().trim().isEmpty &&
            (fx['odds_summary'] ?? '').toString().trim().isNotEmpty) {
          existing['odds_summary'] = fx['odds_summary'];
        }
        if (existing['home_score'] == null && fx['home_score'] != null) {
          existing['home_score'] = fx['home_score'];
        }
        if (existing['away_score'] == null && fx['away_score'] != null) {
          existing['away_score'] = fx['away_score'];
        }
        if ((existing['clock'] ?? '').toString().trim().isEmpty &&
            (fx['clock'] ?? '').toString().trim().isNotEmpty) {
          existing['clock'] = fx['clock'];
        }
        if (fx['is_live'] == true) {
          existing['is_live'] = true;
        }
      } else {
        merged.add(fx);
      }
    }
    return _sortMatchesChronologically(merged);
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final started = DateTime.now();
    final fixturesFuture = _loadNoellyneFixtures();
    final tvScheduleFuture = _loadTvScheduleChannels();

    if (!_enableNoVpnFallback) {
      List<Map<String, dynamic>> streamRows;
      try {
        streamRows = await _loadPublicApi();
      } catch (_) {
        streamRows = const <Map<String, dynamic>>[];
      }
      final fixtures = await fixturesFuture;
      final tvChannels = await tvScheduleFuture;
      final rows = _attachEpgChannels(
        _mergeNoellyneFixtures(streamRows, fixtures),
        tvChannels,
      );
      if (rows.isEmpty && streamRows.isEmpty) {
        throw StateError('No match sources reachable.');
      }
      unawaited(
        AnalyticsService.capture(
          'match feed loaded',
          properties: {
            'source': 'Multi-source live + Noellyne fixtures',
            'match_count': rows.length,
            'latency_ms': DateTime.now().difference(started).inMilliseconds,
          },
        ),
      );
      unawaited(_saveAuthoritativeCache(rows));
      return rows;
    }

    // Cloudflare, Vercel and Supabase are authoritative. Race those first.
    // Only fall back to GitHub after both fail, otherwise an older mirror can
    // win the race and resurrect deleted matches or stale LIVE state.
    final authoritative = <Future<_MatchLoadResult> Function()>[
      () async => _MatchLoadResult(await _loadPublicApi(), 'Fast public API'),
    ];

    if (_supabaseClientOrNull() != null) {
      authoritative.add(
        () async =>
            _MatchLoadResult(await _loadSupabaseMatches(), 'Direct database'),
      );
    }

    _MatchLoadResult result;
    try {
      result = await _hedged(
        authoritative,
        delay: const Duration(milliseconds: 500),
      );

      // Save the latest authoritative match list before any mirror enrichment.
      // If VPN/API routing later fails, this prevents an older GitHub snapshot
      // from replacing a newer match that the phone has already seen.
      unawaited(_saveAuthoritativeCache(result.rows));

      // Authoritative sources intentionally expose only availability counts.
      // Add safe non-keyed mirror lines so WATCH still works when the
      // protected stream endpoint is blocked on the current phone network.
      try {
        final mirror = await _loadMirror().timeout(const Duration(seconds: 2));
        result = _MatchLoadResult(
          _mergeMirrorBackupsIntoMatches(result.rows, mirror),
          result.label,
        );
      } catch (_) {
        // Preserve the fresh authoritative match list if mirror enrichment
        // happens to be unavailable.
      }
    } catch (_) {
      // On restricted networks GitHub may be the only reachable transport.
      // Compare its publish timestamp with the last authoritative feed saved
      // on this phone. Never regress from a newer known feed to an older
      // mirror just because VPN was turned off.
      final cachedFuture = _loadAuthoritativeCache();
      final mirrorStatusFuture = _loadMirrorUpdatedAt();
      try {
        final mirror = await _loadMirror();
        final cached = await cachedFuture;
        final mirrorUpdatedAt = await mirrorStatusFuture;
        final cacheIsNewer =
            cached != null &&
            (mirrorUpdatedAt == null ||
                cached.fetchedAt.isAfter(
                  mirrorUpdatedAt.add(const Duration(minutes: 1)),
                ));

        if (cacheIsNewer) {
          result = _MatchLoadResult(
            _mergeMirrorBackupsIntoMatches(cached.rows, mirror),
            'Saved live feed',
          );
        } else {
          result = _MatchLoadResult(mirror, 'Backup feed');
        }
      } catch (_) {
        final cached = await cachedFuture;
        if (cached == null) rethrow;
        result = _MatchLoadResult(cached.rows, 'Saved live feed');
      }
    }

    final mergedFallback = _attachEpgChannels(
      _mergeNoellyneFixtures(
        result.rows,
        await fixturesFuture,
      ),
      await tvScheduleFuture,
    );

    unawaited(
      AnalyticsService.capture(
        'match feed loaded',
        properties: {
          'source': result.label ?? 'unknown',
          'match_count': mergedFallback.length,
          'latency_ms': DateTime.now().difference(started).inMilliseconds,
        },
      ),
    );

    return mergedFallback;
  }

  Future<void> refresh({bool silent = false}) async {
    await _feed.refresh();
    if (!silent && mounted && _feed.hasData && _feed.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not refresh. Showing the previous results.'),
        ),
      );
    }
  }

  List<Map<String, dynamic>> playableLinks(dynamic raw) {
    final now = DateTime.now();
    final rows = List<Map<String, dynamic>>.from(raw ?? const []);
    final filtered = rows.where((row) {
      if (row['is_active'] != true) return false;
      final fromText = row['available_from']?.toString();
      final expiryText = row['expires_at']?.toString();
      if (fromText != null && fromText.isNotEmpty) {
        if (now.isBefore(DateTime.parse(fromText).toLocal())) return false;
      }
      if (expiryText != null && expiryText.isNotEmpty) {
        if (!now.isBefore(DateTime.parse(expiryText).toLocal())) return false;
      }
      final useWeb = row['use_webview'] == true;
      final url = useWeb
          ? (row['webview_url']?.toString() ?? '')
          : (row['stream_url']?.toString() ?? '');
      return url.trim().isNotEmpty;
    }).toList();

    int healthRank(Map<String, dynamic> row) {
      switch ((row['health_status'] ?? 'unknown').toString()) {
        case 'healthy':
          return 0;
        case 'unknown':
          return 1;
        case 'slow':
          return 2;
        default:
          return 3;
      }
    }

    int formatRank(Map<String, dynamic> row) {
      if (row['use_webview'] == true) return 9;
      final type = (row['stream_type'] ?? 'auto').toString().toLowerCase();
      final url = (row['stream_url'] ?? '').toString().toLowerCase();

      if (type == 'hls' || type == 'm3u8' || url.contains('.m3u8')) return 0;

      // On Web, especially iPhone WebKit, current mpegts.js can play healthy
      // FLV via ManagedMediaSource while ClearKey DASH is not supported by
      // Safari. Put FLV ahead of DASH in the chooser so the first tap has the
      // best chance of actually starting.
      if (kIsWeb && (type == 'flv' || url.contains('.flv'))) return 1;
      if (type == 'mp4' || url.contains('.mp4')) return 2;
      if (type == 'dash' || type == 'mpd' || url.contains('.mpd')) return 3;
      if (type == 'auto') return 4;
      if (type == 'flv' || url.contains('.flv')) return 5;
      return 6;
    }

    filtered.sort((a, b) {
      final h = healthRank(a).compareTo(healthRank(b));
      if (h != 0) return h;

      // HLS first gives Android, iPhone and browser clients the most portable
      // source before falling back to DASH/direct/FLV.
      final f = formatRank(a).compareTo(formatRank(b));
      if (f != 0) return f;

      final ap = (a['priority'] as num?)?.toInt() ?? 100;
      final bp = (b['priority'] as num?)?.toInt() ?? 100;
      return ap.compareTo(bp);
    });
    return filtered;
  }

  String _normalizedWebReferer(
    Map<String, dynamic> link,
    Map<String, dynamic> match,
  ) {
    final referer = (link['referer'] ?? '').toString().trim();
    if (!kIsWeb || referer.isEmpty) return referer;

    Uri? uri;
    try {
      uri = Uri.parse(referer);
    } catch (_) {
      return referer;
    }

    final host = uri.host.toLowerCase();
    final isFawa =
        host == 'fawanews.sc' ||
        host == 'www.fawanews.sc' ||
        host.endsWith('.fawanews.sc');
    if (!isFawa) return referer;

    final path = uri.path.trim();
    if (path.isNotEmpty && path != '/') return referer;

    final home = (match['home_team'] ?? '').toString().trim();
    final away = (match['away_team'] ?? '').toString().trim();
    if (home.isEmpty || away.isEmpty) return referer;

    final slug = Uri.encodeComponent('$home vs $away');
    return 'http://www.fawanews.sc/$slug.html';
  }

  /// Shape the native portrait feed understands: id/name/subtitle/isLive.
  Future<void> _loadFeaturedPick() async {
    try {
      final picks = await DailyPicksRepository().fetch(limit: 5);
      if (picks.isEmpty || !mounted) return;
      final DailyPick pick = picks.first;
      setState(() {
        _featuredPick = <String, dynamic>{
          'match': pick.match,
          'league': pick.league,
          'selection': pick.pick,
          // Native player reads `pick`; keep both keys in sync.
          'pick': pick.pick,
          'odds': pick.odds,
          'confidence': pick.confidence,
          'units': pick.units,
          'reasoning': pick.reasoning,
          'tier': pick.tier,
        };
      });
    } catch (_) {
      // Picks are optional chrome inside the player.
    }
  }

  List<Map<String, dynamic>> _suggestedChannels(Map<String, dynamic> current) {
    final rows = [...?_feed.data];
    final currentId = current['id']?.toString();
    final out = <Map<String, dynamic>>[];
    for (final m in rows) {
      if (m['id']?.toString() == currentId) continue;
      final home = englishKnownFootballName((m['home_team'] ?? '').toString());
      final away = englishKnownFootballName((m['away_team'] ?? '').toString());
      final league = englishKnownFootballName(
        (m['league'] ?? '').toString(),
        kind: 'league',
      );
      final lines = _lineCountFor(m);
      final carried = <Map<String, dynamic>>[];
      for (final entry in playableLinks(m['stream_links']).asMap().entries) {
        final x = entry.value;
        final url = (x['stream_url'] ?? '').toString();
        if (url.isEmpty || x['use_webview'] == true) continue;
        carried.add(<String, dynamic>{
          'label': _streamDisplayLabel(x, entry.key),
          'streamType': (x['stream_type'] ?? 'auto').toString(),
          'url': url,
          'referer': _normalizedWebReferer(x, m),
          'origin': (x['origin'] ?? '').toString(),
          'keyId': (x['key_id'] ?? '').toString(),
          'keyData': (x['key_data'] ?? '').toString(),
          'resolution': (x['resolution'] ?? '').toString(),
        });
        if (carried.length >= 12) break;
      }
      if (carried.isEmpty) continue;
      out.add({
        'id': m['id']?.toString() ?? '',
        'name': league.isEmpty ? '$home vs $away' : league,
        'epgTitle': _matchTitle(m),
        'logoUrl': (m['home_logo_url'] ?? m['home_logo'] ?? '').toString(),
        'category': league,
        'subtitle': _isOnAir(m)
            ? '$home vs $away \u00B7 LIVE'
            : '$home vs $away \u00B7 $lines line${lines == 1 ? '' : 's'}',
        'isLive': _isOnAir(m),
        'lineCount': lines,
        'sourcesJson': jsonEncode(carried),
      });
      if (out.length >= 12) break;
    }
    return out;
  }

  Future<void> openPlayer(Map<String, dynamic> match) async {
    if (_openingPlayer || !mounted) return;
    _openingPlayer = true;
    try {
      await _openPlayer(match);
    } finally {
      _openingPlayer = false;
    }
  }

  String _matchTitle(Map<String, dynamic> match) =>
      '${englishKnownFootballName((match['home_team'] ?? 'Home').toString())}'
      ' vs ${englishKnownFootballName((match['away_team'] ?? 'Away').toString())}';

  String _streamDisplayLabel(Map<String, dynamic> row, int index) {
    final raw = shortMatchLineLabel((row['label'] ?? row['resolution'] ?? 'Server').toString());
    return RegExp(r'^YYZB\b', caseSensitive: false).hasMatch(raw)
        ? englishStreamLabel(raw, index: index)
        : raw;
  }

  Future<void> _openPlayer(Map<String, dynamic> match) async {
    final matchId = match['id']?.toString() ?? '';
    final watchToSourcesClock = Stopwatch()..start();
    unawaited(
      AnalyticsService.capture(
        'watch tapped',
        properties: {
          'match_id': matchId,
          'league': (match['league'] ?? '').toString(),
          'is_live': match['is_live'] == true,
          'advertised_lines': (match['stream_count'] as num?)?.toInt() ?? 0,
        },
      ),
    );

    final epgChannels = _epgChannelsFor(match);
    final hasAnyStreamCandidate =
        match['noellyne_fixture'] != true ||
        _lineCountFor(match) > 0 ||
        epgChannels.isNotEmpty;
    if (!hasAnyStreamCandidate) {
      if (_isOnAir(match)) {
        await _openLiveChannelFallbackSheet(match);
        return;
      }
    }

    final links = await loadPlayerSources(context, () => _resolveLinks(match));
    watchToSourcesClock.stop();
    if (links == null || !mounted) return;
    // Playback startup_ms starts only after the player opens. This separate
    // phase shows the time users spend waiting for protected line metadata.
    // Emit only counts and durations; never a stream URL, key, or token.
    unawaited(
      AnalyticsService.capture(
        'stream sources loaded',
        properties: {
          'source': 'featured',
          'match_id': matchId,
          'resolution_ms': watchToSourcesClock.elapsedMilliseconds,
          'count': links.length,
        },
      ),
    );

    // Keep the visible count synchronized after link resolution. The protected
    // API path now replaces stale mirror rows, so this can correct both added
    // and removed Admin servers.
    final currentCount = (match['stream_count'] as num?)?.toInt() ?? 0;
    if (links.length != currentCount) {
      match['stream_count'] = links.length;
      match['stream_links'] = links;
      match['public_stream_count'] = links.length;
      if (mounted) setState(() {});
    }

    if (links.isEmpty) {
      await AnalyticsService.capture(
        'stream unavailable',
        properties: {
          'match_id': matchId,
          'reason': 'protected_api_returned_no_lines',
          'advertised_lines': (match['stream_count'] as num?)?.toInt() ?? 0,
        },
      );
      if (!mounted) return;
      if (_isOnAir(match)) {
        await _openLiveChannelFallbackSheet(match);
        return;
      }
      final advertised = (match['stream_count'] as num?)?.toInt() ?? 0;
      final isScheduleFixture = match['noellyne_fixture'] == true;
      final title = _matchTitle(match);
      final league = (match['league'] ?? '').toString();
      final odds = (match['odds_summary'] ?? '').toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              advertised > 0
                  ? 'Could not load the $advertised configured line(s). '
                      'Please tap WATCH again in a moment.'
                  : isScheduleFixture
                      ? 'Stream links open near kickoff${odds.isNotEmpty ? ' · $odds' : ''}. Ask AI for preview?'
                      : 'Stream is not available yet.',
            ),
            action: SnackBarAction(
              label: 'Ask AI',
              onPressed: () {
                openAiChat(
                  context,
                  initialPrompt:
                      'Chambua mechi ya $title ($league) leo${odds.isNotEmpty ? ' (Odds: $odds)' : ''}. '
                      'Nani ana nafasi kubwa ya kushinda na soko gani ni salama?',
                  matchContext: {
                    'match': title,
                    'league': league,
                    'sport': (match['sport'] ?? 'football').toString(),
                    if (odds.isNotEmpty) 'odds_summary': odds,
                  },
                );
              },
            ),
          ),
        );
      return;
    }

    final nativeSources = playbackSources(
      links
          .where((x) => x['use_webview'] != true)
          .toList()
          .asMap()
          .entries
          .map((entry) {
            final x = entry.value;
            return <String, dynamic>{
              'id': x['id']?.toString(),
              'label': _streamDisplayLabel(x, entry.key),
              'streamType': (x['stream_type'] ?? 'auto').toString(),
              'url': (x['stream_url'] ?? '').toString(),
              'referer': _normalizedWebReferer(x, match),
              'origin': (x['origin'] ?? '').toString(),
              'keyId': (x['key_id'] ?? '').toString(),
              'keyData': (x['key_data'] ?? '').toString(),
              'resolution': (x['resolution'] ?? '').toString(),
              'healthStatus': (x['health_status'] ?? 'unknown').toString(),
              'priority': (x['priority'] as num?)?.toInt() ?? 100,
              'blockedReason': (x['blocked_reason'] ?? '').toString(),
              'viewerMessage': (x['viewer_message'] ?? '').toString(),
            };
          })
          .where((x) => (x['url'] as String).trim().isNotEmpty)
          .toList(),
    );

    final visibleIndices = visiblePlaybackIndices(nativeSources);
    if (nativeSources.isEmpty) {
      await AnalyticsService.capture(
        'stream unavailable',
        properties: {
          'match_id': matchId,
          'reason': 'no_native_sources',
          'resolved_lines': links.length,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This match currently has no native stream.'),
        ),
      );
      return;
    }

    var selectedIndex = 0;
    var chooserDurationMs = 0;

    // Web downloads its player engine while the user is choosing a line,
    // removing that network wait from the first-frame startup measurement.
    // Android and iOS implement this as a no-op because their engines ship in
    // the app.
    NativePlayer.prewarm(sources: nativeSources);

    {
      final chooserClock = Stopwatch()..start();
      final picked = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final colors = Theme.of(sheetContext).colorScheme;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: nativeSources.length <= 4 ? .52 : .72,
            minChildSize: .38,
            maxChildSize: .90,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose line',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Best available lines are shown first',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _matchTitle(match),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${visibleIndices.length} lines',
                            style: TextStyle(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
                      itemCount: visibleIndices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final sourceIndex = visibleIndices[index];
                        final source = nativeSources[sourceIndex];
                        final blocked = (source['blockedReason'] ?? '')
                            .toString().trim().isNotEmpty;
                        final lineName = compactStreamLineTitle(
                          label: (source['label'] ?? '').toString(),
                          resolution: (source['resolution'] ?? '').toString(),
                          streamType: (source['streamType'] ?? 'auto').toString(),
                          index: sourceIndex,
                        );
                        return Material(
                          color: colors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: colors.outlineVariant.withValues(alpha: .55),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 1,
                            ),
                            onTap: blocked
                                ? null
                                : () => Navigator.pop(sheetContext, sourceIndex),
                            leading: Icon(blocked
                                ? Icons.lock_outline_rounded
                                : Icons.live_tv_rounded, size: 20),
                            title: Text(
                              lineName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      chooserClock.stop();
      if (picked == null) return;
      selectedIndex = picked;
      // Included in the stream-selected event below; user choice time must
      // not be mistaken for network or video buffering latency.
      chooserDurationMs = chooserClock.elapsedMilliseconds;
    }

    final selectedSource = nativeSources[selectedIndex];
    unawaited(
      AnalyticsService.capture(
        'stream selected',
        properties: {
          'match_id': matchId,
          'line_count': nativeSources.length,
          'selected_index': selectedIndex,
          'chooser_ms': chooserDurationMs,
          'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
          'resolution': (selectedSource['resolution'] ?? '').toString(),
          'health_status': (selectedSource['healthStatus'] ?? 'unknown')
              .toString(),
        },
      ),
    );

    try {
      if (!mounted) return;
      debugPrint(
        'NoellynePlayer: sending ${_suggestedChannels(match).length} suggested channels',
      );
      await NativePlayer.open(
        context: context,
        sources: nativeSources,
        selectedIndex: selectedIndex,
        title: _matchTitle(match),
        matchId: matchId,
        suggestedChannels: _suggestedChannels(match),
        featuredPick: _featuredPick,
        activeTabIndex: _lobbyFilter == LobbyFilter.liveNow ? 0 : 1,
        isDark: Theme.of(context).brightness == Brightness.dark,
      );
      await AnalyticsService.capture(
        'player opened',
        properties: {
          'match_id': matchId,
          'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
        },
      );
    } catch (_) {
      await AnalyticsService.capture(
        'player open failed',
        properties: {
          'match_id': matchId,
          'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player could not be opened.')),
      );
    }
  }

  Future<void> _openAppMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.sports_soccer_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Noellyne',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FutureBuilder<String>(
                          future: _versionLabel,
                          builder: (context, snapshot) => Text(
                            snapshot.data ?? 'V9.8 • Live streams',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text(
                  'Appearance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('System, light or dark mode'),
                trailing: const ThemeModeButton(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text(
                  'Connection diagnostics',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Check API and fallback connectivity'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NetworkDiagnosticsPage(),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text(
                  'Check for updates',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: FutureBuilder<String>(
                  future: _updateVersionLabel,
                  builder: (context, snapshot) => Text(
                    snapshot.data ?? 'Check and install the latest Noellyne APK',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  AppUpdateService.check(context, force: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLiveChannelFallbackSheet(Map<String, dynamic> match) async {
    if (!mounted) return;
    final title = _matchTitle(match);
    final league = englishKnownFootballName(
      (match['league'] ?? 'Football').toString(),
      kind: 'league',
    );
    final odds = (match['odds_summary'] ?? '').toString();
    final suggestedQuery = suggestedChannelQueryForLeague(league);
    final score = _scoreTextFor(match);
    final clock = _clockTextFor(match);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  league,
                  if (score != null) score,
                  if (clock != null) clock,
                  'Live on Sports TV channels',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ChannelsPage(initialSearch: suggestedQuery),
                    ),
                  );
                },
                icon: const Icon(Icons.live_tv_rounded),
                label: Text('Open Channels ($suggestedQuery)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChannelsPage(initialSearch: ''),
                    ),
                  );
                },
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Browse All 390+ Live Channels'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  openAiChat(
                    context,
                    initialPrompt:
                        'Mechi ya $title ($league) inaendelea live${score != null ? ' ($score${clock != null ? ' $clock' : ''})' : ''}'
                        '${odds.isNotEmpty ? ' (Odds: $odds)' : ''}. '
                        'Chambua mwenendo na soko bora la live sasa.',
                    matchContext: {
                      'match': title,
                      'league': league,
                      'sport': (match['sport'] ?? 'football').toString(),
                      if (score != null) 'score': score,
                      if (odds.isNotEmpty) 'odds_summary': odds,
                    },
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Ask Noellyne AI Live Analysis'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A match counts as on air when the feed flags it live (and is not stale),
  /// **or** it carries a playable line / live EPG TV channel inside the
  /// broadcast window.
  bool _isOnAir(Map<String, dynamic> m) {
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    final now = DateTime.now();
    if (m['noellyne_fixture'] == true &&
        kickoff != null &&
        now.difference(kickoff) > const Duration(hours: 3, minutes: 30)) {
      return false;
    }
    if (m['is_live'] == true) return true;
    final hasLiveTv = _epgChannelsFor(m).any((c) => c['is_live_now'] == true);
    if (_lineCountFor(m) <= 0 && !hasLiveTv) return false;
    if (kickoff == null) return hasLiveTv;
    return now.isAfter(kickoff.subtract(const Duration(minutes: 45))) &&
        now.isBefore(kickoff.add(const Duration(hours: 3, minutes: 30)));
  }

  bool _hasPlayableTvChannel(Map<String, dynamic> m) {
    final channels = _epgChannelsFor(m);
    if (channels.isEmpty) return false;
    if (_isOnAir(m) || channels.any((c) => c['is_live_now'] == true)) {
      return true;
    }
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    if (kickoff == null) return false;
    final now = DateTime.now();
    return now.isAfter(kickoff.subtract(const Duration(minutes: 45))) &&
        now.isBefore(kickoff.add(const Duration(hours: 3, minutes: 30)));
  }

  String? _scoreTextFor(Map<String, dynamic> m) {
    final hs = m['home_score'];
    final as = m['away_score'];
    if (hs == null || as == null) return null;
    return '$hs - $as';
  }

  String? _clockTextFor(Map<String, dynamic> m) {
    final raw = (m['clock'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    if (!_isOnAir(m) && _scoreTextFor(m) == null) return null;
    return raw;
  }

  String? _tvChannelBadgeFor(Map<String, dynamic> m) {
    final channels = _epgChannelsFor(m);
    if (channels.isEmpty) return null;
    final uniqueNames = <String>[];
    for (final c in channels) {
      final name = (c['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (!uniqueNames.any((x) => x.toLowerCase() == name.toLowerCase())) {
        uniqueNames.add(name);
      }
    }
    if (uniqueNames.isEmpty) return null;
    final first = uniqueNames.first;
    final extra = uniqueNames.length - 1;
    final liveNow = channels.any((c) => c['is_live_now'] == true);
    final prefix = liveNow ? 'LIVE TV: ' : 'TV: ';
    return extra > 0 ? '$prefix$first +$extra' : '$prefix$first';
  }

  String _shortChannelCta(String name) {
    final cleaned = name.trim();
    if (cleaned.length <= 18) return cleaned.toUpperCase();
    return '${cleaned.substring(0, 17).trim()}…'.toUpperCase();
  }

  bool _isReplay(Map<String, dynamic> m) {
    if (m['is_live'] == true || _isOnAir(m)) return false;
    if (_lineCountFor(m) <= 0) return false;
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    if (kickoff == null) return false;
    final age = DateTime.now().difference(kickoff);
    return age > const Duration(hours: 3, minutes: 30) &&
        age < const Duration(hours: 30);
  }

  /// Matches visible under the current lobby filter pill.
  List<Map<String, dynamic>> _visibleMatches(List<Map<String, dynamic>> all) {
    var rows = all;
    final league = _leagueFilter;
    if (league != null && league.isNotEmpty) {
      rows = rows
          .where((m) => (m['league'] ?? '').toString() == league)
          .toList(growable: true);
    }
    switch (_lobbyFilter) {
      case LobbyFilter.liveNow:
        rows = rows.where(_isOnAir).toList(growable: true);
      case LobbyFilter.upcoming:
        rows = rows
            .where((m) => !_isOnAir(m) && !_isReplay(m))
            .toList(growable: true);
      case LobbyFilter.all:
        break;
    }
    return rows;
  }

  /// The hero slot: prefer a live match that can actually play now (direct line
  /// or live TV channel), then any live match, then next upcoming match with a
  /// known TV channel/line, otherwise the earliest upcoming fixture.
  Map<String, dynamic>? _featuredMatch(List<Map<String, dynamic>> all) {
    if (all.isEmpty) return null;
    for (final m in all) {
      if (_isOnAir(m) && (_lineCountFor(m) > 0 || _hasPlayableTvChannel(m))) {
        return m;
      }
    }
    for (final m in all) {
      if (_isOnAir(m)) return m;
    }
    for (final m in all) {
      if (_lineCountFor(m) > 0 || _epgChannelsFor(m).isNotEmpty) return m;
    }
    return all.first;
  }

  int _lineCountFor(Map<String, dynamic> m) {
    final links = playableLinks(m['stream_links']);
    final nativeLinkCount = links.where((x) {
      if (x['use_webview'] == true) return false;
      return (x['stream_url']?.toString() ?? '').trim().isNotEmpty;
    }).length;
    final fallbackCount = (m['stream_count'] as num?)?.toInt() ?? 0;
    return nativeLinkCount > fallbackCount ? nativeLinkCount : fallbackCount;
  }

  List<String> _leagueNames(List<Map<String, dynamic>> all) {
    final seen = <String>{};
    for (final m in all) {
      final league = englishKnownFootballName(
        (m['league'] ?? '').toString(),
        kind: 'league',
      );
      if (league.trim().isNotEmpty) seen.add(league);
    }
    final list = seen.toList()..sort();
    return list;
  }

  Widget _buildLobbyHeader(
    BuildContext context,
    List<Map<String, dynamic>> all,
    Map<String, dynamic> featured,
    int visibleCount,
  ) {
    final featuredLinks = _lineCountFor(featured);
    final epgChannels = _epgChannelsFor(featured);
    final hasTvNow = _hasPlayableTvChannel(featured);
    final isLive = _isOnAir(featured);
    final canWatch = featuredLinks > 0 || hasTvNow || isLive;
    final kickoff = DateTime.tryParse(
      featured['kickoff_at']?.toString() ?? '',
    )?.toLocal();
    final tvBadge = _tvChannelBadgeFor(featured);

    String heroCta;
    if (featuredLinks > 0) {
      heroCta = featuredLinks > 1
          ? '▶  WATCH LIVE · $featuredLinks LINES'
          : '▶  WATCH LIVE';
    } else if (hasTvNow) {
      final firstName = (epgChannels.first['name'] ?? 'TV').toString();
      heroCta = epgChannels.length > 1
          ? '▶  WATCH ON TV · ${epgChannels.length} CHANNELS'
          : '▶  WATCH ON ${_shortChannelCta(firstName)}';
    } else if (isLive) {
      heroCta = '▶  LIVE · FIND ON CHANNELS';
    } else {
      heroCta = epgChannels.isNotEmpty
          ? 'TV: ${_shortChannelCta((epgChannels.first['name'] ?? '').toString())}'
          : 'OPENS NEAR KICKOFF';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroMatchCard(
          league: englishKnownFootballName(
            (featured['league'] ?? 'Football').toString(),
            kind: 'league',
          ),
          homeName: englishKnownFootballName(
            (featured['home_team'] ?? 'Home').toString(),
          ),
          awayName: englishKnownFootballName(
            (featured['away_team'] ?? 'Away').toString(),
          ),
          homeLogo: featured['home_logo_url']?.toString(),
          awayLogo: featured['away_logo_url']?.toString(),
          kickoff: kickoff,
          isLive: isLive,
          canWatch: canWatch,
          lineCount: featuredLinks > 0 ? featuredLinks : epgChannels.length,
          metaLabel: tvBadge,
          scoreLabel: _scoreTextFor(featured),
          clockLabel: _clockTextFor(featured),
          actionLabel: heroCta,
          onWatch: () => openPlayer(featured),
        ),
        const SizedBox(height: 14),
        LobbyFilterRail(
          selected: _lobbyFilter,
          onSelected: (value) => setState(() => _lobbyFilter = value),
          extraLeagues: _leagueNames(all),
          selectedLeague: _leagueFilter,
          onLeagueSelected: (league) =>
              setState(() => _leagueFilter = league),
        ),
        const SizedBox(height: 6),
        SectionHeader(
          title: switch (_lobbyFilter) {
            LobbyFilter.liveNow => 'Live now',
            LobbyFilter.upcoming => 'Upcoming fixtures',
            LobbyFilter.all => 'Fixtures by day',
          },
          actionLabel: _lobbyCountLabel(all, visibleCount),
        ),
      ],
    );
  }

  String _lobbyCountLabel(List<Map<String, dynamic>> all, int visible) {
    final live = all.where(_isOnAir).length;
    if (_lobbyFilter == LobbyFilter.liveNow) {
      return live == 1 ? '1 streaming' : '$live streaming';
    }
    final total = visible == 1 ? '1 match' : '$visible matches';
    return live > 0 ? '$total · $live live' : total;
  }

  /// One row per fixture, prefixed by a day header in the `Matches` view.
  List<Widget> _groupedRows(List<Map<String, dynamic>> visible) {
    final rows = <Widget>[];
    final showGroups = _lobbyFilter == LobbyFilter.all ||
        _lobbyFilter == LobbyFilter.upcoming;
    String? lastBucket;
    for (final m in visible) {
      if (showGroups) {
        final bucket = _dayBucket(m);
        if (bucket != lastBucket) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 2));
          rows.add(
            FixtureDayHeader(
              label: _dayLabel(bucket, m),
              live: bucket == 'live',
            ),
          );
          lastBucket = bucket;
        }
      }
      rows.add(_matchCard(m));
      rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  String _dayBucket(Map<String, dynamic> m) {
    if (_isOnAir(m)) return 'live';
    if (_isReplay(m)) return 'replay';
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    if (kickoff == null) return 'later';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(kickoff.year, kickoff.month, kickoff.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'tomorrow';
    return 'd$diff';
  }

  String _dayLabel(String bucket, Map<String, dynamic> m) {
    switch (bucket) {
      case 'live':
        return 'LIVE NOW';
      case 'replay':
        return 'REPLAY & HIGHLIGHTS';
      case 'today':
        return 'TODAY';
      case 'tomorrow':
        return 'TOMORROW';
      case 'later':
        return 'LATER';
    }
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    if (kickoff == null) return 'LATER';
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${days[kickoff.weekday - 1]} ${kickoff.day} ${months[kickoff.month - 1]}';
  }

  Widget _matchCard(Map<String, dynamic> m) {
    final links = playableLinks(m['stream_links']);
    final nativeLinkCount = links.where((x) {
      if (x['use_webview'] == true) return false;
      return (x['stream_url']?.toString() ?? '').trim().isNotEmpty;
    }).length;
    final fallbackCount = (m['stream_count'] as num?)?.toInt() ?? 0;
    final displayCount =
        nativeLinkCount > fallbackCount ? nativeLinkCount : fallbackCount;
    final epgChannels = _epgChannelsFor(m);
    final hasTvNow = _hasPlayableTvChannel(m);
    final isLive = _isOnAir(m);
    final kickoff =
        DateTime.tryParse(m['kickoff_at']?.toString() ?? '')?.toLocal();
    final canWatch = displayCount > 0 || hasTvNow || isLive;

    final tvBadge = _tvChannelBadgeFor(m);
    final odds = (m['odds_summary'] ?? '').toString().trim();
    final metaParts = <String>[
      if (tvBadge != null) tvBadge,
      if (tvBadge == null && odds.isNotEmpty) odds,
    ];

    String actionLabel;
    if (displayCount > 0) {
      actionLabel = displayCount > 1
          ? 'WATCH LIVE  •  $displayCount LINES'
          : 'WATCH LIVE';
    } else if (hasTvNow) {
      final firstName = (epgChannels.first['name'] ?? 'TV').toString();
      actionLabel = epgChannels.length > 1
          ? 'WATCH ON TV  •  ${epgChannels.length} CHANNELS'
          : 'WATCH ON ${_shortChannelCta(firstName)}';
    } else if (isLive) {
      actionLabel = 'LIVE  •  FIND ON CHANNELS';
    } else if (epgChannels.isNotEmpty) {
      actionLabel =
          'OPENS ON ${_shortChannelCta((epgChannels.first['name'] ?? 'TV').toString())}';
    } else {
      actionLabel = 'OPENS NEAR KICKOFF';
    }

    return PremiumMatchCard(
      league: englishKnownFootballName(
        (m['league'] ?? 'Football').toString(),
        kind: 'league',
      ),
      homeName: englishKnownFootballName(
        (m['home_team'] ?? 'Home').toString(),
      ),
      awayName: englishKnownFootballName(
        (m['away_team'] ?? 'Away').toString(),
      ),
      homeLogo: m['home_logo_url']?.toString(),
      awayLogo: m['away_logo_url']?.toString(),
      kickoff: kickoff,
      isLive: isLive,
      canWatch: canWatch,
      scoreLabel: _scoreTextFor(m),
      clockLabel: _clockTextFor(m),
      metaLabel: metaParts.isEmpty ? null : metaParts.join('  ·  '),
      actionLabel: actionLabel,
      onWatch: () => openPlayer(m),
      reminded: MatchReminders.instance.isReminded(m['id'].toString()),
      onRemind: kickoff == null
          ? null
          : () => _toggleReminder(m, kickoff!),
    );
  }

  Future<void> _toggleReminder(
    Map<String, dynamic> m,
    DateTime kickoff,
  ) async {
    final id = m['id'].toString();
    final lead = await MatchReminders.leadMinutes();
    final home = englishKnownFootballName(
      (m['home_team'] ?? 'Home').toString(),
    );
    final away = englishKnownFootballName(
      (m['away_team'] ?? 'Away').toString(),
    );
    await MatchReminders.instance.toggle(
      MatchReminder(
        matchId: id,
        title: '$home vs $away',
        league: englishKnownFootballName(
          (m['league'] ?? '').toString(),
          kind: 'league',
        ),
        kickoff: kickoff,
        leadMinutes: lead,
      ),
    );
    if (!mounted) return;
    final on = MatchReminders.instance.isReminded(id);
    setState(() {});
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'Reminder set — we will nudge you $lead min before kickoff'
                : 'Reminder removed',
          ),
          action: on
              ? SnackBarAction(
                  label: 'View',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RemindersPage(),
                    ),
                  ),
                )
              : null,
        ),
      );
  }

  Widget _buildEmptyLobby(
    BuildContext context,
    List<Map<String, dynamic>> all,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final liveMode = _lobbyFilter == LobbyFilter.liveNow;
    final nextOnAir = all.where(_isOnAir).length;
    final nextUp = all
        .where((m) => !_isOnAir(m))
        .map((m) => DateTime.tryParse(m['kickoff_at']?.toString() ?? '')
            ?.toLocal())
        .whereType<DateTime>()
        .where((d) => d.isAfter(DateTime.now()))
        .toList()
      ..sort();
    final nextLabel = nextUp.isEmpty
        ? ''
        : ' Next kickoff ${_hhmm(nextUp.first)}.';
    if (!liveMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 46, 24, 24),
        child: Column(
          children: [
            Icon(Icons.sports_soccer_outlined,
                size: 36,
                color: NoellyneColors.glowDeep.withValues(alpha: .85)),
            const SizedBox(height: 10),
            Text(
              _leagueFilter == null
                  ? 'Nothing in this filter'
                  : 'No $_leagueFilter matches',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try “All” — new matches appear automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Icon(Icons.sensors_off_rounded,
              size: 36, color: NoellyneColors.glowDeep.withValues(alpha: .85)),
          const SizedBox(height: 10),
          Text(
            'No line is on air right now',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nextOnAir == 0
                ? 'Channels are quiet between matches.$nextLabel '
                    'Tap “All” to browse the full schedule.'
                : '$nextOnAir match${nextOnAir == 1 ? '' : 'es'} flagged live '
                    'but no playable line is ready yet.$nextLabel',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => setState(() {
              _lobbyFilter = LobbyFilter.all;
              _leagueFilter = null;
            }),
            child: const Text('Browse all fixtures'),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Opens the AI chat (n8n brain with an offline fallback); the chat has a
  /// shortcut to the Daily Picks feed.
  Future<void> _openAiChat() => openAiChat(context);

  /// Opens the n8n Daily Picks feed; a pick's CTA jumps straight into the
  /// matching stream when its `stream_id` is still in the current feed.
  Future<void> _openDailyPicks() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DailyPicksPage(
          onWatchMatch: (streamId) {
            Navigator.of(context).pop();
            _focusMatch(streamId);
          },
        ),
      ),
    );
  }

  void _focusMatch(String streamId) {
    final rows = _feed.data;
    if (rows == null) return;
    for (final m in rows) {
      if (m['id']?.toString() == streamId) {
        unawaited(openPlayer(m));
        return;
      }
    }
  }

  void _openStreamSource(int index) {
    final source = viewerSourceAt(index);
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => SourceBrowserPage(source: source),
          ),
        )
        .then((_) {
      if (mounted && _liveNeedsRefresh) unawaited(refresh(silent: true));
    });
  }

  Future<void> _openMoreSheet() async {
    const extraSources = <(int, String, IconData)>[
      (1, 'Live 2', Icons.live_tv_rounded),
      (2, 'Soco', Icons.sports_soccer_rounded),
      (3, 'YYZB', Icons.sensors_rounded),
      (4, 'ColaTV', Icons.tv_rounded),
      (5, 'Fawa', Icons.language_rounded),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return GlassBlur(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          sigma: 24,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'More sources',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                  ),
                ),
                for (final (index, label, icon) in extraSources)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openStreamSource(index);
                    },
                  ),
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text(
                    'Daily Picks',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('AI slips from n8n'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openDailyPicks();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text(
                    'Settings & updates',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openAppMenu();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    NativePlayer.onOpenMatch = null;
    _reminderTick?.cancel();
    _feed.dispose();
    _debounce?.cancel();
    _feedRefresh?.cancel();
    final c = _channel;
    final supabase = _supabaseClientOrNull();
    if (c != null && supabase != null) supabase.removeChannel(c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 14,
        title: const LobbyBrand(),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => refresh(silent: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 3),
        ],
      ),
      body: AnimatedBuilder(
        animation: _feed,
        builder: (context, _) {
          if (_feed.loading && !_feed.hasData) {
            return const SkeletonLobby();
          }
          if (_feed.error != null && !_feed.hasData) {
            return _StateMessage(
              icon: Icons.vpn_key_off_outlined,
              title: 'Live feed unavailable',
              subtitle: 'Network temporarily unavailable. Tap refresh to retry backup routes.',
              onPressed: refresh,
            );
          }

          final matches = [...?_feed.data];
          final linkedIndex = matches.indexWhere((m) => m['id'] == widget.initialMatchId);
          if (linkedIndex > 0) matches.insert(0, matches.removeAt(linkedIndex));
          if (matches.isEmpty) {
            return _StateMessage(
              icon: Icons.sports_soccer_outlined,
              title: 'No matches now',
              subtitle: 'New matches will appear here automatically.',
              onPressed: refresh,
            );
          }

          final visible = _visibleMatches(matches);
          final featured = _featuredMatch(matches);
          final emptyLobby = visible.isEmpty;
          if (featured == null) {
            return _StateMessage(
              icon: Icons.sports_soccer_outlined,
              title: 'No matches now',
              subtitle: 'New matches will appear here automatically.',
              onPressed: refresh,
            );
          }

          return NoellyneBackground(
            child: RefreshIndicator(
              onRefresh: refresh,
              color: NoellyneColors.glowDeep,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 108),
                // Fixtures are grouped by day so `Matches` reads as a
                // schedule, while `Live` stays a single live strip.
                children: [
                  _buildLobbyHeader(
                    context,
                    matches,
                    featured,
                    visible.length,
                  ),
                  if (emptyLobby) _buildEmptyLobby(context, matches) else ...[
                    for (final row in _groupedRows(visible)) row,
                  ],
                ],
              ),
            ),
          );
        },
      ),
      extendBody: true,
      bottomNavigationBar: const NoellyneDockBar(current: NoellyneTab.home),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 29, color: colors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onPressed(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REFRESH'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
