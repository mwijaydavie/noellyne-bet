import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../noellyne_config.dart';
import '../screens/ai_chat_page.dart';
import '../screens/channels_page.dart';
import '../screens/daily_picks_page.dart';
import '../screens/settings_page.dart';
import '../screens/home_page.dart';
import '../screens/source_browser_page.dart';
import '../viewer_navigation.dart';
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

/// Shared "More" sheet: stream sources, picks, AI, channels, theme.
Future<void> showNoellyneMoreSheet(BuildContext context) async {
  const sources = <(int, String, IconData)>[
    (1, 'Live 2', Icons.live_tv_rounded),
    (2, 'Soco', Icons.sports_soccer_rounded),
    (3, 'YYZB', Icons.sensors_rounded),
    (4, 'ColaTV', Icons.tv_rounded),
    (5, 'Fawa', Icons.language_rounded),
  ];

  void push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return GlassBlur(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
        sigma: 24,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
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
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text(
                    'Noellyne AI',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Chat: picks, NBA, mgao wa mtaji'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openAiChat(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: const Text(
                    'Daily Picks',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Slips from the n8n pipeline'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    push(const DailyPicksPage());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tv_rounded),
                  title: const Text(
                    'Channels',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('All broadcaster channels'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    push(const ChannelsPage());
                  },
                ),
                const Divider(height: 14),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'STREAM SOURCES',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
                for (final (index, label, icon) in sources)
                  ListTile(
                    dense: true,
                    leading: Icon(icon, size: 20),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      push(
                        SourceBrowserPage(source: viewerSourceAt(index)),
                      );
                    },
                  ),
                const Divider(height: 14),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text(
                    'Settings',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Profile, reminders, notifications, pinned teams',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    push(const SettingsPage());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text(
                    'Appearance',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('System, light or dark'),
                  trailing: const ThemeModeButton(),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Noellyne Bet · made for match day',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Realtime: ${NoellyneConfig.supabaseLabel}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
