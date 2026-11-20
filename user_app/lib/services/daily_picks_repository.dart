import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/daily_pick.dart';

/// Loads published picks written by the n8n pipeline.
///
/// Degrades gracefully: if Supabase is unavailable or the table is empty,
/// [_demo] picks are returned so the feed never shows a blank screen.
/// Set `DAILY_PICKS_DEMO=0` via dart-define to disable demo content.
class DailyPicksRepository {
  const DailyPicksRepository();

  static const _enableDemo = bool.fromEnvironment(
    'DAILY_PICKS_DEMO',
    defaultValue: true,
  );

  Future<List<DailyPick>> fetch({int limit = 40}) async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('daily_picks')
          .select(
            'id,match,league,pick,odds,confidence,reasoning,stream_id,'
            'kickoff_time,tags,slip_code',
          )
          .eq('status', 'published')
          .order('kickoff_time', ascending: true)
          .limit(limit)
          .timeout(const Duration(seconds: 8));

      final picks = (rows as List)
          .map((row) => DailyPick.fromJson((row as Map).cast<String, dynamic>()))
          .where((p) => p.pick.isNotEmpty)
          .toList(growable: false);

      if (picks.isNotEmpty) return picks;
    } catch (error) {
      debugPrint('daily_picks unavailable, using demo feed: $error');
    }
    return _enableDemo ? _demo : const [];
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
      tags: const ['sure2+', 'over2.5'],
      slipCode: 'NLY-8K2F',
    ),
    DailyPick(
      id: 'demo-2',
      match: 'Real Madrid vs Barcelona',
      league: 'La Liga',
      pick: 'Both Teams To Score',
      odds: 1.55,
      confidence: 88,
      reasoning:
          'Both sides scored in the last 6 Clásicos. High xG on both sides '
          'and open midfields make BTTS the safest angle.',
      streamId: 'demo-rma-bar',
      tags: const ['btts', 'sure2+'],
      slipCode: 'NLY-4M7Q',
    ),
    DailyPick(
      id: 'demo-3',
      match: 'Simba vs Yanga',
      league: 'NBC Premier League',
      pick: 'Under 2.5 Goals',
      odds: 1.72,
      confidence: 79,
      reasoning:
          'Derby matches average 1.8 goals. Both defences are top-3 in the '
          'league and the last 4 meetings produced under 2.5.',
      streamId: 'demo-sim-yan',
      tags: const ['under2.5'],
      slipCode: 'NLY-1T9C',
    ),
    DailyPick(
      id: 'demo-4',
      match: 'Man City vs Liverpool',
      league: 'Premier League',
      pick: 'Over 3.5 Goals & BTTS',
      odds: 2.45,
      confidence: 71,
      reasoning:
          'Priced for value: both attacks rank top-2 for shots on target, '
          'while both keepers face 4+ big chances per game.',
      streamId: 'demo-mci-liv',
      tags: const ['high-odds', 'btts', 'over2.5'],
      slipCode: 'NLY-6R3D',
    ),
    DailyPick(
      id: 'demo-5',
      match: 'Bayern vs Dortmund',
      league: 'Bundesliga',
      pick: 'Bayern -1 Handicap',
      odds: 2.10,
      confidence: 76,
      reasoning:
          'Bayern have won by 2+ in their last 5 home Der Klassiker fixtures.',
      streamId: 'demo-bay-bvb',
      tags: const ['high-odds'],
      slipCode: 'NLY-9W5B',
    ),
  ];
}
