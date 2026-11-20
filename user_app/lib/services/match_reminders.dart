import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A locally stored "remind me" for one fixture.
class MatchReminder {
  MatchReminder({
    required this.matchId,
    required this.title,
    required this.kickoff,
    this.league = '',
    this.leadMinutes = 15,
  });

  final String matchId;
  final String title;
  final String league;
  final DateTime kickoff;
  final int leadMinutes;

  DateTime get notifyAt => kickoff.subtract(Duration(minutes: leadMinutes));

  bool get isPast => DateTime.now().isAfter(kickoff.add(const Duration(hours: 4)));

  String get countdown {
    final delta = kickoff.difference(DateTime.now());
    if (delta.isNegative) return 'Started';
    if (delta.inMinutes < 60) return 'in ${delta.inMinutes}m';
    if (delta.inHours < 24) {
      final m = delta.inMinutes % 60;
      return 'in ${delta.inHours}h${m == 0 ? '' : ' ${m}m'}';
    }
    return 'in ${delta.inDays}d';
  }

  Map<String, dynamic> toJson() => {
        'id': matchId,
        'title': title,
        'league': league,
        'kickoff': kickoff.toIso8601String(),
        'lead': leadMinutes,
      };

  static MatchReminder? fromJson(Map<String, dynamic> json) {
    final kickoff = DateTime.tryParse(json['kickoff']?.toString() ?? '');
    final id = json['id']?.toString() ?? '';
    if (kickoff == null || id.isEmpty) return null;
    return MatchReminder(
      matchId: id,
      title: json['title']?.toString() ?? 'Match',
      league: json['league']?.toString() ?? '',
      kickoff: kickoff,
      leadMinutes: (json['lead'] as num?)?.toInt() ?? 15,
    );
  }
}

/// Device-local reminder store.
///
/// Deliberately offline-first: reminders live in `SharedPreferences` so they
/// work with or without Supabase, and the app can act on them the moment it is
/// opened. A due reminder fires once and is then marked as delivered.
class MatchReminders extends ChangeNotifier {
  MatchReminders._();

  static final MatchReminders instance = MatchReminders._();

  static const _key = 'noellyne.reminders.v1';
  static const _firedKey = 'noellyne.reminders.fired.v1';

  final List<MatchReminder> _items = [];
  final Set<String> _fired = {};
  Future<void>? _loading;

  List<MatchReminder> get items => List.unmodifiable(_items);

  Future<void> load() => _loading ??= _load();

  /// Lead time configured in Settings (15 / 30 / 60 minutes).
  static Future<int> leadMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('noellyne.alerts.lead') ?? 15;
    } catch (_) {
      return 15;
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final raw in prefs.getStringList(_key) ?? const <String>[]) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final reminder =
                MatchReminder.fromJson(decoded.cast<String, dynamic>());
            if (reminder != null) _items.add(reminder);
          }
        } catch (_) {
          // Skip a single corrupt entry, never the whole list.
        }
      }
      _fired.addAll(prefs.getStringList(_firedKey) ?? const <String>[]);
      _items.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      notifyListeners();
    } catch (error) {
      debugPrint('reminders unavailable: $error');
      _loading = null;
    }
  }

  bool isReminded(String matchId) =>
      _items.any((r) => r.matchId == matchId);

  Future<void> toggle(MatchReminder reminder) async {
    await load();
    if (isReminded(reminder.matchId)) {
      _items.removeWhere((r) => r.matchId == reminder.matchId);
    } else {
      _items.add(reminder);
    }
    _items.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    await _persist();
  }

  Future<void> remove(String matchId) async {
    await load();
    _items.removeWhere((r) => r.matchId == matchId);
    await _persist();
  }

  /// Reminders whose window has opened and that have not fired yet.
  List<MatchReminder> takeDue() {
    final now = DateTime.now();
    final due = <MatchReminder>[];
    for (final reminder in _items) {
      if (_fired.contains(reminder.matchId)) continue;
      if (reminder.isPast) continue;
      if (now.isAfter(reminder.notifyAt)) {
        due.add(reminder);
        _fired.add(reminder.matchId);
      }
    }
    if (due.isNotEmpty) _persist();
    return due;
  }

  Future<void> _persist() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        _items.map((r) => jsonEncode(r.toJson())).toList(),
      );
      await prefs.setStringList(_firedKey, _fired.toList());
    } catch (error) {
      debugPrint('reminders persist failed: $error');
    }
  }
}
