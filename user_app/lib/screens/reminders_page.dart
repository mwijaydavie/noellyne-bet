import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../services/match_reminders.dart';
import 'settings_page.dart';

/// Everything the viewer asked to be nudged about, soonest first.
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(MatchReminders.instance.load());
    // Re-render the countdowns every 30s; also lets a due reminder surface.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.3),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: NoellyneBackground(
        child: AnimatedBuilder(
          animation: MatchReminders.instance,
          builder: (context, _) {
            final items = MatchReminders.instance.items
                .where((r) => !r.isPast)
                .toList(growable: false);
            if (items.isEmpty) {
              return const _EmptyReminders();
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'We nudge you ${items.first.leadMinutes} minutes before '
                      'kickoff while the app is open.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final reminder = items[index - 1];
                return _ReminderCard(
                  reminder: reminder,
                  onRemove: () =>
                      MatchReminders.instance.remove(reminder.matchId),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onRemove});

  final MatchReminder reminder;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('EEE d MMM · HH:mm').format(reminder.kickoff);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NoellyneColors.glowDeep.withValues(alpha: .14),
            ),
            child: const Icon(Icons.notifications_active_rounded,
                size: 19, color: NoellyneColors.glowDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reminder.league.isEmpty ? time : '${reminder.league} · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            reminder.countdown,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: NoellyneColors.glowDeep,
            ),
          ),
          IconButton(
            tooltip: 'Remove reminder',
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 24),
      child: Column(
        children: [
          Icon(Icons.alarm_off_rounded,
              size: 40, color: NoellyneColors.glowDeep.withValues(alpha: .8)),
          const SizedBox(height: 12),
          Text(
            'No reminders yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Open a fixture and tap the bell — a 22:30 kickoff will nudge you '
            'at 22:15 so you never miss it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
