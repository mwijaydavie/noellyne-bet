import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/channel_match_search.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  Map<String, dynamic> programme(String text, {int minutes = 0}) => {
    'title': text, 'start': now.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    'end': now.add(Duration(minutes: minutes + 120)).millisecondsSinceEpoch,
  };
  test('Napoli team search finds a programme even when the channel has a different name', () {
    final rows = [programme('Napoli vs Inter Milan')];
    expect(channelMatchesProgrammeQuery({'name':'TNT Sports 1'}, rows, 'Napoli'), isTrue);
    expect(channelMatchesProgrammeQuery({'name':'TNT Sports 1'}, rows, 'Napoli Arsenal'), isFalse);
    expect(currentFootballProgramme(programme('Replay: Napoli vs Inter Milan'), now: now), isFalse);
    expect(currentFootballProgramme(programme('Napoli vs Inter Milan', minutes: -200), now: now), isFalse);
  });
  test('selected match needs both teams and a nearby kickoff, not a highlight or another fixture', () {
    final match = {'home_team':'SSC Napoli','away_team':'Inter Milan','kickoff_at':now.toIso8601String()};
    expect(programmeCoversMatch(programme('Napoli vs Inter Milan'), match, now: now), isTrue);
    expect(programmeCoversMatch(programme('Serie A: Napoli - Inter Milan'), match, now: now), isTrue);
    expect(programmeCoversMatch(programme('Napoli vs Inter Milan', minutes: 180), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Napoli vs Roma'), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Preview: Napoli vs Inter Milan'), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Inter Milan vs Atalanta'),
      {'home_team':'Inter Milan','away_team':'AC Milan','kickoff_at':now.toIso8601String()},now: now), isFalse);
  });
  test('matches Internazionale -> Inter, Dortmund, diacritics, and rejects Mini Match / delayed (D)', () {
    final interMatch = {'home_team': 'Atalanta', 'away_team': 'Internazionale', 'kickoff_at': now.toIso8601String()};
    expect(programmeCoversMatch(programme('Serie A | Atalanta vs Inter'), interMatch, now: now), isTrue);
    expect(programmeCoversMatch(programme('Mini Match - Serie A | Atalanta vs Inter'), interMatch, now: now), isFalse);
    final uclMatch = {'home_team': 'Arsenal', 'away_team': 'Borussia Dortmund', 'kickoff_at': now.toIso8601String()};
    expect(programmeCoversMatch(programme('(L) UCL : Arsenal Vs Dortmund - MD5'), uclMatch, now: now), isTrue);
    expect(programmeCoversMatch(programme('(D) UCL : Arsenal Vs Dortmund - MD5'), uclMatch, now: now), isFalse);
    final laLiga = {'home_team': 'Getafe', 'away_team': 'Atlético Madrid', 'kickoff_at': now.toIso8601String()};
    expect(programmeCoversMatch(programme('LaLiga | Getafe vs Atletico Madrid'), laLiga, now: now), isTrue);
    expect(programmeIsLiveNow(programme('LaLiga | Levante vs Elche', minutes: -10), now: now), isTrue);
    expect(programmeIsLiveNow(programme('LaLiga | Levante vs Elche', minutes: 90), now: now), isFalse);
  });
}
