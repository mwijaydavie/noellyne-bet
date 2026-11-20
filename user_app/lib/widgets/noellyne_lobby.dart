import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import 'team_crest.dart';

/// Lobby filter applied to the live feed list.
enum LobbyFilter {
  liveNow('Live Now'),
  upcoming('Upcoming'),
  all('All');

  const LobbyFilter(this.label);
  final String label;
}

/// Brand block used in the lobby app bar.
class LobbyBrand extends StatelessWidget {
  const LobbyBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [NoellyneColors.glowSoft, NoellyneColors.glowDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: NoellyneColors.glowDeep.withValues(alpha: .45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'N',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: dark ? NoellyneColors.ink : Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Noellyne Bet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -.02 * 16,
                height: 1.1,
                color: scheme.onSurface,
              ),
            ),
            Text(
              'LIVE FOOTBALL',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Featured match hero — the "banker slip" slot at the top of the lobby.
class HeroMatchCard extends StatelessWidget {
  const HeroMatchCard({
    super.key,
    required this.league,
    required this.homeName,
    required this.awayName,
    required this.isLive,
    required this.canWatch,
    required this.onWatch,
    this.homeLogo,
    this.awayLogo,
    this.kickoff,
    this.lineCount = 0,
    this.metaLabel,
  });

  final String league;
  final String homeName;
  final String awayName;
  final bool isLive;
  final bool canWatch;
  final VoidCallback onWatch;
  final String? homeLogo;
  final String? awayLogo;
  final DateTime? kickoff;
  final int lineCount;
  final String? metaLabel;

  String get _kickoffLabel {
    final k = kickoff;
    if (k == null) return 'Kickoff TBC';
    final now = DateTime.now();
    final sameDay = k.year == now.year && k.month == now.month && k.day == now.day;
    final hh = k.hour.toString().padLeft(2, '0');
    final mm = k.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Today · $hh:$mm';
    final tomorrow = now.add(const Duration(days: 1));
    if (k.year == tomorrow.year &&
        k.month == tomorrow.month &&
        k.day == tomorrow.day) {
      return 'Tomorrow · $hh:$mm';
    }
    return '${k.day}/${k.month} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassCard(
      glowCorner: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              isLive
                  ? const LivePill(text: "LIVE")
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.brightness == Brightness.dark
                            ? NoellyneColors.glowDeep.withValues(alpha: .18)
                            : NoellyneColors.liveBg,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '★ FEATURED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                          color: scheme.brightness == Brightness.dark
                              ? NoellyneColors.glowSoft
                              : NoellyneColors.liveInk,
                        ),
                      ),
                    ),
              const Spacer(),
              Flexible(
                child: Text(
                  league,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TeamBlock(name: homeName, logo: homeLogo)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    TabularText(
                      'VS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.02 * 20,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLive ? 'LIVE NOW' : _kickoffLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _TeamBlock(name: awayName, logo: awayLogo)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (lineCount > 0) ...[
                _MetaPill(
                  icon: Icons.sensors_rounded,
                  label: lineCount == 1 ? '1 server' : '$lineCount servers',
                ),
                const SizedBox(width: 6),
              ],
              _MetaPill(icon: Icons.hd_rounded, label: 'HD stream'),
            ],
          ),
          const SizedBox(height: 14),
          PillButton(
            label: canWatch ? '▶  WATCH LIVE' : 'NOT READY YET',
            onPressed: canWatch ? onWatch : null,
          ),
        ],
      ),
    );
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.name, this.logo});

  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Always renders a badge: feed crest → curated colours → initials.
        TeamCrest(name: name, logoUrl: logo, size: 56),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -.1,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: dark
              ? NoellyneColors.glassBorderDark
              : NoellyneColors.glassBorderLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal pill rail selecting which matches the lobby shows.
class LobbyFilterRail extends StatelessWidget {
  const LobbyFilterRail({
    super.key,
    required this.selected,
    required this.onSelected,
    this.extraLeagues = const [],
    this.selectedLeague,
    this.onLeagueSelected,
  });

  final LobbyFilter selected;
  final ValueChanged<LobbyFilter> onSelected;
  final List<String> extraLeagues;
  final String? selectedLeague;
  final ValueChanged<String?>? onLeagueSelected;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      for (final f in LobbyFilter.values)
        FilterPill(
          label: f.label,
          selected: f == selected && (selectedLeague == null),
          onTap: () {
            onSelected(f);
            if (selectedLeague != null) onLeagueSelected?.call(null);
          },
        ),
      for (final league in extraLeagues.take(4))
        FilterPill(
          label: league,
          selected: selectedLeague == league,
          onTap: () => onLeagueSelected?.call(
            selectedLeague == league ? null : league,
          ),
        ),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}
