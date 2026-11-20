import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../noellyne_config.dart';

/// One chat turn.
class AiMessage {
  AiMessage(this.text, {required this.fromUser, this.pending = false});

  final String text;
  final bool fromUser;
  bool pending;
}

/// Talks to the Noellyne n8n brain (`AI_CHAT_WEBHOOK`).
///
/// The n8n side already carries the provider fallback chain (Groq → Gemini →
/// OpenRouter). If that webhook is missing or every provider fails, this
/// service answers from [_offline] so the chat is **never** dead — it still
/// understands football, NBA and the BetPawa stake split.
class NoellyneAiService {
  const NoellyneAiService();

  static const _timeout = Duration(seconds: 30);

  bool get isConfigured => NoellyneConfig.aiChatWebhook.trim().isNotEmpty;

  Future<String> send(List<AiMessage> history) async {
    final lastUser = history.lastWhere(
      (m) => m.fromUser,
      orElse: () => AiMessage('', fromUser: true),
    );
    final question = lastUser.text.trim();
    if (question.isEmpty) return _offline('');

    if (!isConfigured) return _offline(question);

    try {
      final response = await http
          .post(
            Uri.parse(NoellyneConfig.aiChatWebhook),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': question,
              'chatId': 'app',
              'source': 'noellyne-app',
              'history': history
                  .where((m) => !m.pending)
                  .map((m) => {
                        'role': m.fromUser ? 'user' : 'assistant',
                        'content': m.text,
                      })
                  .toList(),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final reply = _extract(utf8.decode(response.bodyBytes, allowMalformed: true));
        if (reply != null && reply.isNotEmpty) return reply;
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
      return '⚡ MGAWO WA MTaji — TZS ${_tzs(total)}\n'
          '━━━━━━━━━━━━━━━━━━\n'
          '🎫 Ticket 1 (40%) — Single ⚽ anchor\n'
          '   Weka TZS ${_tzs(a)} → malipo ≈ TZS ${_tzs((a * 1.85).round())}\n\n'
          '🎫 Ticket 2 (40%) — Single 🏀 anchor\n'
          '   Weka TZS ${_tzs(b)} → malipo ≈ TZS ${_tzs((b * 1.72).round())}\n\n'
          '🎫 Ticket 3 (20%) — Double ⚽ × 🏀\n'
          '   Weka TZS ${_tzs(c)} → malipo ≈ TZS ${_tzs((c * 3.18).round())}\n'
          '━━━━━━━━━━━━━━━━━━\n'
          '🔒 Ulinzi: single moja ikiteleza, nyingine inakurudishia mtaji.\n'
          'Andika kiasi kingine, mfano "Nina 25,000 leo".';
    }

    if (q.contains('nba') || q.contains('basket')) {
      return '🏀 NBA Leo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Nakagua Injury Guard kwanza: nyota yeyote aliye OUT '
          'hushusha tier kutoka 🟢 STRONG hadi 🟡 MODERATE.\n\n'
          '• Moneyline ndio salama zaidi kwenye NBA\n'
          '• Spread -5.5 = ishinde kwa pointi 6+\n'
          '• Totals: angalia PPG na FG% kabla ya OVER/UNDER\n\n'
          'Picks kamili ziko kwenye tab ya ✨ Picks.';
    }

    if (q.contains('football') || q.contains('mechi') ||
        q.contains('leo') || q.contains('picks')) {
      return '⚽ Football Leo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          '1. Chagua 🟢 STRONG tier pekee (Conf ≥ 63%, Edge ≥ 2.5%).\n'
          '2. Safest markets: DC 1X / DC X2 na OVER 1.5-2.5.\n'
          '3. Weka 2–3u kwa STRONG, 1–1.5u kwa MODERATE.\n\n'
          'Picks za leo ziko kwenye tab ya ✨ Picks — '
          'bonyeza "Watch Live" kufungua mechi.';
    }

    if (q.contains('matokeo') || q.contains('results') || q.contains('rekodi')) {
      return '📊 Matokeo\n'
          '━━━━━━━━━━━━━━━━━━\n'
          'Rekodi halisi huletwa kutoka Google Sheet ya Hermes. '
          'Ili kuunganisha: weka n8n webhook kwenye build '
          '(--dart-define=AI_CHAT_WEBHOOK=...) halafu tumia node '
          '"Read Sheet for Chat".';
    }

    return '🦅 Noellyne AI\n'
        '━━━━━━━━━━━━━━━━━━\n'
        'Niko hapa kukusaidia: football, NBA, mgao wa mtaji, '
        'na uchambuzi wa mechi.\n\n'
        'Jaribu:\n'
        '• "Nina 20,000 leo"\n'
        '• "Picks za football leo"\n'
        '• "NBA injury guard"\n\n'
        'AI ya live itawezeshwa ukiunganisha n8n webhook.';
  }

  /// Suggested first questions shown as chips.
  static const quickPrompts = <String>[
    'Picks za leo',
    'Nina 20,000 leo',
    'NBA injury guard',
    'Jinsi ya kuweka',
  ];
}
