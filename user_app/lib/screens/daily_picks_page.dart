import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../models/daily_pick.dart';
import '../services/daily_picks_repository.dart';

/// Daily Bets feed — n8n picks rendered as structured, tappable cards.
/// See DESIGN_SYSTEM.md § "Daily Bets Feed (n8n)".
class DailyPicksPage extends StatefulWidget {
  const DailyPicksPage({
    super.key,
    this.onWatchMatch,
    this.repository = const DailyPicksRepository(),
  });

  /// Deep-links into the player for a given `stream_id`.
  final ValueChanged<String>? onWatchMatch;
  final DailyPicksRepository repository;

  @override
  State<DailyPicksPage> createState() => _DailyPicksPageState();
}

class _DailyPicksPageState extends State<DailyPicksPage> {
  late Future<List<DailyPick>> _future;
  PickFilter _filter = PickFilter.all;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetch();
  }

  Future<void> _refresh() async {
    final next = widget.repository.fetch();
    setState(() => _future = next);
    await next;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // A Scaffold is mandatory here: without it the route has no Material
    // ancestor, so ThemeData is dropped and every Text falls back to the
    // yellow double-underlined debug style.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 0,
        title: const _Header(),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh picks',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: .35),
          ),
        ),
      ),
      body: NoellyneBackground(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<DailyPick>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _PicksSkeleton();
                  }
                  final all = snapshot.data ?? const <DailyPick>[];
                  final picks =
                      all.where((p) => _filter.matches(p)).toList(growable: false);

                  return RefreshIndicator(
                    color: NoellyneColors.glowDeep,
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: _FilterRail(
                              selected: _filter,
                              onSelected: (f) => setState(() => _filter = f),
                            ),
                          ),
                        ),
                        if (picks.isEmpty)
                          const SliverToBoxAdapter(child: _EmptyPicks())
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            sliver: SliverList.separated(
                              itemCount: picks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) => RevealIn(
                                delay: Duration(milliseconds: 40 * i),
                                child: PickCard(
                                  pick: picks[i],
                                  onWatch: () {
                                    final id = picks[i].streamId;
                                    if (id == null) {
                                      _toast('No stream linked yet');
                                      return;
                                    }
                                    if (widget.onWatchMatch == null) {
                                      _toast('Open this pick from the Live tab');
                                      return;
                                    }
                                    widget.onWatchMatch!.call(id);
                                  },
                                  onCopy: () async {
                                    final code = picks[i].slipCode;
                                    if (code == null) {
                                      _toast('No slip code for this pick');
                                      return;
                                    }
                                    await Clipboard.setData(
                                      ClipboardData(text: code),
                                    );
                                    _toast('Slip code $code copied');
                                  },
                                ),
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: _Disclaimer()),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Picks',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: NoellyneUI.headlineTracking,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'Curated by Noellyne AI · updated every morning',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FilterRail extends StatelessWidget {
  const _FilterRail({required this.selected, required this.onSelected});

  final PickFilter selected;
  final ValueChanged<PickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PickFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = PickFilter.values[i];
          return FilterPill(
            label: f.label,
            selected: f == selected,
            onTap: () => onSelected(f),
          );
        },
      ),
    );
  }
}

/// Structured diagnostic card: reasoning header, nested white stat rows,
/// obsidian CTA.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.pick,
    this.onWatch,
    this.onCopy,
  });

  final DailyPick pick;
  final VoidCallback? onWatch;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      glowCorner: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pick.match,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ConfidenceChip(confidence: pick.confidence),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            pick.league,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (pick.reasoning.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              pick.reasoning,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _InnerRow(
            icon: pick.isBasketball
                ? Icons.sports_basketball_rounded
                : Icons.sports_soccer_rounded,
            title: pick.pick,
            subtitle: 'Market & Pick',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TabularText(
                      pick.odds.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '${pick.confidence}% conf.',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dark ? NoellyneColors.glowDark : NoellyneColors.ink,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: dark ? NoellyneColors.ink : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (pick.units > 0 ||
              pick.edgePct > 0 ||
              pick.injuryNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (pick.tier.isNotEmpty)
                  _MetaChip(icon: Icons.workspace_premium_rounded, label: pick.tier),
                if (pick.units > 0)
                  _MetaChip(
                    icon: Icons.savings_rounded,
                    label: '${pick.units.toStringAsFixed(2)}u stake',
                  ),
                if (pick.edgePct > 0)
                  _MetaChip(
                    icon: Icons.trending_up_rounded,
                    label: '+${pick.edgePct.toStringAsFixed(1)}% edge',
                  ),
                if (pick.injuryNote.isNotEmpty)
                  _MetaChip(
                    icon: Icons.medical_services_rounded,
                    label: pick.injuryNote,
                    warn: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: pick.isBasketball ? 'Watch Game' : 'Watch Live',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onWatch,
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                label: 'Copy',
                icon: Icons.copy_rounded,
                expand: false,
                height: 44,
                tone: PillTone.ghost,
                onPressed: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InnerRow extends StatelessWidget {
  const _InnerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark
              ? NoellyneColors.glassBorderDark
              : const Color(0x99FFFFFF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (dark ? NoellyneColors.glowDark : NoellyneColors.glowSoft)
                  .withValues(alpha: dark ? .2 : .3),
            ),
            child: Icon(
              icon,
              size: 17,
              color: dark ? NoellyneColors.glowSoft : NoellyneColors.liveInk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final accent = warn ? NoellyneColors.liveInk : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: warn
            ? (dark
                ? NoellyneColors.glowDark.withValues(alpha: .16)
                : NoellyneColors.liveBg)
            : (dark ? NoellyneColors.innerDark : NoellyneColors.innerLight),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: dark
              ? NoellyneColors.glassBorderDark
              : const Color(0x66FFFFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: accent),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final int confidence;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final strong = confidence >= 80;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: strong
            ? (dark ? NoellyneColors.glowDark : NoellyneColors.liveBg)
            : (dark ? NoellyneColors.innerDark : NoellyneColors.innerLight),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            strong ? Icons.bolt_rounded : Icons.insights_rounded,
            size: 13,
            color: strong
                ? (dark ? NoellyneColors.ink : NoellyneColors.liveInk)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          TabularText(
            '$confidence%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: strong
                  ? (dark ? NoellyneColors.ink : NoellyneColors.liveInk)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PicksSkeleton extends StatelessWidget {
  const _PicksSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 190,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: .5),
          borderRadius: BorderRadius.circular(26),
        ),
      ),
    );
  }
}

class _EmptyPicks extends StatelessWidget {
  const _EmptyPicks();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded,
              size: 40, color: NoellyneColors.glowDeep.withValues(alpha: .8)),
          const SizedBox(height: 12),
          Text(
            'No picks in this filter',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try “All Picks” — new slips drop every morning.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Text(
        'Picks are model estimates, not guarantees. 18+. Play responsibly.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
