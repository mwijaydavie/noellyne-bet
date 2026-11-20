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

  /// Free-form tags: `sure2+`, `btts`, `high-odds`, `over2.5`.
  final List<String> tags;

  /// Shareable bet-slip code shown in Match Theatre.
  final String? slipCode;

  bool get isHighConfidence => confidence >= 80;

  factory DailyPick.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final rawKickoff = json['kickoff_time'] ?? json['kickoffTime'];
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

/// Feed filters shown as pills above the picks.
enum PickFilter {
  all('All Picks'),
  sure('Sure 2+'),
  btts('BTTS'),
  highOdds('High Odds');

  const PickFilter(this.label);
  final String label;

  bool matches(DailyPick p) => switch (this) {
        PickFilter.all => true,
        PickFilter.sure => p.confidence >= 80 || p.tags.contains('sure2+'),
        PickFilter.btts => p.tags.contains('btts') ||
            p.pick.toLowerCase().contains('btts') ||
            p.pick.toLowerCase().contains('both teams'),
        PickFilter.highOdds => p.odds >= 2.0 || p.tags.contains('high-odds'),
      };
}
