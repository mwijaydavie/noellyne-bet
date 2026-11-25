import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/models/daily_pick.dart';

void main() {
  final now = DateTime.utc(2026, 11, 25, 12);
  final sureWin = DailyPick(
    id: '1',
    match: 'Wolves vs Derby',
    league: 'Championship',
    pick: 'Wolves Win (1)',
    odds: 1.31,
    confidence: 86,
    tier: 'STRONG',
    tags: const ['sure2+', 'strong'],
    units: 3.0,
    edgePct: 9.2,
    status: 'settled',
    result: 'won',
    profitUnits: 0.93,
    kickoffTime: now.subtract(const Duration(hours: 16)),
    settledAt: now.subtract(const Duration(hours: 14)),
  );
  final highOddsWin = DailyPick(
    id: '2',
    match: 'Real Madrid vs PSV',
    league: 'UCL',
    pick: 'OVER 4.5',
    odds: 1.95,
    confidence: 67,
    tier: 'STRONG',
    tags: const ['strong', 'over2.5'],
    units: 2.5,
    edgePct: 6.4,
    status: 'settled',
    result: 'won',
    profitUnits: 2.38,
    kickoffTime: now.subtract(const Duration(hours: 18)),
    settledAt: now.subtract(const Duration(hours: 15)),
  );
  final lostPick = DailyPick(
    id: '3',
    match: 'Wizards vs Celtics',
    league: 'NBA',
    sport: 'basketball',
    pick: 'Wizards +10.5',
    odds: 1.91,
    confidence: 58,
    tier: 'MODERATE',
    tags: const [],
    units: 1.5,
    edgePct: 4.1,
    status: 'settled',
    result: 'lost',
    profitUnits: -1.5,
    kickoffTime: now.subtract(const Duration(hours: 12)),
    settledAt: now.subtract(const Duration(hours: 6)),
  );

  test('canonical category predicates stay aligned across Today and Results', () {
    expect(sureWin.isSure2, isTrue);
    expect(sureWin.isStrong, isTrue);
    expect(sureWin.isHighOdds, isFalse);

    expect(highOddsWin.isSure2, isFalse);
    expect(highOddsWin.isStrong, isTrue);
    expect(highOddsWin.isHighOdds, isTrue);

    expect(lostPick.isSure2, isFalse);
    expect(lostPick.isStrong, isFalse);
    expect(lostPick.isHighOdds, isTrue);

    expect(PickFilter.sure.matches(sureWin), isTrue);
    expect(PickFilter.highOdds.matches(highOddsWin), isTrue);
    expect(ResultOutcomeFilter.won.matches(sureWin, now: now), isTrue);
    expect(ResultOutcomeFilter.lost.matches(lostPick, now: now), isTrue);
    expect(ResultOutcomeFilter.week7d.matches(sureWin, now: now), isTrue);
  });

  test('PickSort and ResultSort produce exact serious ordering', () {
    final list = [lostPick, highOddsWin, sureWin];
    expect(PickSort.confidence.apply(list).first.id, '1');
    expect(PickSort.highestOdds.apply(list).first.id, '2');
    expect(PickSort.bestEdge.apply(list).first.id, '1');

    expect(ResultSort.newest.apply(list).first.id, '3');
    expect(ResultSort.wonFirst.apply(list).first.id, '2');
    expect(ResultSort.highestConfidence.apply(list).first.id, '1');
    expect(ResultSort.highestOdds.apply(list).first.id, '2');
    expect(ResultSort.topProfit.apply(list).first.id, '2');
  });

  test('DailyBankerSlip picks optimal ~2.00x Sure 2+ double and never forces weak picks', () {
    final leg1 = DailyPick(
      id: 'b1',
      match: 'Celta Vigo vs AFC Bournemouth',
      league: 'UEL',
      pick: 'DC X2',
      odds: 1.33,
      confidence: 88,
      tier: 'STRONG',
      tags: const ['sure2+', 'strong'],
    );
    final leg2 = DailyPick(
      id: 'b2',
      match: 'Viktoria Plzen vs Benfica',
      league: 'UEL',
      pick: 'Benfica Win (2)',
      odds: 1.47,
      confidence: 83,
      tier: 'STRONG',
      tags: const ['sure2+', 'strong'],
    );
    final weak = DailyPick(
      id: 'w1',
      match: 'Hornets vs Bulls',
      league: 'NBA',
      sport: 'basketball',
      pick: 'Bulls +3.5',
      odds: 1.87,
      confidence: 59,
      tier: 'MODERATE',
    );

    final slip = DailyBankerSlip.build([weak, leg2, leg1], settled: [sureWin, lostPick]);
    expect(slip, isNotNull);
    expect(slip!.allSure2, isTrue);
    expect(slip.legs.map((p) => p.id).toList(), ['b1', 'b2']);
    expect(slip.combinedOdds, 1.96);
    expect(slip.jointConfidencePct, 73);
    expect(slip.sure2HistoricalWins, 1);
    expect(slip.sure2HistoricalLosses, 0);
    expect(slip.estReturnTzs(10000), 19600);

    // Never forces a combo from low-confidence picks.
    expect(DailyBankerSlip.build([weak]), isNull);
  });
}
