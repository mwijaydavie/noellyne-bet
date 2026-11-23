import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../app_update_service.dart';
import '../channel_library.dart';
import '../design/noellyne_skeleton.dart';
import '../design/noellyne_ui.dart';
import '../noellyne_config.dart';
import '../services/daily_picks_repository.dart';
import '../services/noellyne_auth_service.dart';
import '../services/noellyne_push_service.dart';
import '../widgets/theme_mode_button.dart';
import 'reminders_page.dart';

/// Dedicated settings screen: profile, reminders, notifications, pinned teams,
/// appearance, updates and data hygiene. No legacy branding anywhere.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _kName = 'noellyne.profile.name';
  static const _kPinned = 'noellyne.profile.pinned';
  static const _kReminders = 'noellyne.alerts.reminders';
  static const _kLead = 'noellyne.alerts.lead';
  static const _kGoals = 'noellyne.alerts.goals';
  static const _kPinnedOnly = 'noellyne.alerts.pinnedOnly';
  static const _kPushPicks = NoellynePushService.prefPicksKey;
  static const _kPushResults = NoellynePushService.prefResultsKey;

  final _prefs = <String, Object>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs[_kName] = prefs.getString(_kName) ?? '';
      _prefs[_kPinned] = prefs.getStringList(_kPinned) ?? <String>[];
      _prefs[_kReminders] = prefs.getBool(_kReminders) ?? true;
      _prefs[_kLead] = prefs.getInt(_kLead) ?? 30;
      _prefs[_kGoals] = prefs.getBool(_kGoals) ?? true;
      _prefs[_kPinnedOnly] = prefs.getBool(_kPinnedOnly) ?? false;
      _prefs[_kPushPicks] = prefs.getBool(_kPushPicks) ?? true;
      _prefs[_kPushResults] = prefs.getBool(_kPushResults) ?? true;
      _loading = false;
    });
  }

  Future<void> _set(String key, Object value) async {
    setState(() => _prefs[key] = value);
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is List<String>) await prefs.setStringList(key, value);
  }

  String get _name => (_prefs[_kName] as String? ?? '').trim();
  List<String> get _pinned => (_prefs[_kPinned] as List<String>? ?? const []);
  bool get _reminders => _prefs[_kReminders] as bool? ?? true;
  int get _lead => _prefs[_kLead] as int? ?? 30;
  bool get _goals => _prefs[_kGoals] as bool? ?? true;
  bool get _pinnedOnly => _prefs[_kPinnedOnly] as bool? ?? false;
  bool get _pushPicks => _prefs[_kPushPicks] as bool? ?? true;
  bool get _pushResults => _prefs[_kPushResults] as bool? ?? true;

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Mwijay',
            labelText: 'Display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) await _set(_kName, value);
  }

  Future<void> _addPinned() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pin a team'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Simba SC',
            labelText: 'Team',
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Pin'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    if (_pinned.any((t) => t.toLowerCase() == value.toLowerCase())) return;
    await _set(_kPinned, [..._pinned, value]);
    HapticFeedback.selectionClick();
  }

  Future<void> _removePinned(String team) async {
    await _set(_kPinned, _pinned.where((t) => t != team).toList());
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear channel data?'),
        content: const Text(
          'Removes favorites and recent channels on this device. Your account '
          'and picks are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChannelLibrary.instance.load();
    ChannelLibrary.instance.favorites.clear();
    ChannelLibrary.instance.recent.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nca_channel_favorites_v1');
    await prefs.remove('nca_channel_recent_v1');
    await prefs.remove('noellyne_daily_picks_board_v1');
    DailyPicksRepository.clearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Cached data cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.3),
        ),
      ),
      body: _loading
          ? const SkeletonRows(count: 7)
          : NoellyneBackground(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                children: [
                  const _AccountCard(),
                  const SizedBox(height: 12),
                  _ProfileCard(
                    name: _name,
                    pinned: _pinned,
                    onEditName: _editName,
                    onAddPin: _addPinned,
                    onRemovePin: _removePinned,
                  ),
                  const _SectionLabel('ALERTS'),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: _reminders,
                          onChanged: (v) => _set(_kReminders, v),
                          title: const _TileTitle('Match reminders'),
                          subtitle: const _TileSub(
                            'A nudge before kickoff for your pinned teams',
                          ),
                          secondary: const _TileIcon(Icons.alarm_rounded),
                        ),
                        if (_reminders)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                const _TileSub('Remind me'),
                                const SizedBox(width: 10),
                                for (final m in const [15, 30, 60])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterPill(
                                      label: '${m}m',
                                      selected: _lead == m,
                                      onTap: () => _set(_kLead, m),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile.adaptive(
                          value: _goals,
                          onChanged: (v) => _set(_kGoals, v),
                          title: const _TileTitle('Goal notifications'),
                          subtitle: const _TileSub(
                            'Score alerts while a match is on air',
                          ),
                          secondary: const _TileIcon(
                            Icons.sports_soccer_rounded,
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile.adaptive(
                          value: _pushPicks,
                          onChanged: (v) async {
                            setState(() => _prefs[_kPushPicks] = v);
                            await NoellynePushService.instance.setPicksAlerts(v);
                          },
                          title: const _TileTitle('Daily Picks push alerts'),
                          subtitle: const _TileSub(
                            'Instant phone alert when Football & NBA picks drop',
                          ),
                          secondary: const _TileIcon(Icons.campaign_rounded),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile.adaptive(
                          value: _pushResults,
                          onChanged: (v) async {
                            setState(() => _prefs[_kPushResults] = v);
                            await NoellynePushService.instance.setResultsAlerts(v);
                          },
                          title: const _TileTitle('Winning results alerts'),
                          subtitle: const _TileSub(
                            'Celebrate instantly when settled picks win',
                          ),
                          secondary: const _TileIcon(Icons.emoji_events_rounded),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile.adaptive(
                          value: _pinnedOnly,
                          onChanged: (v) => _set(_kPinnedOnly, v),
                          title: const _TileTitle('Pinned teams only'),
                          subtitle: const _TileSub(
                            'Quiet mode for everything else',
                          ),
                          secondary: const _TileIcon(Icons.push_pin_rounded),
                        ),
                      ],
                    ),
                  ),
                  const _SectionLabel('APPEARANCE'),
                  GlassCard(
                    child: Row(
                      children: [
                        const _TileIcon(Icons.palette_outlined),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TileTitle('Theme'),
                              _TileSub('System, light or dark'),
                            ],
                          ),
                        ),
                        const ThemeModeButton(),
                      ],
                    ),
                  ),
                  const _SectionLabel('APP'),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              const _TileIcon(Icons.notifications_active_rounded),
                          title: const _TileTitle('Reminders'),
                          subtitle: _TileSub(
                            'Fixtures you asked to be nudged about',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const RemindersPage(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const _TileIcon(Icons.system_update_rounded),
                          title: const _TileTitle('Check for updates'),
                          subtitle: _TileSub(
                            'Installs straight from the Noellyne release feed',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              AppUpdateService.check(context, force: true),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const _TileIcon(Icons.cleaning_services_rounded),
                          title: const _TileTitle('Clear cached data'),
                          subtitle: const _TileSub(
                            'Favorites, recent channels and cached picks',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _clearData,
                        ),
                      ],
                    ),
                  ),
                  const _SectionLabel('ABOUT'),
                  GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const _TileIcon(Icons.dns_rounded),
                          title: const _TileTitle('Stream backend'),
                          subtitle: _TileSub(NoellyneConfig.supabaseLabel),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const _TileIcon(Icons.receipt_long_rounded),
                          title: const _TileTitle('Picks & ROI database'),
                          subtitle: _TileSub(NoellyneConfig.picksSupabaseLabel),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const _TileIcon(Icons.bolt_rounded),
                          title: const _TileTitle('AI engine'),
                          subtitle: _TileSub(
                            NoellyneConfig.aiChatWebhook.trim().isEmpty
                                ? 'Offline brain (add AI_CHAT_WEBHOOK)'
                                : 'Noellyne AI live · n8n webhook',
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const _TileIcon(Icons.info_outline_rounded),
                          title: const _TileTitle('Noellyne'),
                          subtitle: _TileSub(
                            dark
                                ? 'Sports & AI · dark theme'
                                : 'Sports & AI · light theme',
                          ),
                          trailing: Text(
                            '10.0.0',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Noellyne · Altraware Technology',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = NoellyneAuthService.instance;

    return ValueListenableBuilder<NoellyneUser?>(
      valueListenable: auth.user,
      builder: (context, account, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: auth.busy,
          builder: (context, busy, _) {
            return ValueListenableBuilder<String?>(
              valueListenable: auth.lastError,
              builder: (context, err, _) {
                if (account == null) {
                  return GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const _TileIcon(Icons.verified_user_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Noellyne Account',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Sign in with Google for 10 AI chats/day (up from 3)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (err != null && err.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            err,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  auth.signInWithGoogle();
                                },
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 18),
                          label: Text(
                            busy ? 'Opening Google...' : 'Sign in with Google',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final isVip = account.isVipOwner;
                return GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isVip
                                  ? NoellyneColors.winDark
                                  : NoellyneColors.glowDeep)
                              .withValues(alpha: .16),
                        ),
                        child: Icon(
                          isVip
                              ? Icons.verified_rounded
                              : Icons.account_circle_rounded,
                          size: 24,
                          color: isVip
                              ? NoellyneColors.winDark
                              : NoellyneColors.glowDeep,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    account.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isVip
                                            ? NoellyneColors.winDark
                                            : NoellyneColors.glowDeep)
                                        .withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isVip ? 'VIP UNLIMITED' : 'MEMBER',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .5,
                                      color: isVip
                                          ? NoellyneColors.winDark
                                          : NoellyneColors.glowDeep,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              account.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          auth.signOut();
                        },
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.pinned,
    required this.onEditName,
    required this.onAddPin,
    required this.onRemovePin,
  });

  final String name;
  final List<String> pinned;
  final VoidCallback onEditName;
  final VoidCallback onAddPin;
  final ValueChanged<String> onRemovePin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.isEmpty
        ? 'NB'
        : name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [NoellyneColors.glowSoft, NoellyneColors.glowDeep],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NoellyneColors.glowDeep.withValues(alpha: .35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -.4,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Set your name' : name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pinned.isEmpty
                          ? 'Pin teams for reminders and alerts'
                          : '${pinned.length} pinned team${pinned.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEditName,
                child: Text(name.isEmpty ? 'Add' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final team in pinned)
                InputChip(
                  label: Text(team),
                  avatar: const Icon(Icons.push_pin_rounded, size: 14),
                  onDeleted: () => onRemovePin(team),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Pin team'),
                onPressed: onAddPin,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TileTitle extends StatelessWidget {
  const _TileTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      );
}

class _TileSub extends StatelessWidget {
  const _TileSub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: NoellyneColors.glowDeep.withValues(alpha: .12),
        ),
        child: Icon(icon, size: 18, color: NoellyneColors.glowDeep),
      );
}
