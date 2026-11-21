import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../noellyne_config.dart';

/// One chat turn.
class AiMessage {
  AiMessage(this.text, {required this.fromUser, this.pending = false});

  final String text;
  final bool fromUser;
  bool pending;
}

/// Talks to the Noellyne n8n brain (`ai_chat_webhook`).
///
/// The webhook URL is resolved dynamically from Supabase `public.app_config`
/// once per session (falling back to [NoellyneConfig.aiChatWebhook]) so backend
/// VPS migrations require zero APK rebuild.
///
/// The n8n side carries the provider fallback chain (Groq -> Gemini ->
/// OpenRouter), rate limiting, and verified VIP owner bypass. If the webhook is
/// unreachable, this service answers from [_offline] so the chat is **never**
/// dead — it still understands football, NBA, and the BetPawa stake split.
class NoellyneAiService {
  const NoellyneAiService();

  static const _timeout = Duration(seconds: 30);
  static const _configTimeout = Duration(seconds: 5);
  static const _deviceIdPrefKey = 'noellyne_ai_device_id';

  static String? _cachedWebhook;
  static bool _configChecked = false;
  static String? _cachedDeviceId;

  bool get isConfigured =>
      (_cachedWebhook ?? NoellyneConfig.aiChatWebhook).trim().isNotEmpty;

  /// Resolves the live AI Chat webhook from Supabase `public.app_config`
  /// once per app session, falling back cleanly to the compile-time default.
  Future<String> _resolveWebhook() async {
    if (_configChecked) {
      return (_cachedWebhook ?? NoellyneConfig.aiChatWebhook).trim();
    }
    _configChecked = true;
    final fallback = NoellyneConfig.aiChatWebhook.trim();

    if (!NoellyneConfig.picksSupabaseEnabled) {
      _cachedWebhook = fallback;
      return fallback;
    }

    try {
      final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
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
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          final remote = (decoded.first['value'] ?? '').toString().trim();
          if (remote.startsWith('https://')) {
            _cachedWebhook = remote;
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

  /// Generates & persists an anonymous per-device identifier so rate limits
  /// isolate individual phones cleanly even behind mobile carrier CGNAT IPs.
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
      final generated = 'nly-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_deviceIdPrefKey, generated);
      _cachedDeviceId = generated;
      return generated;
    } catch (_) {
      return 'nly-ephemeral';
    }
  }

  Future<String> send(
    List<AiMessage> history, {
    Map<String, dynamic>? matchContext,
    String? authToken,
  }) async {
    final lastUser = history.lastWhere(
      (m) => m.fromUser,
      orElse: () => AiMessage('', fromUser: true),
    );
    final question = lastUser.text.trim();
    if (question.isEmpty) return _offline('');

    final webhookUrl = await _resolveWebhook();
    if (webhookUrl.isEmpty) return _offline(question);

    try {
      final deviceId = await _getDeviceId();
      final payload = <String, dynamic>{
        'message': question,
        'chatId': deviceId,
        'deviceId': deviceId,
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
      };
      final token = authToken?.trim() ?? '';
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
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
        final reply = _extract(bodyText);
        if (reply != null && reply.isNotEmpty) return reply;
      } else if (response.statusCode == 429) {
        // Surface the friendly Kiswahili rate-limit message from n8n directly.
        final limitMsg = _extract(bodyText);
        if (limitMsg != null && limitMsg.isNotEmpty) return limitMsg;
        return 'Umefikia kikomo cha maswali ya AI kwa saa hii. '
            'Jaribu tena baada ya muda mfupi au ingia na akaunti yako.';
      }
      debugPrint('AI webhook ${response.statusCode}; using offline brain');
    } catch (error) {
      debugPrint('AI webhook failed: $error');
    }
    return _offline(question);
  }

  /// Accepts `{reply}`, `{text}`, `{output}`, `{message}` or an n8n array.
  String? _extract(String body) {
    try {
      final decoded = jsonDecode(body);
      final map = decoded is List
          ? (decoded.isNotEmpty && decoded.first is Map
              ? Map<String, dynamic>.from(decoded.first as Map)
              : null)
          : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);
      if (map == null) return null;
      for (final key in ['reply', 'text', 'output', 'message', 'answer']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    } catch (_) {
      // Plain-text webhook response.
      final trimmed = body.trim();
      return trimmed.isEmpty ? null : trimmed;
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

    if (q.contains('football') || q.contains('mechi') ||
        q.contains('leo') || q.contains('picks')) {
      return 'Football Leo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          '1. Chagua STRONG tier pekee (Conf >= 63%, Edge >= 2.5%).\n'
          '2. Safest markets: DC 1X / DC X2 na OVER 1.5-2.5.\n'
          '3. Weka 2-3u kwa STRONG, 1-1.5u kwa MODERATE.\n\n'
          'Picks za leo ziko kwenye tab ya Picks — '
          'bonyeza "Watch Live" kufungua mechi.';
    }

    if (q.contains('matokeo') || q.contains('results') || q.contains('rekodi')) {
      return 'Matokeo & ROI\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Rekodi halisi huletwa moja kwa moja kutoka Supabase ya Noellyne Bet. '
          'Fungua tab ya Picks kisha bonyeza Results kuona W/L na faida.';
    }

    return 'Noellyne AI\n'
        '━━━━━━━━━━━━━━━━━━\n'
        'Niko hapa kukusaidia: football, NBA, mgao wa mtaji, '
        'na uchambuzi wa mechi.\n\n'
        'Jaribu:\n'
        '• "Nina 20,000 leo"\n'
        '• "Picks za football leo"\n'
        '• "NBA injury guard"';
  }

  /// Suggested first questions shown as chips.
  static const quickPrompts = <String>[
    'Picks za leo',
    'Matokeo ya jana vipi?',
    'Nina 20,000 leo',
    'NBA injury guard',
  ];
}
