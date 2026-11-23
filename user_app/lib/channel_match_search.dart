String _foldDiacritics(String input) {
  const map = <String, String>{
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c', 'ş': 's', 'š': 's', 'ğ': 'g', 'ž': 'z', 'ł': 'l',
    'ý': 'y', 'ÿ': 'y',
  };
  final buf = StringBuffer();
  for (final unit in input.toLowerCase().runes) {
    final ch = String.fromCharCode(unit);
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

String _words(Object? value) => _foldDiacritics((value ?? '').toString())
    .replaceAllMapped(RegExp(r'([a-z])([0-9])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String programmeSearchText(Map programme) =>
    '${programme['title'] ?? ''} ${programme['subtitle'] ?? ''} ${programme['description'] ?? ''}';

bool currentFootballProgramme(Map programme, {DateTime? now}) {
  if (programme['stream_ambiguous'] == true) return false;
  final rawText = programmeSearchText(programme);
  // Reject delayed / mini-match rebroadcasts like "(D) Women's Super League" or "Mini Match".
  if (RegExp(r'\(\s*d\s*\)', caseSensitive: false).hasMatch(rawText)) return false;
  final body = _words(rawText);
  if (RegExp(
    r'\b(replay|highlights?|recap|preview|repeat|classic|magazine|review|mini|aflw?|australian rules|aussie rules|american football|nfl|nba|hockey|rugby|cricket|tennis|basketball|motorsport|esports|formula 1)\b',
  ).hasMatch(body)) {
    return false;
  }
  final versus = RegExp(r'\b(vs|v|versus)\b').hasMatch(body);
  final hosted = RegExp(r'\blive\b').hasMatch(body) &&
      RegExp(r'\b(soccer|premier league|la liga|laliga|bundesliga|serie a|ligue 1|champions league|ucl|europa league)\b').hasMatch(body) &&
      RegExp(r'\b(host|hosts|hosting|face|faces|take on|takes on)\b').hasMatch(body);
  final labelledFixture = RegExp(r'\b(soccer|football|serie a|premier league|la liga|laliga|bundesliga|ligue 1|champions league|ucl|europa league|eredivisie)\b').hasMatch(body) &&
      RegExp(r'\w\s*[-–—]\s*\w').hasMatch(rawText);
  if (!versus && !hosted && !labelledFixture) return false;
  final startMs = programme['start'];
  if (startMs is! num) return false;
  final start = DateTime.fromMillisecondsSinceEpoch(startMs.toInt(), isUtc: true);
  final endMs = programme['end'];
  final end = endMs is num
      ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt(), isUtc: true)
      : start.add(const Duration(hours: 3));
  final current = (now ?? DateTime.now()).toUtc();
  return end.isAfter(current) && !start.isAfter(current.add(const Duration(days: 8)));
}

bool programmeIsLiveNow(Map programme, {DateTime? now}) {
  final startMs = programme['start'];
  if (startMs is! num) return false;
  final start = DateTime.fromMillisecondsSinceEpoch(startMs.toInt(), isUtc: true);
  final endMs = programme['end'];
  final end = endMs is num
      ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt(), isUtc: true)
      : start.add(const Duration(hours: 3));
  final current = (now ?? DateTime.now()).toUtc();
  return !start.isAfter(current.add(const Duration(minutes: 15))) && end.isAfter(current);
}

List<String> _aliases(Object? team) {
  final name = _words(team);
  final short = name
      .replaceFirst(RegExp(r'^(?:ssc|acf|afc|fc|ac|sc|cf|cd|rc|as|ss|sl|rcd|ud|rb|sv|vfl|tsg|fsv|ogc|us|ca|se|ec|cr) '), '')
      .replaceFirst(RegExp(r' (?:fc|afc|cf|sc|cp|football club|calcio|balompie|united)$'), '');
  const known = <String, List<String>>{
    'tottenham hotspur': ['tottenham', 'spurs'],
    'ssc napoli': ['napoli', 'naples'],
    'napoli': ['naples'],
    'manchester city': ['man city'],
    'manchester united': ['man united', 'man utd'],
    'inter milan': ['inter', 'internazionale'],
    'inter': ['inter milan', 'internazionale'],
    'internazionale': ['inter', 'inter milan', 'inter milano'],
    'fc internazionale milano': ['inter', 'inter milan', 'internazionale'],
    'ac milan': ['milan'],
    'newcastle united': ['newcastle'],
    'athletic club': ['athletic bilbao', 'bilbao'],
    'athletic bilbao': ['athletic club', 'bilbao'],
    'borussia dortmund': ['dortmund', 'bvb'],
    'dortmund': ['borussia dortmund', 'bvb'],
    'atletico madrid': ['atletico', 'atleti', 'atletico de madrid'],
    'atletico de madrid': ['atletico', 'atletico madrid', 'atleti'],
    'paris saint germain': ['psg', 'paris sg', 'paris'],
    'psg': ['paris saint germain', 'paris sg'],
    'bayern munich': ['bayern', 'bayern munchen'],
    'bayern munchen': ['bayern', 'bayern munich'],
    'real madrid cf': ['real madrid'],
    'fc barcelona': ['barcelona', 'barca'],
    'barcelona': ['barca'],
    'wolverhampton wanderers': ['wolves', 'wolverhampton'],
    'brighton and hove albion': ['brighton'],
    'brighton hove albion': ['brighton'],
    'west ham united': ['west ham'],
    'west ham': ['west ham united'],
    'nottingham forest': ['nottm forest', 'nottingham', 'forest'],
    'leicester city': ['leicester'],
    'real betis balompie': ['real betis', 'betis'],
    'real betis': ['betis'],
    'rb leipzig': ['leipzig'],
    'bayer leverkusen': ['leverkusen'],
    'bayer 04 leverkusen': ['leverkusen'],
    'olympique de marseille': ['marseille'],
    'olympique marseille': ['marseille'],
    'olympique lyonnais': ['lyon'],
    'sporting cp': ['sporting', 'sporting lisbon'],
    'sl benfica': ['benfica'],
    'fc porto': ['porto'],
    'psv eindhoven': ['psv'],
    'afc ajax': ['ajax'],
    'calcio como': ['como'],
    'aek athens fc': ['aek athens', 'aek'],
    'aek athens': ['aek'],
    'bodo glimt': ['bodo', 'glimt'],
    'athletico pr': ['athletico paranaense', 'athletico'],
    'athletico paranaense': ['athletico pr', 'athletico'],
    'hellas verona': ['verona'],
    'udinese calcio': ['udinese'],
    'ac monza': ['monza'],
    'acf fiorentina': ['fiorentina'],
    'real sociedad': ['sociedad'],
  };
  return {
    name,
    short,
    ...?known[name],
    ...?known[short],
  }.where((s) => s.length >= 3).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

bool programmeCoversMatch(Map programme, Map match, {DateTime? now}) {
  if (!currentFootballProgramme(programme, now: now)) return false;
  final kickoff = DateTime.tryParse('${match['kickoff_at'] ?? ''}');
  if (kickoff == null) return false;
  final start = DateTime.fromMillisecondsSinceEpoch((programme['start'] as num).toInt(), isUtc: true);
  final gap = start.difference(kickoff.toUtc()).inMinutes;
  if (gap < -90 || gap > 75) return false;
  final body = ' ${_words(programmeSearchText(programme))} ';
  // Mask the longest home-team name before finding the away team, so the
  // word Milan inside Inter Milan cannot also satisfy AC Milan.
  for (final home in _aliases(match['home_team'])) {
    final needle = ' $home ';
    final index = body.indexOf(needle);
    if (index < 0) continue;
    final remaining = body.replaceRange(index, index + needle.length, ' ');
    return _aliases(match['away_team']).any((away) => remaining.contains(' $away '));
  }
  return false;
}

/// Best default Channels search keyword when a live fixture has no EPG hit yet.
String suggestedChannelQueryForLeague(String league) {
  final l = _words(league);
  if (l.contains('serie a')) return 'beIN Sports';
  if (l.contains('la liga') || l.contains('laliga')) return 'beIN Sports';
  if (l.contains('premier league')) return 'beIN';
  if (l.contains('champions league') || l.contains('europa league')) return 'TNT Sports';
  if (l.contains('bundesliga')) return 'Sky Sport';
  if (l.contains('ligue 1')) return 'beIN Sports';
  if (l.contains('brasileirao')) return 'Premiere';
  if (l.contains('nba')) return 'NBA';
  return 'beIN Sports';
}

bool channelMatchesProgrammeQuery(Map channel, List<Map<String, dynamic>> programmes, String query) {
  final expanded = query.toLowerCase().replaceAll(RegExp(r'\bspurs\b|စပါး'), 'tottenham');
  final terms = _words(expanded).split(' ').where((s) => s.isNotEmpty).toList();
  if (terms.isEmpty) return true;
  final metadata = _words('${channel['name'] ?? ''} ${channel['category'] ?? ''}');
  bool matches(String text) => terms.every(text.contains);
  return matches(metadata) || programmes.any((p) => matches('$metadata ${_words(programmeSearchText(p))}'));
}
