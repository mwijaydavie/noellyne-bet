import 'package:flutter/material.dart';

import 'resilient_logo.dart';

/// A team badge that **always** renders something recognisable.
///
/// Order of resolution:
///  1. the remote crest supplied by the feed (`home_logo_url` / `away_logo_url`),
///  2. a brand-coloured generated crest (curated palette → deterministic hue),
///  3. the club initials, so no team is ever a grey shield.
///
/// This is what makes the lobby look complete even when a feed row is missing
/// its logo (Tanzanian/NBC, African and lower-league fixtures usually are).
class TeamCrest extends StatelessWidget {
  const TeamCrest({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 44,
    this.channelId,
    this.shape = CrestShape.circle,
    this.showShadow = true,
  });

  final String name;
  final String? logoUrl;
  final double size;
  final String? channelId;
  final CrestShape shape;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final url = (logoUrl ?? '').trim();
    final brand = TeamBrand.resolve(name);
    final generated = _GeneratedCrest(
      brand: brand,
      size: size,
      shape: shape,
      showShadow: showShadow,
    );

    if (url.isEmpty) return generated;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ResilientLogo(
          value: url,
          channelId: channelId,
          width: size,
          height: size,
          fit: BoxFit.contain,
          fallback: generated,
        ),
      ),
    );
  }
}

enum CrestShape { circle, rounded }

class _GeneratedCrest extends StatelessWidget {
  const _GeneratedCrest({
    required this.brand,
    required this.size,
    required this.shape,
    required this.showShadow,
  });

  final TeamBrand brand;
  final double size;
  final CrestShape shape;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final radius = shape == CrestShape.circle ? size : size * .32;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brand.from, brand.to],
        ),
        border: Border.all(
          color: brand.ink == Colors.white
              ? Colors.white.withValues(alpha: .55)
              : const Color(0x331D1918),
          width: size >= 48 ? 1.5 : 1,
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: brand.from.withValues(alpha: .35),
                  blurRadius: size * .28,
                  offset: Offset(0, size * .12),
                ),
              ]
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * .12),
          child: Text(
            brand.initials,
            style: TextStyle(
              fontSize: size * .34,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
              height: 1,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual identity for a club, derived from its name.
class TeamBrand {
  const TeamBrand({
    required this.initials,
    required this.from,
    required this.to,
  });

  final String initials;
  final Color from;
  final Color to;

  /// Readable ink for the generated badge (white clubs need dark letters).
  Color get ink => from.computeLuminance() > .58
      ? const Color(0xFF1D1918)
      : Colors.white;

  static TeamBrand resolve(String rawName) {
    final name = rawName.trim();
    final key = _normalise(name);
    final curated = _palette[key];
    if (curated != null) {
      return TeamBrand(
        initials: curated.$3,
        from: curated.$1,
        to: curated.$2,
      );
    }
    // Fuzzy pass: "Arsenal FC" → "arsenal".
    for (final entry in _palette.entries) {
      if (key == entry.key ||
          key.startsWith('${entry.key} ') ||
          key.endsWith(' ${entry.key}') ||
          key.contains(entry.key)) {
        final v = entry.value;
        return TeamBrand(initials: v.$3, from: v.$1, to: v.$2);
      }
    }
    final hue = (_hash(key) % 360).toDouble();
    return TeamBrand(
      initials: _initials(name),
      from: HSLColor.fromAHSL(1, hue, .62, .42).toColor(),
      to: HSLColor.fromAHSL(1, (hue + 24) % 360, .68, .30).toColor(),
    );
  }

  static String _normalise(String s) {
    const diacritics = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c', 'ø': 'o', 'š': 's', 'ž': 'z', 'ć': 'c',
    };
    final lower = s.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(diacritics[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static final _stopWords = {
    'fc', 'cf', 'sc', 'afc', 'ac', 'as', 'ss', 'cd', 'ca', 'club', 'the',
    'de', 'of', 'fk', 'bk', 'if', 'sk', 'nk', 'us', 'sv', 'krc', 'rc',
  };

  static String _initials(String name) {
    final words = _normalise(name)
        .split(' ')
        .where((w) => w.isNotEmpty && !_stopWords.contains(w))
        .toList();
    if (words.isEmpty) {
      final compact = _normalise(name).replaceAll(' ', '');
      return compact.isEmpty
          ? 'FC'
          : compact.substring(0, compact.length >= 3 ? 3 : compact.length)
              .toUpperCase();
    }
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length >= 3 ? 3 : w.length).toUpperCase();
    }
    final letters = words.take(3).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  static int _hash(String s) {
    var h = 2166136261;
    for (final code in s.codeUnits) {
      h ^= code;
      h = (h * 16777619) & 0x7fffffff;
    }
    return h;
  }

  /// Curated club colours so familiar badges feel right even without art.
  static const Map<String, (Color, Color, String)> _palette = {
    // England
    'arsenal': (Color(0xFFB3121C), Color(0xFF7A0C13), 'ARS'),
    'aston villa': (Color(0xFF94BEE5), Color(0xFF6B0F2B), 'AVL'),
    'bournemouth': (Color(0xFFD71920), Color(0xFF1B1B1B), 'BOU'),
    'brentford': (Color(0xFFD20000), Color(0xFF8B0000), 'BRE'),
    'brighton': (Color(0xFF0057B8), Color(0xFF003A7A), 'BHA'),
    'chelsea': (Color(0xFF1E58A8), Color(0xFF0B2E63), 'CHE'),
    'crystal palace': (Color(0xFF1B458F), Color(0xFFC8102E), 'CRY'),
    'everton': (Color(0xFF1B3FA0), Color(0xFF0C1F55), 'EVE'),
    'fulham': (Color(0xFF1B1B1B), Color(0xFF6B6B6B), 'FUL'),
    'liverpool': (Color(0xFFC8102E), Color(0xFF8A0B20), 'LIV'),
    'manchester city': (Color(0xFF6CABDD), Color(0xFF1C2C5B), 'MCI'),
    'manchester united': (Color(0xFFDA020E), Color(0xFF8B0009), 'MUN'),
    'newcastle': (Color(0xFF1B1B1B), Color(0xFF4C4C4C), 'NEW'),
    'nottingham': (Color(0xFFD6001C), Color(0xFF8A0012), 'NFO'),
    'tottenham': (Color(0xFF132257), Color(0xFF0A1230), 'TOT'),
    'west ham': (Color(0xFF7A263A), Color(0xFF3B1220), 'WHU'),
    'wolves': (Color(0xFFFDB913), Color(0xFF1B1B1B), 'WOL'),
    'leeds': (Color(0xFF1D428A), Color(0xFFF1C400), 'LEE'),
    'sunderland': (Color(0xFFEB172B), Color(0xFF1B1B1B), 'SUN'),
    'celtic': (Color(0xFF018749), Color(0xFF005C31), 'CEL'),
    'rangers': (Color(0xFF1B458F), Color(0xFFC8102E), 'RAN'),
    // Spain
    'real madrid': (Color(0xFFF5F5F5), Color(0xFFC9C9C9), 'RMA'),
    'barcelona': (Color(0xFFA50044), Color(0xFF004D98), 'BAR'),
    'atletico': (Color(0xFFCB3524), Color(0xFF1B3A6B), 'ATM'),
    'sevilla': (Color(0xFFD81920), Color(0xFF8A0F14), 'SEV'),
    'real betis': (Color(0xFF00954C), Color(0xFF00602F), 'BET'),
    'valencia': (Color(0xFFF5A623), Color(0xFF1B1B1B), 'VAL'),
    'villarreal': (Color(0xFFFBE122), Color(0xFF9E7C00), 'VIL'),
    'athletic': (Color(0xFFEE2523), Color(0xFF9A1210), 'ATH'),
    'real sociedad': (Color(0xFF0067B1), Color(0xFF003E6B), 'RSO'),
    // Italy
    'juventus': (Color(0xFF1B1B1B), Color(0xFF5C5C5C), 'JUV'),
    'ac milan': (Color(0xFFFB090B), Color(0xFF1B1B1B), 'MIL'),
    'inter': (Color(0xFF0068A8), Color(0xFF1B1B1B), 'INT'),
    'napoli': (Color(0xFF12A0D7), Color(0xFF0A6E95), 'NAP'),
    'roma': (Color(0xFF8E1F2F), Color(0xFFF0A500), 'ROM'),
    'lazio': (Color(0xFF87D8F7), Color(0xFF1B3A6B), 'LAZ'),
    'atalanta': (Color(0xFF1B1B1B), Color(0xFF2E5AA8), 'ATA'),
    'fiorentina': (Color(0xFF6A1B9A), Color(0xFF3E1059), 'FIO'),
    // Germany
    'bayern': (Color(0xFFDC052D), Color(0xFF0066B2), 'FCB'),
    'dortmund': (Color(0xFFFDE100), Color(0xFF1B1B1B), 'BVB'),
    'leverkusen': (Color(0xFFE32221), Color(0xFF1B1B1B), 'B04'),
    'leipzig': (Color(0xFFDD0741), Color(0xFF001F47), 'RBL'),
    'frankfurt': (Color(0xFF1B1B1B), Color(0xFFE1000F), 'SGE'),
    'stuttgart': (Color(0xFFE32219), Color(0xFFF4F4F4), 'VFB'),
    // France
    'psg': (Color(0xFF004170), Color(0xFFDA291C), 'PSG'),
    'paris saint': (Color(0xFF004170), Color(0xFFDA291C), 'PSG'),
    'marseille': (Color(0xFF2FAEE0), Color(0xFF1B6E8F), 'OM'),
    'lyon': (Color(0xFF1B3A6B), Color(0xFFDA291C), 'OL'),
    'monaco': (Color(0xFFE51B22), Color(0xFFF4F4F4), 'ASM'),
    'lille': (Color(0xFFE01E13), Color(0xFF0B2E63), 'LOSC'),
    // Portugal / Netherlands / Turkey
    'benfica': (Color(0xFFDA020E), Color(0xFF8B0009), 'SLB'),
    'porto': (Color(0xFF004E9E), Color(0xFF00306B), 'FCP'),
    'sporting': (Color(0xFF008057), Color(0xFF00513A), 'SCP'),
    'ajax': (Color(0xFFD2122E), Color(0xFF8A0B1E), 'AJA'),
    'psv': (Color(0xFFED1C24), Color(0xFF1B1B1B), 'PSV'),
    'feyenoord': (Color(0xFFE01E13), Color(0xFF1B1B1B), 'FEY'),
    'galatasaray': (Color(0xFFF5A623), Color(0xFFA81D1D), 'GAL'),
    'fenerbahce': (Color(0xFFFBE122), Color(0xFF1B3A6B), 'FEN'),
    'besiktas': (Color(0xFF1B1B1B), Color(0xFFF4F4F4), 'BJK'),
    // Africa / Tanzania
    'simba': (Color(0xFF1E8449), Color(0xFF0E4C28), 'SIM'),
    'yanga': (Color(0xFFF1C40F), Color(0xFF1B6B32), 'YAN'),
    'young africans': (Color(0xFFF1C40F), Color(0xFF1B6B32), 'YAN'),
    'azam': (Color(0xFF1B5E20), Color(0xFFF1C40F), 'AZA'),
    'namungo': (Color(0xFF1565C0), Color(0xFF0D3C73), 'NAM'),
    'al ahly': (Color(0xFFDA291C), Color(0xFF8B120A), 'AHL'),
    'zamalek': (Color(0xFFF4F4F4), Color(0xFFC8102E), 'ZAM'),
    'esperance': (Color(0xFFDA291C), Color(0xFFF1C40F), 'EST'),
    'wydad': (Color(0xFFDA291C), Color(0xFF8B120A), 'WAC'),
    'raja': (Color(0xFF1B8A3E), Color(0xFF0E5527), 'RCA'),
    'mamelodi': (Color(0xFFF1C40F), Color(0xFF1B1B1B), 'SUN'),
    'kaizer chiefs': (Color(0xFFF1C40F), Color(0xFF1B1B1B), 'KZC'),
    'orlando pirates': (Color(0xFF1B1B1B), Color(0xFFF4F4F4), 'OPI'),
    'gor mahia': (Color(0xFF1B8A3E), Color(0xFF0E5527), 'GOR'),
    'tp mazembe': (Color(0xFF1B5E20), Color(0xFFF1C40F), 'TPM'),
    // Americas
    'flamengo': (Color(0xFFD0021B), Color(0xFF1B1B1B), 'FLA'),
    'palmeiras': (Color(0xFF1B7A3E), Color(0xFF0E4C26), 'PAL'),
    'boca juniors': (Color(0xFF0B2E63), Color(0xFFF1C40F), 'BOC'),
    'river plate': (Color(0xFFF4F4F4), Color(0xFFC8102E), 'RIV'),
    'inter miami': (Color(0xFFF7B5CD), Color(0xFF1B1B1B), 'MIA'),
    'lafc': (Color(0xFF1B1B1B), Color(0xFFC8A45C), 'LAFC'),
  };
}
