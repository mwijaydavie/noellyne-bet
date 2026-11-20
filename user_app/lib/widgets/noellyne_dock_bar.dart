import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../noellyne_config.dart';
import '../screens/ai_chat_page.dart';
import '../screens/channels_page.dart';
import '../screens/daily_picks_page.dart';
import '../screens/network_diagnostics_page.dart';
import '../screens/reminders_page.dart';
import '../screens/settings_page.dart';
import '../screens/home_page.dart';
import 'noellyne_lobby.dart';
import 'theme_mode_button.dart';

/// The destinations every main screen shares. Live and Matches now live
/// together on Home as segments, so one tap can never land on a dead route.
enum NoellyneTab { home, channels, picks }

/// Shared floating stadium dock. Screens pass [onSelect] when they need to
/// persist their own state before leaving; otherwise navigation is handled here.
class NoellyneDockBar extends StatelessWidget {
  const NoellyneDockBar({
    super.key,
    required this.current,
    this.onSelect,
    this.onAi,
  });

  final NoellyneTab current;
  final ValueChanged<NoellyneTab>? onSelect;
  final VoidCallback? onAi;

  int get _index => switch (current) {
        NoellyneTab.home => 0,
        NoellyneTab.channels => 1,
        NoellyneTab.picks => 2,
      };

  static void _replace(BuildContext context, Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => page),
      (route) => false,
    );
  }

  static void goHome(BuildContext context, LobbyFilter filter) =>
      _replace(context, HomePage(initialFilter: filter));

  /// Replace the shell with [tab] — used by the native player's dock.
  static void goTab(BuildContext context, NoellyneTab tab) {
    switch (tab) {
      case NoellyneTab.home:
        _replace(context, const HomePage());
      case NoellyneTab.channels:
        _replace(context, const ChannelsPage());
      case NoellyneTab.picks:
        _replace(context, const DailyPicksPage());
    }
  }

  void _handle(BuildContext context, int index) {
    if (index == 3) {
      showNoellyneMoreSheet(context);
      return;
    }
    final tab = switch (index) {
      0 => NoellyneTab.home,
      1 => NoellyneTab.channels,
      _ => NoellyneTab.picks,
    };
    if (tab == current) return;
    if (onSelect != null) {
      onSelect!(tab);
      return;
    }
    switch (tab) {
      case NoellyneTab.home:
        _replace(context, const HomePage());
      case NoellyneTab.channels:
        _replace(context, const ChannelsPage());
      case NoellyneTab.picks:
        _replace(context, const DailyPicksPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FloatingDock(
        items: const [
          DockItem(
            icon: Icons.sports_soccer_outlined,
            activeIcon: Icons.sports_soccer_rounded,
            label: 'Home',
          ),
          DockItem(
            icon: Icons.tv_outlined,
            activeIcon: Icons.tv_rounded,
            label: 'Channels',
          ),
          DockItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
            label: 'Picks',
          ),
          DockItem(icon: Icons.menu_rounded, label: 'More'),
        ],
        index: _index,
        onSelected: (index) => _handle(context, index),
        onAiPressed: onAi ?? () => openAiChat(context),
        aiTooltip: 'Noellyne AI',
      ),
    );
  }
}

/// Opens the AI chat, with a shortcut to the Daily Picks feed.
Future<void> openAiChat(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AiChatPage(
        onOpenPicks: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DailyPicksPage()),
          );
        },
      ),
    ),
  );
}

/// Shared "More" sheet.
///
/// Deliberately short: Channels, Picks and stream sources already have proper
/// homes, so More is the settings/utility surface (and no longer buries it).
Future<void> showNoellyneMoreSheet(BuildContext context) async {
  void push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final scheme = Theme.of(context).colorScheme;
      return GlassBlur(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        sigma: 24,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'More',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                    ),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.notifications_active_rounded,
                title: 'Reminders',
                subtitle: 'Nudges before your kickoffs',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  push(const RemindersPage());
                },
              ),
              _MoreTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Noellyne AI',
                subtitle: 'Chat: picks, NBA, stake split',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openAiChat(context);
                },
              ),
              _MoreTile(
                icon: Icons.tune_rounded,
                title: 'Settings',
                subtitle: 'Profile, alerts, pinned teams, updates',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  push(const SettingsPage());
                },
              ),
              _MoreTile(
                icon: Icons.speed_rounded,
                title: 'Diagnostics',
                subtitle: 'Check routes, lines and backend health',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  push(const NetworkDiagnosticsPage());
                },
              ),
              const Divider(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        size: 17, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    const ThemeModeButton(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Text(
                  'Realtime: ${NoellyneConfig.supabaseLabel}',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: NoellyneColors.glowDeep.withValues(alpha: .12),
        ),
        child: Icon(icon, size: 18, color: NoellyneColors.glowDeep),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
    );
  }
}
