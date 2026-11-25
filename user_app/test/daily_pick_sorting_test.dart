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
}
