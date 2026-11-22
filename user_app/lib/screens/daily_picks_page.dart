import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../models/daily_pick.dart';
import '../services/daily_picks_repository.dart';
import '../widgets/noellyne_dock_bar.dart';

enum _PicksSection { picks, results }

/// Daily Bets feed — n8n Hermes picks & settled ROI rendered as interactive
/// cards (zero emojis in structural UI, vector icons + design tokens only).
///
/// Uses Stale-While-Revalidate (L1 RAM + L2 disk cache): revisiting the tab or
/// hitting a flaky mobile network NEVER blanks previously loaded picks.
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
  static _PicksSection _lastSection = _PicksSection.picks;
  static PickFilter _lastFilter = PickFilter.all;

  DailyPicksBoard? _board;
  bool _initialLoading = true;
  bool _refreshing = false;
  _PicksSection _section = _lastSection;
  PickFilter _filter = _lastFilter;

  @override
  void initState() {
    super.initState();
    final mem = widget.repository.peekCachedBoard();
    if (mem != null && mem.hasData) {
      _board = mem;
      _initialLoading = false;
    }
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // 1. Cold-start disk restore so picks appear immediately even offline.
    if (_board == null) {
      final disk = await widget.repository.loadCachedBoard();
      if (!mounted) return;
      if (disk != null && disk.hasData) {
        setState(() {
          _board = disk;
          _initialLoading = false;
        });
      }
    }

    // 2. Skip DB round-trip if memory cache is still fresh (< 3 min).
    if (widget.repository.isCacheFresh && _board != null) {
      if (_initialLoading && mounted) {
        setState(() => _initialLoading = false);
      }
      return;
    }

    // 3. Revalidate silently in background without blanking existing cards.
    await _refresh(force: false);
  }

  Future<void> _refresh({bool force = true}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_board == null) _initialLoading = true;
      });
    }
    final next = await widget.repository.fetchBoard(force: force);
    if (!mounted) return;
    setState(() {
      // Never wipe an already-loaded board with an empty failed response.
      if (next.hasData || _board == null || next.errorMessage == null) {
        _board = next;
      } else {
        _board = _board!.copyWith(
          fromCache: true,
          syncNotice: next.syncNotice ??
              'Mtandao umecheza — unaona picks zilizohifadhiwa.',
        );
      }
      _initialLoading = false;
      _refreshing = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _askAiAboutPick(DailyPick pick) {
    HapticFeedback.lightImpact();
    final prompt =
        'Chambua mechi hii ya ${pick.match} (${pick.league}): '
        'pick ya ${pick.pick} @ ${pick.odds.toStringAsFixed(2)} '
        '(${pick.confidence}% conf). Je ni salama kuweka pesa leo?';
    openAiChat(
      context,
      initialPrompt: prompt,
      matchContext: pick.toAiContext(),
    );
  }

  void _openStakeSplit() {
    HapticFeedback.lightImpact();
    openAiChat(context, initialPrompt: 'Nina 10,000 leo');
  }

  String _subtitleText() {
    final b = _board;
    if (b == null || b.fetchedAt == null) {
      return 'Hermes Sports AI · Football & NBA';
    }
    final mins = DateTime.now().difference(b.fetchedAt!).inMinutes;
    final ageLabel = mins <= 0
        ? 'just now'
        : mins < 60
            ? '${mins}m ago'
            : '${(mins / 60).floor()}h ago';
    if (b.syncNotice != null) {
      return 'Offline cache · Updated $ageLabel';
    }
    return 'Hermes Sports AI · Updated $ageLabel';
  }

  @override
  Widget build(BuildContext context) {
    final board =
        _board ?? const DailyPicksBoard(published: [], settled: []);
    final activeList = _section == _PicksSection.picks
        ? board.published
        : board.settled;
    final filtered =
        activeList.where((p) => _filter.matches(p)).toList(growable: false);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 0,
        title: _Header(subtitle: _subtitleText()),
        actions: [
          IconButton(
            onPressed: _openStakeSplit,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'BetPawa stake split',
          ),
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(force: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh picks',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _refreshing && !_initialLoading
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  color: NoellyneColors.glowDeep,
                  backgroundColor: Colors.transparent,
                )
              : Divider(
                  height: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: .35),
                ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: const NoellyneDockBar(current: NoellyneTab.picks),
      body: NoellyneBackground(
        child: _initialLoading
            ? const _PicksSkeleton()
            : RefreshIndicator(
                color: NoellyneColors.glowDeep,
                onRefresh: () => _refresh(force: true),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    if (board.errorMessage != null && board.isEmpty)
                      SliverToBoxAdapter(
                        child: _ErrorState(
                          message: board.errorMessage!,
                          onRetry: () => _refresh(force: true),
                        ),
                      )
                    else ...[
                      if (board.syncNotice != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: _CacheStatusBanner(
                              message: board.syncNotice!,
                              onRetry: () => _refresh(force: true),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: _SectionSwitch(
                            selected: _section,
                            picksCount: board.published.length,
                            resultsCount: board.settled.length,
                            onChanged: (s) {
                              HapticFeedback.lightImpact();
                              _lastSection = s;
                              setState(() => _section = s);
                            },
                          ),
                        ),
                      ),
                      if (DailyPicksRepository.showsSampleData &&
                          board.published.isNotEmpty &&
                          _section == _PicksSection.picks)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: _SampleBanner(),
                          ),
                        ),
                      if (_section == _PicksSection.results &&
                          board.settled.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: _RoiSummaryCard(settled: board.settled),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: _FilterRail(
                            selected: _filter,
                            onSelected: (f) {
                              HapticFeedback.lightImpact();
                              _lastFilter = f;
                              setState(() => _filter = f);
                            },
                          ),
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverToBoxAdapter(
                          child: _EmptyPicks(
                            isResults: _section == _PicksSection.results,
                            onRefresh: () => _refresh(force: true),
                          ),
                        )
                      else
                        SliverPadding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverList.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) => RevealIn(
                              delay: Duration(
                                milliseconds: (35 * i).clamp(0, 280).toInt(),
                              ),
                              child: _section == _PicksSection.results
                                  ? _SettledPickCard(pick: filtered[i])
                                  : PickCard(
                                      pick: filtered[i],
                                      onAskAi: () =>
                                          _askAiAboutPick(filtered[i]),
                                      onWatch: () {
                                        final id = filtered[i].streamId;
                                        if (id == null) {
                                          _toast('No stream linked yet');
                                          return;
                                        }
                                        if (widget.onWatchMatch == null) {
                                          _toast(
                                            'Open this pick from the Live tab',
                                          );
                                          return;
                                        }
                                        widget.onWatchMatch!.call(id);
                                      },
                                      onCopy: () async {
                                        final p = filtered[i];
                                        final buf = StringBuffer()
                                          ..writeln('Noellyne Bet · ${p.league}')
                                          ..writeln(p.match)
                                          ..writeln(
                                            'Pick: ${p.pick} @ ${p.odds.toStringAsFixed(2)} '
                                            '(${p.confidence}% conf'
                                            '${p.tier.isNotEmpty ? ' · ${p.tier}' : ''})',
                                          );
                                        if (p.units > 0) {
                                          buf.writeln(
                                            'Stake: ${p.units.toStringAsFixed(2)}u',
                                          );
                                        }
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: buf.toString().trim(),
                                          ),
                                        );
                                        _toast(
                                          'Pick copied — ready to share or bet',
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: _Disclaimer()),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.subtitle});

  final String subtitle;

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
          subtitle,
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

class _CacheStatusBanner extends StatelessWidget {
  const _CacheStatusBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: NoellyneColors.glowDeep.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: NoellyneColors.glowDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({
    required this.selected,
    required this.picksCount,
    required this.resultsCount,
    required this.onChanged,
  });

  final _PicksSection selected;
  final int picksCount;
  final int resultsCount;
  final ValueChanged<_PicksSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? NoellyneColors.glassBorderDark
              : NoellyneColors.glassBorderLight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentItem(
              icon: Icons.bolt_rounded,
              label: 'Today ($picksCount)',
              selected: selected == _PicksSection.picks,
              onTap: () => onChanged(_PicksSection.picks),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentItem(
              icon: Icons.analytics_outlined,
              label: 'Results ($resultsCount)',
              selected: selected == _PicksSection.results,
              onTap: () => onChanged(_PicksSection.results),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final fg = selected
        ? (dark ? NoellyneColors.ink : Colors.white)
        : scheme.onSurfaceVariant;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: NoellyneMotion.tap,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? (dark ? NoellyneColors.glowDark : NoellyneColors.ink)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoiSummaryCard extends StatelessWidget {
  const _RoiSummaryCard({required this.settled});

  final List<DailyPick> settled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final graded = settled.where((p) => p.isWon || p.isLost).toList();
    final wins = graded.where((p) => p.isWon).length;
    final losses = graded.length - wins;
    final wr = graded.isEmpty ? 0.0 : (wins / graded.length) * 100;
    final netUnits = graded.fold<double>(0, (a, p) => a + p.profitUnits);
    final netTzs = (netUnits * 1000).round();

    final fb = graded.where((p) => !p.isBasketball).toList();
    final fbW = fb.where((p) => p.isWon).length;
    final bb = graded.where((p) => p.isBasketball).toList();
    final bbW = bb.where((p) => p.isWon).length;

    final positive = netUnits >= 0;
    final profitColor = positive
        ? (dark ? NoellyneColors.winDark : NoellyneColors.winInk)
        : NoellyneColors.lossInk;

    return GlassCard(
      glowCorner: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 18, color: profitColor),
              const SizedBox(width: 8),
              Text(
                'Verified Performance',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: positive
                      ? (dark
                          ? NoellyneColors.winDark.withValues(alpha: .16)
                          : NoellyneColors.winBg)
                      : (dark
                          ? NoellyneColors.lossInk.withValues(alpha: .18)
                          : NoellyneColors.lossBg),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: TabularText(
                  '${positive ? '+' : ''}${netUnits.toStringAsFixed(2)}u',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: profitColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Win Rate',
                  value: '${wr.toStringAsFixed(1)}%',
                  sub: '${wins}W / ${losses}L',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Est. P&L (1u=1k)',
                  value:
                      '${netTzs >= 0 ? '+' : '-'}TZS ${_fmtTzs(netTzs.abs())}',
                  sub: 'Net bankroll',
                  valueColor: profitColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniSplit(
                  icon: Icons.sports_soccer_rounded,
                  label: 'Football: ${fbW}W / ${fb.length - fbW}L',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniSplit(
                  icon: Icons.sports_basketball_rounded,
                  label: 'NBA: ${bbW}W / ${bb.length - bbW}L',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtTzs(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TabularText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSplit extends StatelessWidget {
  const _MiniSplit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettledPickCard extends StatelessWidget {
  const _SettledPickCard({required this.pick});

  final DailyPick pick;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final won = pick.isWon;
    final badgeBg = won
        ? (dark
            ? NoellyneColors.winDark.withValues(alpha: .18)
            : NoellyneColors.winBg)
        : (dark
            ? NoellyneColors.lossInk.withValues(alpha: .18)
            : NoellyneColors.lossBg);
    final badgeFg = won
        ? (dark ? NoellyneColors.winDark : NoellyneColors.winInk)
        : NoellyneColors.lossInk;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pick.isBasketball
                    ? Icons.sports_basketball_rounded
                    : Icons.sports_soccer_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pick.match,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      won ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 13,
                      color: badgeFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      won ? 'WON' : 'LOST',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${pick.league} · ${pick.pick} @ ${pick.odds.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (pick.score.isNotEmpty) ...[
                const SizedBox(width: 8),
                TabularText(
                  pick.score,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (pick.units > 0)
                Text(
                  'Stake: ${pick.units.toStringAsFixed(2)}u',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              TabularText(
                '${pick.profitUnits >= 0 ? '+' : ''}${pick.profitUnits.toStringAsFixed(2)}u',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: badgeFg,
                ),
              ),
            ],
          ),
        ],
      ),
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
/// Watch / Ask AI / Copy actions.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.pick,
    this.onWatch,
    this.onAskAi,
    this.onCopy,
  });

  final DailyPick pick;
  final VoidCallback? onWatch;
  final VoidCallback? onAskAi;
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
          const SizedBox(height: 4),
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
          if (pick.tier.isNotEmpty ||
              pick.units > 0 ||
              pick.edgePct > 0 ||
              pick.injuryNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (pick.tier.isNotEmpty)
                  _MetaChip(
                    icon: Icons.workspace_premium_rounded,
                    label: pick.tier,
                  ),
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
                  label: pick.isBasketball ? 'Watch' : 'Watch Live',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onWatch,
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                label: 'Ask AI',
                icon: Icons.auto_awesome_rounded,
                expand: false,
                height: 44,
                tone: PillTone.glow,
                onPressed: onAskAi,
              ),
              const SizedBox(width: 8),
              PillButton(
                label: 'Share',
                icon: Icons.copy_all_rounded,
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
              : NoellyneColors.glassBorderLight,
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
              : NoellyneColors.glassBorderLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
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
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .5),
          borderRadius: BorderRadius.circular(26),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 42, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Jaribu Tena'),
          ),
        ],
      ),
    );
  }
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : NoellyneColors.liveBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NoellyneColors.glowDeep.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.science_rounded,
            size: 16,
            color: NoellyneColors.glowDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'SAMPLE DATA — design fixtures, not live picks.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPicks extends StatelessWidget {
  const _EmptyPicks({this.isResults = false, this.onRefresh});

  final bool isResults;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(
            isResults
                ? Icons.analytics_outlined
                : Icons.auto_awesome_rounded,
            size: 40,
            color: NoellyneColors.glowDeep.withValues(alpha: .8),
          ),
          const SizedBox(height: 12),
          Text(
            isResults ? 'No settled results yet' : 'No picks for this filter',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isResults
                ? 'Hermes Settlement grades finished Football and NBA picks '
                    'automatically at 01:30 and 08:45 EAT.'
                : 'The Hermes pipeline publishes fresh Football and NBA picks '
                    'at 09:00, 14:00 and 19:00 EAT.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (onRefresh != null)
            FilledButton.icon(
              onPressed: () => onRefresh!(),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Check again'),
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
