import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../noellyne_config.dart';
import 'noellyne_auth_service.dart';

/// Interactive action button returned alongside a Noellyne AI response.
class AiAction {
  const AiAction({
    required this.type,
    required this.label,
    this.url,
    this.text,
    this.streamId,
  });

  /// `open_picks` | `open_results` | `open_watch` | `sign_in` | `open_url` | `copy_text`
  final String type;
  final String label;
  final String? url;
  final String? text;
  final String? streamId;

  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
        type: '${json['type'] ?? ''}'.trim(),
        label: '${json['label'] ?? ''}'.trim(),
        url: json['url']?.toString().trim(),
        text: json['text']?.toString(),
        streamId: json['streamId']?.toString().trim(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        if (url != null) 'url': url,
        if (text != null) 'text': text,
        if (streamId != null) 'streamId': streamId,
      };
}

/// Server-enforced daily quota metadata returned by the AI Chat API.
class AiQuota {
  const AiQuota({
    required this.tier,
    required this.plan,
    required this.used,
    required this.limit,
    required this.remaining,
    required this.unlimited,
  });

  final String tier;
  final String plan;
  final int used;
  final int limit;
  final int remaining;
  final bool unlimited;

  factory AiQuota.fromJson(Map<String, dynamic> json) {
    final lim = json['limit'] is num ? (json['limit'] as num).toInt() : 3;
    final rem = json['remaining'] is num ? (json['remaining'] as num).toInt() : 0;
    final used = json['used'] is num ? (json['used'] as num).toInt() : 0;
    final unlim = json['unlimited'] == true || lim < 0;
    return AiQuota(
      tier: '${json['tier'] ?? 'guest'}'.trim(),
      plan: '${json['plan'] ?? 'guest'}'.trim(),
      used: used,
      limit: lim,
      remaining: unlim ? -1 : rem,
      unlimited: unlim,
    );
  }
}

/// Structured AI response containing text, clickable in-app actions, and quota.
class AiReply {
  const AiReply({
    required this.text,
    this.actions = const [],
    this.quota,
    this.quotaReached = false,
  });

  final String text;
  final List<AiAction> actions;
  final AiQuota? quota;
  final bool quotaReached;
}

/// One chat turn.
class AiMessage {
  AiMessage(
    this.text, {
    required this.fromUser,
    this.pending = false,
    this.actions = const [],
  });

  final String text;
  final bool fromUser;
  bool pending;
  final List<AiAction> actions;

  Map<String, dynamic> toJson() => {
        'text': text,
        'fromUser': fromUser,
        'actions': actions.map((a) => a.toJson()).toList(growable: false),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    final rawActs = json['actions'];
    final acts = rawActs is List
        ? rawActs
            .whereType<Map>()
            .map((a) => AiAction.fromJson(Map<String, dynamic>.from(a)))
            .where((a) => a.type.isNotEmpty && a.label.isNotEmpty)
            .toList(growable: false)
        : const <AiAction>[];
    return AiMessage(
      '${json['text'] ?? ''}',
      fromUser: json['fromUser'] == true,
      actions: acts,
    );
  }
}

/// Talks to the Noellyne n8n brain (`ai_chat_webhook`).
///
/// Features:
///   - Remote webhook URL cached on disk for 6h via Supabase `public.app_config`
///     (zero APK rebuild when migrating VPS servers).
///   - Hardware-stable Android SHA-256 fingerprint (`hwId`) via `MainActivity`
///     so daily guest/member limits survive Clear Cache, Clear Data & Reinstall.
///   - Automatic Supabase JWT forwarding for Google Members (10/day), future
///     Pro subscribers, and VIP Owner Unlimited access.
///   - Interactive in-app action buttons (`actions`) returned with AI replies.
class NoellyneAiService {
  const NoellyneAiService();

  static const _timeout = Duration(seconds: 30);
  static const _configTimeout = Duration(seconds: 5);
  static const _deviceIdPrefKey = 'noellyne_ai_device_id';
  static const _chatHistoryPrefKey = 'noellyne_ai_chat_history_v1';
  static const _maxPersistedTurns = 40;
  static const _webhookCachePrefKey = 'noellyne_ai_webhook_url_v1';
  static const _webhookCacheTsKey = 'noellyne_ai_webhook_ts_v1';
  static const _webhookCacheTtl = Duration(hours: 6);
  static const _nativeChannel = MethodChannel('noellyne/auth_links');

  /// Latest server-reported quota for live display in the AI Chat AppBar.
  static final ValueNotifier<AiQuota?> quota = ValueNotifier<AiQuota?>(null);

  static String? _cachedWebhook;
  static bool _configChecked = false;
  static String? _cachedDeviceId;
  static String? _cachedHwId;
  static bool _hwChecked = false;

  bool get isConfigured =>
      (_cachedWebhook ?? NoellyneConfig.aiChatWebhook).trim().isNotEmpty;

  Future<String> _resolveWebhook() async {
    if (_configChecked) {
      return (_cachedWebhook ?? NoellyneConfig.aiChatWebhook).trim();
    }
    _configChecked = true;
    final fallback = NoellyneConfig.aiChatWebhook.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_webhookCachePrefKey)?.trim() ?? '';
      final savedTs = prefs.getInt(_webhookCacheTsKey) ?? 0;
      if (savedUrl.startsWith('https://') && savedTs > 0) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(savedTs),
        );
        if (age >= Duration.zero && age < _webhookCacheTtl) {
          _cachedWebhook = savedUrl;
          return savedUrl;
        }
      }
    } catch (_) {}

    if (!NoellyneConfig.picksSupabaseEnabled) {
      _cachedWebhook = fallback;
      return fallback;
    }

    try {
      final base = NoellyneConfig.picksSupabaseUrl
          .trim()
          .replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        '$base/rest/v1/app_config?key=eq.ai_chat_webhook&select=value&limit=1',
      );
      final resp = await http.get(
        uri,
        headers: {
          'apikey': NoellyneConfig.picksSupabaseAnonKey,
          'Authorization': 'Bearer ${NoellyneConfig.picksSupabaseAnonKey}',
        },
      ).timeout(_configTimeout);

      if (resp.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          final remote = (decoded.first['value'] ?? '').toString().trim();
          if (remote.startsWith('https://')) {
            _cachedWebhook = remote;
            unawaited(_persistWebhook(remote));
            return remote;
          }
        }
      }
    } catch (error) {
      debugPrint('Remote app_config lookup skipped: $error');
    }

    _cachedWebhook = fallback;
    return fallback;
  }

  Future<void> _persistWebhook(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webhookCachePrefKey, url);
      await prefs.setInt(
        _webhookCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Hardware-stable Android SHA-256 fingerprint (survives Clear Cache/Data).
  Future<String> _getHardwareFingerprint() async {
    if (_hwChecked) return _cachedHwId ?? '';
    _hwChecked = true;
    if (kIsWeb) return '';
    try {
      final hw = await _nativeChannel.invokeMethod<String>('getDeviceFingerprint');
      _cachedHwId = hw?.trim() ?? '';
      return _cachedHwId!;
    } catch (_) {
      return '';
    }
  }

  /// Fallback anonymous per-install ID for non-Android platforms.
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_deviceIdPrefKey);
      if (existing != null && existing.trim().isNotEmpty) {
        _cachedDeviceId = existing.trim();
        return _cachedDeviceId!;
      }
      final rng = Random.secure();
      final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
      final generated =
          'nly-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_deviceIdPrefKey, generated);
      _cachedDeviceId = generated;
      return generated;
    } catch (_) {
      return 'nly-ephemeral';
    }
  }

  /// Loads persisted local chat history from device storage.
  Future<List<AiMessage>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chatHistoryPrefKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => AiMessage.fromJson(Map<String, dynamic>.from(m)))
          .where((m) => m.text.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Persists the most recent chat turns locally so conversations survive navigation & restarts.
  Future<void> saveHistory(List<AiMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = messages.where((m) => !m.pending && m.text.trim().isNotEmpty).toList();
      final trimmed = clean.length > _maxPersistedTurns
          ? clean.sublist(clean.length - _maxPersistedTurns)
          : clean;
      await prefs.setString(
        _chatHistoryPrefKey,
        jsonEncode(trimmed.map((m) => m.toJson()).toList(growable: false)),
      );
    } catch (_) {}
  }

  /// Clears saved chat history for starting a fresh thread.
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chatHistoryPrefKey);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('noellyne.profile.name')?.trim() ?? '';
      final pinned = prefs.getStringList('noellyne.profile.pinned') ?? const <String>[];
      return <String, dynamic>{
        if (name.isNotEmpty) 'name': name,
        if (pinned.isNotEmpty) 'pinnedTeams': pinned,
      };
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// Backward-compatible text-only helper.
  Future<String> send(
    List<AiMessage> history, {
    Map<String, dynamic>? matchContext,
    String? authToken,
  }) async {
    final structured = await sendStructured(
      history,
      matchContext: matchContext,
      authToken: authToken,
    );
    return structured.text;
  }

  /// Sends chat turn and returns reply text + interactive actions + live quota.
  Future<AiReply> sendStructured(
    List<AiMessage> history, {
    Map<String, dynamic>? matchContext,
    String? authToken,
  }) async {
    final lastUser = history.lastWhere(
      (m) => m.fromUser,
      orElse: () => AiMessage('', fromUser: true),
    );
    final question = lastUser.text.trim();
    if (question.isEmpty) return AiReply(text: _offline(''));

    final webhookUrl = await _resolveWebhook();
    if (webhookUrl.isEmpty) return AiReply(text: _offline(question));

    try {
      final results = await Future.wait<String>([
        _getHardwareFingerprint(),
        _getDeviceId(),
      ]);
      final hwId = results[0];
      final deviceId = results[1];
      final userProfile = await _loadUserProfile();
      final resolvedToken = (authToken?.trim().isNotEmpty ?? false)
          ? authToken!.trim()
          : (await NoellyneAuthService.instance.getValidAccessToken() ?? '');

      final payload = <String, dynamic>{
        'message': question,
        'chatId': hwId.isNotEmpty ? hwId : deviceId,
        'deviceId': deviceId,
        if (hwId.isNotEmpty) 'hwId': hwId,
        if (userProfile.isNotEmpty) 'userProfile': userProfile,
        'source': 'noellyne-app',
        'history': history
            .where((m) => !m.pending)
            .map((m) => {
                  'role': m.fromUser ? 'user' : 'assistant',
                  'content': m.text,
                })
            .toList(),
      };
      if (matchContext != null && matchContext.isNotEmpty) {
        payload['matchContext'] = matchContext;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Device-Id': deviceId,
        if (hwId.isNotEmpty) 'X-Device-Hardware-Id': hwId,
      };
      if (resolvedToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $resolvedToken';
      }

      final response = await http
          .post(
            Uri.parse(webhookUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = _extractStructured(bodyText);
        if (parsed != null && parsed.text.isNotEmpty) {
          if (parsed.quota != null) {
            quota.value = parsed.quota;
          }
          return parsed;
        }
      } else if (response.statusCode == 429) {
        final parsed = _extractStructured(bodyText);
        if (parsed != null && parsed.text.isNotEmpty) {
          if (parsed.quota != null) quota.value = parsed.quota;
          return parsed;
        }
        return const AiReply(
          text: 'Umefikia kikomo cha maswali ya AI kwa leo. '
              'Ingia na Google kwenye Settings upate maswali 10 kila siku.',
          quotaReached: true,
          actions: [
            AiAction(type: 'sign_in', label: 'Ingia na Google (10/siku)'),
          ],
        );
      }
      debugPrint('AI webhook ${response.statusCode}; using offline brain');
    } catch (error) {
      debugPrint('AI webhook failed: $error');
    }
    return AiReply(text: _offline(question));
  }

  AiReply? _extractStructured(String body) {
    try {
      final decoded = jsonDecode(body);
      final map = decoded is List
          ? (decoded.isNotEmpty && decoded.first is Map
              ? Map<String, dynamic>.from(decoded.first as Map)
              : null)
          : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);
      if (map == null) return null;

      String text = '';
      for (final key in ['reply', 'text', 'output', 'message', 'answer']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) {
          text = value.trim();
          break;
        }
      }
      if (text.isEmpty) return null;

      final rawActions = map['actions'];
      final actions = rawActions is List
          ? rawActions
              .whereType<Map>()
              .map((a) => AiAction.fromJson(Map<String, dynamic>.from(a)))
              .where((a) => a.type.isNotEmpty && a.label.isNotEmpty)
              .toList(growable: false)
          : const <AiAction>[];

      AiQuota? parsedQuota;
      if (map['rateLimit'] is Map) {
        parsedQuota = AiQuota.fromJson(
          Map<String, dynamic>.from(map['rateLimit'] as Map),
        );
      }

      return AiReply(
        text: text,
        actions: actions,
        quota: parsedQuota,
        quotaReached: map['quotaReached'] == true,
      );
    } catch (_) {
      final trimmed = body.trim();
      return trimmed.isEmpty ? null : AiReply(text: trimmed);
    }
  }

  int? _amount(String q) {
    final k = RegExp(r'(\d+(?:\.\d+)?)\s*k\b').firstMatch(q);
    if (k != null) {
      final v = (double.tryParse(k.group(1)!) ?? 0) * 1000;
      if (v >= 500 && v <= 50000000) return v.round();
    }
    final num = RegExp(r'\b\d{1,3}(?:,\d{3})+\b|\b\d{3,8}\b').allMatches(q);
    for (final m in num) {
      final v = int.tryParse(m.group(0)!.replaceAll(',', ''));
      if (v != null && v >= 500 && v <= 50000000) return v;
    }
    return null;
  }

  String _tzs(int amount) {
    final s = amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  /// Built-in Hermes-style assistant (Kiswahili), used when n8n is offline.
  String _offline(String question) {
    final q = question.toLowerCase();
    final amount = _amount(q);

    if (amount != null ||
        q.contains('mtaji') ||
        q.contains('bankroll') ||
        q.contains('slip') ||
        q.contains('gawa')) {
      final total = amount ?? 10000;
      final a = (total * .40).round();
      final b = (total * .40).round();
      final c = total - a - b;
      return 'MGAWO WA MTAJI — TZS ${_tzs(total)}\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Ticket 1 (40%) — Single Football Anchor\n'
          '   Weka TZS ${_tzs(a)} -> malipo ~ TZS ${_tzs((a * 1.85).round())}\n\n'
          'Ticket 2 (40%) — Single NBA Anchor\n'
          '   Weka TZS ${_tzs(b)} -> malipo ~ TZS ${_tzs((b * 1.72).round())}\n\n'
          'Ticket 3 (20%) — Double Football x NBA\n'
          '   Weka TZS ${_tzs(c)} -> malipo ~ TZS ${_tzs((c * 3.18).round())}\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Ulinzi: single moja ikiteleza, nyingine inakurudishia mtaji.\n'
          'Andika kiasi kingine, mfano "Nina 25,000 leo".';
    }

    if (q.contains('altraware') || q.contains('mwijay')) {
      return 'Altraware Technology Ltd\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Noellyne imeundwa na Altraware Technology Ltd (Dar es Salaam, Tanzania) — '
          'ikiongozwa na David Erick Mwijage (Mwijay Davie) na Clemence W. N\'gunda.\n\n'
          'Bidhaa nyingine: Faida POS, CareTrack, TanzaniaReach, Quickopia na Altraware Motion Lab.\n'
          'Tovuti: https://altra.tanzaniareach.com/';
    }

    if (q.contains('nba') || q.contains('basket')) {
      return 'NBA Leo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Nakagua Injury Guard kwanza: nyota yeyote aliye OUT '
          'hushusha tier kutoka STRONG hadi MODERATE.\n\n'
          '• Moneyline ndio salama zaidi kwenye NBA\n'
          '• Spread -5.5 = ishinde kwa pointi 6+\n'
          '• Totals: angalia PPG na FG% kabla ya OVER/UNDER\n\n'
          'Picks kamili ziko kwenye tab ya Picks.';
    }

    if (q.contains('football') ||
        q.contains('mechi') ||
        q.contains('leo') ||
        q.contains('picks')) {
      return 'Football Leo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          '1. Chagua STRONG tier pekee (Conf >= 63%, Edge >= 2.5%).\n'
          '2. Safest markets: DC 1X / DC X2 na OVER 1.5-2.5.\n'
          '3. Weka 2-3u kwa STRONG, 1-1.5u kwa MODERATE.\n\n'
          'Picks za leo ziko kwenye tab ya Picks — '
          'bonyeza "Watch Live" kufungua mechi.';
    }

    if (q.contains('matokeo') ||
        q.contains('results') ||
        q.contains('rekodi')) {
      return 'Matokeo & ROI\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Rekodi halisi huletwa moja kwa moja kutoka Supabase ya Noellyne. '
          'Fungua tab ya Picks kisha bonyeza Results kuona W/L na faida.';
    }

    return 'Noellyne AI\n'
        '━━━━━━━━━━━━━━━━━━\n'
        'Niko hapa kukusaidia: football, NBA, mgao wa mtaji, '
        'uchambuzi wa mechi, na taarifa za Altraware Technology.\n\n'
        'Jaribu:\n'
        '• "Nina 20,000 leo"\n'
        '• "Picks za leo"\n'
        '• "Altraware Technology ni nini?"';
  }

  /// Suggested first questions shown as chips.
  static const quickPrompts = <String>[
    'Picks za leo',
    'Matokeo ya jana vipi?',
    'Nina 20,000 leo',
    'Altraware Technology ni nini?',
  ];
}
