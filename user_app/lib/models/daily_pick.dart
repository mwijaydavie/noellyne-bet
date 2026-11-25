/// A structured pick produced by the Noellyne n8n betting pipeline.
///
/// n8n POSTs JSON to Supabase `daily_picks`; the viewer renders these as
/// interactive cards (never walls of Telegram markdown).
class DailyPick {
  const DailyPick({
    required this.id,
    required this.match,
    required this.league,
    required this.pick,
    required this.odds,
    required this.confidence,
    this.reasoning = '',
    this.streamId,
    this.kickoffTime,
    this.tags = const [],
    this.slipCode,
    this.sport = 'football',
    this.tier = '',
    this.units = 0,
    this.edgePct = 0,
    this.injuryNote = '',
    this.status = 'published',
    this.result,
    this.score = '',
    this.profitUnits = 0,
    this.settledAt,
  });

  final String id;
  final String match;
  final String league;

  /// Human-readable market + pick, e.g. "Arsenal Win & Over 1.5".
  final String pick;
  final double odds;

  /// 0–100 model confidence.
  final int confidence;
  final String reasoning;

  /// Deep-links the viewer straight into the player (`?match=<streamId>`).
  final String? streamId;
  final DateTime? kickoffTime;

  /// Free-form tags: `sure2+`, `strong`, `btts`, `high-odds`, `over2.5`.
  final List<String> tags;

  /// Shareable bet-slip code shown in Match Theatre.
  final String? slipCode;

  /// `football` | `basketball` (Hermes dual-sport pipeline).
  final String sport;

  /// Quant tier from the model, e.g. "STRONG" or "MODERATE".
  final String tier;

  /// Recommended stake in units (1u = 1% of bankroll).
  final double units;

  /// Model edge over the implied market probability, in %.
  final double edgePct;

  /// NBA Injury Guard note (who is OUT).
  final String injuryNote;

  /// `published` | `settled` | `void`.
  final String status;

  /// `won` | `lost` | `void` when settled.
  final String? result;

  /// Final score string populated by Hermes Settlement, e.g. "101 - 111".
  final String score;

  /// Settled net profit/loss in units (e.g. +1.68 or -1.50).
  final double profitUnits;
  final DateTime? settledAt;

  bool get isHighConfidence => confidence >= 80;
  bool get isBasketball => sport == 'basketball';

  /// Canonical category predicates shared identically across Today AND Results
  /// so users can audit Sure 2+, Strong, and High Odds with 100% consistency.
  bool get isSure2 => confidence >= 80 || tags.contains('sure2+');
  bool get isStrong =>
      tier.toUpperCase().contains('STRONG') || tags.contains('strong');
  bool get isHighOdds => odds >= 1.85 || tags.contains('high-odds');
  bool get isModerate =>
      !isStrong && tier.toUpperCase().contains('MODERATE');

  bool get isSettled => status == 'settled' && result != null;
  bool get isWon => result == 'won';
  bool get isLost => result == 'lost';

  /// Structured match context passed to the n8n AI Chat webhook when the user
  /// taps "Ask AI" on this pick.
  Map<String, dynamic> toAiContext() => {
        'match': match,
        'league': league,
        'sport': sport,
        'pick': pick,
        'odds': odds,
        'confidence': confidence,
        'edge_pct': edgePct,
        'tier': tier,
        'units': units,
        if (injuryNote.isNotEmpty) 'injury_note': injuryNote,
        if (reasoning.isNotEmpty) 'reasoning': reasoning,
        if (score.isNotEmpty) 'score': score,
        if (result != null) 'result': result,
      };

  /// Full lossless JSON representation for offline disk caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'match': match,
        'league': league,
        'pick': pick,
        'odds': odds,
        'confidence': confidence,
        'reasoning': reasoning,
        'stream_id': streamId,
        'kickoff_time': kickoffTime?.toUtc().toIso8601String(),
        'tags': tags,
        'slip_code': slipCode,
        'sport': sport,
        'tier': tier,
        'units': units,
        'edge_pct': edgePct,
        'injury_note': injuryNote,
        'status': status,
        'result': result,
        'score': score,
        'profit_units': profitUnits,
        'settled_at': settledAt?.toUtc().toIso8601String(),
      };

  factory DailyPick.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final rawKickoff = json['kickoff_time'] ?? json['kickoffTime'];
    final rawSettled = json['settled_at'] ?? json['settledAt'];
    return DailyPick(
      id: '${json['id'] ?? ''}',
      match: '${json['match'] ?? json['fixture'] ?? 'Match'}'.trim(),
      league: '${json['league'] ?? 'Football'}'.trim(),
      pick: '${json['pick'] ?? json['market'] ?? ''}'.trim(),
      odds: _asDouble(json['odds']),
      confidence: _asInt(json['confidence']),
      reasoning: '${json['reasoning'] ?? json['analysis'] ?? ''}'.trim(),
      streamId: _asNullableString(json['stream_id'] ?? json['streamId']),
      kickoffTime: rawKickoff == null
          ? null
          : DateTime.tryParse('$rawKickoff')?.toLocal(),
      tags: rawTags is List
          ? rawTags.map((t) => '$t'.toLowerCase().trim()).toList()
          : const [],
      slipCode: _asNullableString(json['slip_code'] ?? json['slipCode']),
      sport: _asNullableString(json['sport'])?.toLowerCase() ?? 'football',
      tier: '${json['tier'] ?? ''}'.trim(),
      units: _asDouble(json['units']),
      edgePct: _asDouble(json['edge_pct'] ?? json['edgePct']),
      injuryNote: '${json['injury_note'] ?? json['injuryNote'] ?? ''}'.trim(),
      status: _asNullableString(json['status'])?.toLowerCase() ?? 'published',
      result: _asNullableString(json['result'])?.toLowerCase(),
      score: '${json['score'] ?? ''}'.trim(),
      profitUnits: _asDouble(json['profit_units'] ?? json['profitUnits']),
      settledAt: rawSettled == null
          ? null
          : DateTime.tryParse('$rawSettled')?.toLocal(),
    );
  }

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.trim()) ?? 0;
  }

  static int _asInt(Object? v) {
    if (v is num) return v.round();
    return int.tryParse('$v'.trim()) ?? 0;
  }

  static String? _asNullableString(Object? v) {
    final s = v == null ? '' : '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

/// Shared category filters shown identically above BOTH Today Picks and Results
/// so users can track Sure 2+, Strong, and High Odds end-to-end.
enum PickFilter {
  all('All'),
  sure('Sure 2+'),
  strong('Strong'),
  highOdds('High Odds'),
  football('Football'),
  basketball('NBA');

  const PickFilter(this.label);
  final String label;

  bool matches(DailyPick p) => switch (this) {
        PickFilter.all => true,
        PickFilter.sure => p.isSure2,
        PickFilter.strong => p.isStrong,
        PickFilter.highOdds => p.isHighOdds,
        PickFilter.football => !p.isBasketball,
        PickFilter.basketball => p.isBasketball,
      };
}

/// Outcome / timeframe sub-filter composable with [PickFilter] on Results.
enum ResultOutcomeFilter {
  all('All'),
  won('Won'),
  lost('Lost'),
  recent48h('48h');

  const ResultOutcomeFilter(this.label);
  final String label;

  bool matches(DailyPick p, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final ref = p.settledAt ?? p.kickoffTime;
    return switch (this) {
      ResultOutcomeFilter.all => true,
      ResultOutcomeFilter.won => p.isWon,
      ResultOutcomeFilter.lost => p.isLost,
      ResultOutcomeFilter.recent48h =>
        ref != null && current.difference(ref).inHours <= 48,
    };
  }
}

/// Sort modes for Today's active picks.
enum PickSort {
  confidence('Confidence'),
  kickoff('Kickoff Soon'),
  highestOdds('Highest Odds'),
  bestEdge('Best Edge');

  const PickSort(this.label);
  final String label;

  List<DailyPick> apply(List<DailyPick> input) {
    final out = [...input];
    out.sort((a, b) => switch (this) {
          PickSort.confidence => _chain([
              b.confidence.compareTo(a.confidence),
              b.edgePct.compareTo(a.edgePct),
              _compareDatesAsc(a.kickoffTime, b.kickoffTime),
            ]),
          PickSort.kickoff => _chain([
              _compareDatesAsc(a.kickoffTime, b.kickoffTime),
              b.confidence.compareTo(a.confidence),
            ]),
          PickSort.highestOdds => _chain([
              b.odds.compareTo(a.odds),
              b.confidence.compareTo(a.confidence),
            ]),
          PickSort.bestEdge => _chain([
              b.edgePct.compareTo(a.edgePct),
              b.confidence.compareTo(a.confidence),
            ]),
        });
    return out;
  }
}

/// Sort modes for verified Results ledger.
enum ResultSort {
  newest('By Date'),
  wonFirst('Won First'),
  highestConfidence('Highest Conf'),
  highestOdds('Highest Odds'),
  topProfit('Top Profit');

  const ResultSort(this.label);
  final String label;

  List<DailyPick> apply(List<DailyPick> input) {
    final out = [...input];
    out.sort((a, b) => switch (this) {
          ResultSort.newest => _compareDatesDesc(
              a.settledAt ?? a.kickoffTime,
              b.settledAt ?? b.kickoffTime,
            ),
          ResultSort.wonFirst => _chain([
              (b.isWon ? 1 : 0).compareTo(a.isWon ? 1 : 0),
              b.profitUnits.compareTo(a.profitUnits),
              _compareDatesDesc(
                a.settledAt ?? a.kickoffTime,
                b.settledAt ?? b.kickoffTime,
              ),
            ]),
          ResultSort.highestConfidence => _chain([
              b.confidence.compareTo(a.confidence),
              (b.isWon ? 1 : 0).compareTo(a.isWon ? 1 : 0),
              b.odds.compareTo(a.odds),
            ]),
          ResultSort.highestOdds => _chain([
              b.odds.compareTo(a.odds),
              (b.isWon ? 1 : 0).compareTo(a.isWon ? 1 : 0),
              b.profitUnits.compareTo(a.profitUnits),
            ]),
          ResultSort.topProfit => _chain([
              b.profitUnits.compareTo(a.profitUnits),
              b.odds.compareTo(a.odds),
            ]),
        });
    return out;
  }
}

int _chain(List<int> comparisons) {
  for (final c in comparisons) {
    if (c != 0) return c;
  }
  return 0;
}

int _compareDatesAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

int _compareDatesDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
