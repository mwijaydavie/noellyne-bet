import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/daily_pick.dart';
import '../noellyne_config.dart';

/// Combined snapshot of live published picks + settled performance history.
class DailyPicksBoard {
  const DailyPicksBoard({
    required this.published,
    required this.settled,
    this.errorMessage,
  });

  final List<DailyPick> published;
  final List<DailyPick> settled;
  final String? errorMessage;
}

/// Loads published picks and settled results written by the n8n Hermes pipeline
/// into the dedicated Noellyne Bet Supabase project (`picksSupabaseUrl`).
///
/// Uses only the public read-only publishable key — zero write secrets exist in
/// the app. Degrades gracefully and never invents fake odds.
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

  /// True when what the UI is showing came from [_demo], not the pipeline.
  static bool get showsSampleData => _enableDemo;

  Future<DailyPicksBoard> fetchBoard({int limit = 40}) async {
    try {
      final results = await Future.wait<List<DailyPick>>([
        _query(status: 'published', order: 'kickoff_time.asc', limit: limit),
        _query(
          status: 'settled',
          order: 'settled_at.desc.nullslast,kickoff_time.desc',
          limit: limit,
        ),
      ]);
      return DailyPicksBoard(
        published: results[0].isNotEmpty || !_enableDemo ? results[0] : _demo,
        settled: results[1],
      );
    } catch (error) {
      debugPrint('daily_picks board fetch failed: $error');
      return DailyPicksBoard(
        published: _enableDemo ? _demo : const [],
        settled: const [],
        errorMessage: 'Imeshindwa kuunganisha na server ya picks. Jaribu tena.',
      );
    }
  }

  Future<List<DailyPick>> fetch({int limit = 40}) async {
    try {
      final picks = await _query(
        status: 'published',
        order: 'kickoff_time.asc',
        limit: limit,
      );
      if (picks.isNotEmpty) return picks;
    } catch (error) {
      debugPrint('daily_picks unavailable: $error');
    }
    return _enableDemo ? _demo : const [];
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
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => DailyPick.fromJson(row.cast<String, dynamic>()))
        .where((p) => p.pick.isNotEmpty)
        .toList(growable: false);
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
