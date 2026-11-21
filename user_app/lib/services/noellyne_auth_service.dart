import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../noellyne_config.dart';

/// Authenticated Noellyne Bet account backed by the dedicated Supabase Auth
/// project (`NoellyneConfig.picksSupabaseUrl` — `tahigoqhuyxedhmeqhnp`).
class NoellyneUser {
  const NoellyneUser({
    required this.id,
    required this.email,
    this.name = '',
    this.avatarUrl = '',
  });

  final String id;
  final String email;
  final String name;
  final String avatarUrl;

  /// Client-side UI hint only — actual VIP bypass is enforced cryptographically
  /// server-side on n8n after verifying the Supabase Auth JWT.
  static const _vipOwnerEmails = <String>{
    'davidbyanmwijage@gmail.com',
    'mwijaydavie@gmail.com',
    'faidahq.tz@gmail.com',
    'altrawaretechnology@gmail.com',
  };

  bool get isVipOwner => _vipOwnerEmails.contains(email.trim().toLowerCase());

  String get displayName => name.trim().isNotEmpty
      ? name.trim()
      : email.split('@').first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
      };

  factory NoellyneUser.fromJson(Map<String, dynamic> json) {
    final meta = json['user_metadata'] is Map
        ? Map<String, dynamic>.from(json['user_metadata'] as Map)
        : const <String, dynamic>{};
    return NoellyneUser(
      id: '${json['id'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      name: '${json['name'] ?? meta['full_name'] ?? meta['name'] ?? ''}'.trim(),
      avatarUrl:
          '${json['avatar_url'] ?? meta['avatar_url'] ?? meta['picture'] ?? ''}'
              .trim(),
    );
  }
}

/// Pure-PKCE Google Sign-In & JWT session manager against Noellyne's dedicated
/// Supabase project (`tahigoqhuyxedhmeqhnp`), kept cleanly separate from the
/// live-streams Supabase client.
///
/// Zero secrets are bundled in the APK: Google OAuth Client Secret lives ONLY
/// inside Supabase Auth Dashboard. Because it uses PKCE OAuth with deep-link
/// callback (`noellyne://login-callback`), it works across both debug-signed
/// preview APKs and release builds without SHA-1 signing friction.
class NoellyneAuthService {
  NoellyneAuthService._();

  static final NoellyneAuthService instance = NoellyneAuthService._();

  static const redirectUri = 'noellyne://login-callback';
  static const _linkChannel = MethodChannel('noellyne/auth_links');
  static const _sessionPrefKey = 'noellyne_auth_session_v1';
  static const _pkceVerifierKey = 'noellyne_auth_pkce_verifier_v1';
  static const _timeout = Duration(seconds: 12);

  final ValueNotifier<NoellyneUser?> user = ValueNotifier<NoellyneUser?>(null);
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _initialized = false;
  Future<String?>? _refreshInFlight;

  bool get isSignedIn => user.value != null && (_accessToken?.isNotEmpty ?? false);

  /// Loads persisted session and registers Android deep-link callback handler.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _installDeepLinkListener();
    await _restoreSession();

    // Check if the app was cold-started by an OAuth redirect URI.
    if (!kIsWeb) {
      try {
        final initial = await _linkChannel.invokeMethod<String>('getInitialAuthLink');
        if (initial != null && initial.trim().isNotEmpty) {
          await handleCallbackUri(initial.trim());
        }
      } catch (_) {
        // Non-Android platforms or unit tests without native channel.
      }
    }
  }

  void _installDeepLinkListener() {
    if (kIsWeb) return;
    _linkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAuthCallback') {
        final uri = call.arguments?.toString().trim() ?? '';
        if (uri.isNotEmpty) {
          await handleCallbackUri(uri);
        }
      }
    });
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final token = '${map['access_token'] ?? ''}'.trim();
      final refresh = '${map['refresh_token'] ?? ''}'.trim();
      final expSec = map['expires_at'] is num ? (map['expires_at'] as num).toInt() : 0;
      final userMap = map['user'] is Map
          ? Map<String, dynamic>.from(map['user'] as Map)
          : null;
      if (token.isEmpty || userMap == null) return;

      _accessToken = token;
      _refreshToken = refresh.isEmpty ? null : refresh;
      _expiresAt = expSec > 0
          ? DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true)
          : null;
      user.value = NoellyneUser.fromJson(userMap);

      // Proactively refresh if token already expired while app was closed.
      if (_isExpiringSoon && _refreshToken != null) {
        unawaited(getValidAccessToken());
      }
    } catch (error) {
      debugPrint('NoellyneAuth restore skipped: $error');
    }
  }

  bool get _isExpiringSoon {
    final exp = _expiresAt;
    if (exp == null) return false;
    return DateTime.now().toUtc().isAfter(exp.subtract(const Duration(seconds: 90)));
  }

  /// Launches Google Sign-In via Supabase Auth PKCE in the system browser.
  Future<bool> signInWithGoogle() async {
    if (!NoellyneConfig.picksSupabaseEnabled) {
      lastError.value = 'Supabase haijasanidiwa kwenye build hii.';
      return false;
    }
    busy.value = true;
    lastError.value = null;
    try {
      final verifier = _generateCodeVerifier();
      final challenge = _codeChallengeS256(verifier);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pkceVerifierKey, verifier);

      final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final authUri = Uri.parse('$base/auth/v1/authorize').replace(
        queryParameters: {
          'provider': 'google',
          'redirect_to': redirectUri,
          'code_challenge': challenge,
          'code_challenge_method': 's256',
          'access_type': 'offline',
          'prompt': 'select_account',
        },
      );

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        lastError.value = 'Imeshindwa kufungua browser kwa ajili ya Google Sign-In.';
        busy.value = false;
        return false;
      }
      // Browser opened; clear spinner after a short grace period if user cancels.
      unawaited(Future<void>.delayed(const Duration(seconds: 12), () {
        if (busy.value && !isSignedIn) {
          busy.value = false;
        }
      }));
      return true;
    } catch (error) {
      lastError.value = 'Google Sign-In error: $error';
      busy.value = false;
      return false;
    }
  }

  /// Completes sign-in after Android returns `noellyne://login-callback?...`.
  Future<bool> handleCallbackUri(String rawUri) async {
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.scheme != 'noellyne') return false;

    busy.value = true;
    lastError.value = null;
    try {
      final errDesc = uri.queryParameters['error_description'] ??
          uri.queryParameters['error'];
      if (errDesc != null && errDesc.trim().isNotEmpty) {
        lastError.value = Uri.decodeComponent(errDesc);
        return false;
      }

      // 1) PKCE flow (`?code=...`)
      final code = uri.queryParameters['code']?.trim() ?? '';
      if (code.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final verifier = prefs.getString(_pkceVerifierKey)?.trim() ?? '';
        await prefs.remove(_pkceVerifierKey);
        if (verifier.isEmpty) {
          lastError.value = 'Kipindi cha kuingia kimeisha. Jaribu tena.';
          return false;
        }
        return await _exchangePkceCode(code, verifier);
      }

      // 2) Implicit fragment fallback (`#access_token=...&refresh_token=...`)
      if (uri.fragment.isNotEmpty) {
        final frag = Uri.splitQueryString(uri.fragment);
        final access = frag['access_token']?.trim() ?? '';
        final refresh = frag['refresh_token']?.trim() ?? '';
        final expiresIn = int.tryParse(frag['expires_in'] ?? '') ?? 3600;
        if (access.isNotEmpty) {
          return await _hydrateFromTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresIn: expiresIn,
          );
        }
      }

      lastError.value = 'Hakuna auth code iliyorudishwa na Google.';
      return false;
    } catch (error) {
      debugPrint('NoellyneAuth callback failed: $error');
      lastError.value = 'Imeshindwa kukamilisha Google Sign-In. Jaribu tena.';
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> _exchangePkceCode(String code, String verifier) async {
    final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final resp = await http
        .post(
          Uri.parse('$base/auth/v1/token?grant_type=pkce'),
          headers: const {
            'apikey': NoellyneConfig.picksSupabaseAnonKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'auth_code': code,
            'code_verifier': verifier,
          }),
        )
        .timeout(_timeout);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('PKCE exchange failed HTTP ${resp.statusCode}: ${resp.body}');
      lastError.value = 'Imeshindwa kuthibitisha akaunti (${resp.statusCode}).';
      return false;
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (decoded is! Map) return false;
    return _saveAuthPayload(Map<String, dynamic>.from(decoded));
  }

  Future<bool> _hydrateFromTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final resp = await http
        .get(
          Uri.parse('$base/auth/v1/user'),
          headers: {
            'apikey': NoellyneConfig.picksSupabaseAnonKey,
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return false;
    final userDecoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (userDecoded is! Map) return false;
    return _saveAuthPayload({
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': expiresIn,
      'user': Map<String, dynamic>.from(userDecoded),
    });
  }

  Future<bool> _saveAuthPayload(Map<String, dynamic> data) async {
    final access = '${data['access_token'] ?? ''}'.trim();
    final refresh = '${data['refresh_token'] ?? ''}'.trim();
    final expiresIn = data['expires_in'] is num ? (data['expires_in'] as num).toInt() : 3600;
    final userRaw = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : null;
    if (access.isEmpty || userRaw == null) return false;

    final parsedUser = NoellyneUser.fromJson(userRaw);
    final expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));

    _accessToken = access;
    if (refresh.isNotEmpty) _refreshToken = refresh;
    _expiresAt = expiresAt;
    user.value = parsedUser;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionPrefKey,
      jsonEncode({
        'access_token': _accessToken,
        'refresh_token': _refreshToken ?? '',
        'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
        'user': parsedUser.toJson(),
      }),
    );
    // Auto-fill display name in Settings if the user hasn't set one yet.
    final existingName = prefs.getString('noellyne.profile.name')?.trim() ?? '';
    if (existingName.isEmpty && parsedUser.displayName.isNotEmpty) {
      await prefs.setString('noellyne.profile.name', parsedUser.displayName);
    }
    return true;
  }

  /// Returns a valid Supabase JWT for n8n AI Chat, transparently refreshing it
  /// if expired. Returns `null` when signed out (Guest tier).
  Future<String?> getValidAccessToken() async {
    if (!_initialized) await initialize();
    final token = _accessToken;
    if (token == null || token.isEmpty) return null;
    if (!_isExpiringSoon) return token;

    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return token;

    final pending = _refreshInFlight;
    if (pending != null) return pending;

    final op = _refreshAccessToken(refresh);
    _refreshInFlight = op;
    unawaited(op.whenComplete(() {
      if (identical(_refreshInFlight, op)) _refreshInFlight = null;
    }));
    return op;
  }

  Future<String?> _refreshAccessToken(String refreshToken) async {
    try {
      final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final resp = await http
          .post(
            Uri.parse('$base/auth/v1/token?grant_type=refresh_token'),
            headers: const {
              'apikey': NoellyneConfig.picksSupabaseAnonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(_timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
        if (decoded is Map) {
          await _saveAuthPayload(Map<String, dynamic>.from(decoded));
          return _accessToken;
        }
      } else if (resp.statusCode == 400 || resp.statusCode == 401) {
        // Refresh token revoked/expired: clear stale session cleanly.
        await signOut();
        return null;
      }
    } catch (error) {
      debugPrint('NoellyneAuth refresh skipped: $error');
    }
    return _accessToken;
  }

  Future<void> signOut() async {
    final token = _accessToken;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    user.value = null;
    lastError.value = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionPrefKey);
      await prefs.remove(_pkceVerifierKey);
    } catch (_) {}

    if (token != null && token.isNotEmpty && NoellyneConfig.picksSupabaseEnabled) {
      unawaited(() async {
        try {
          final base = NoellyneConfig.picksSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
          await http
              .post(
                Uri.parse('$base/auth/v1/logout'),
                headers: {
                  'apikey': NoellyneConfig.picksSupabaseAnonKey,
                  'Authorization': 'Bearer $token',
                },
              )
              .timeout(const Duration(seconds: 6));
        } catch (_) {}
      }());
    }
  }

  static String _generateCodeVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(48, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallengeS256(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
