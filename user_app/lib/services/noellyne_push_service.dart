import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/daily_picks_page.dart';

/// Top-level background FCM handler required by `firebase_messaging`.
@pragma('vm:entry-point')
Future<void> noellyneFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

/// Manages Firebase Cloud Messaging (FCM) topic subscriptions for Noellyne Bet:
///   - `noellyne_picks`: 07:30 / 09:00 / 14:00 / 19:00 EAT Daily Picks alerts
///   - `noellyne_results`: instant alerts when settled picks WIN
///
/// Uses FCM Topics so n8n broadcasts to 10 or 100,000 phones with a single HTTP
/// call and zero device-token table overhead. Gracefully no-ops on Web, iOS
/// simulator builds without GoogleService-Info.plist, or unit tests.
class NoellynePushService {
  NoellynePushService._();

  static final NoellynePushService instance = NoellynePushService._();

  static const topicPicks = 'noellyne_picks';
  static const topicResults = 'noellyne_results';
  static const prefPicksKey = 'noellyne.alerts.pushPicks';
  static const prefResultsKey = 'noellyne.alerts.pushResults';

  bool _initialized = false;
  bool _available = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  bool get isAvailable => _available;

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(noellyneFirebaseBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      _available = true;

      // Sync topic subscriptions with user Settings toggles.
      final prefs = await SharedPreferences.getInstance();
      final picksOn = prefs.getBool(prefPicksKey) ?? true;
      final resultsOn = prefs.getBool(prefResultsKey) ?? true;
      await _applyTopic(topicPicks, picksOn);
      await _applyTopic(topicResults, resultsOn);

      // Foreground notification presentation.
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Notification tap while app is in background.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Notification tap that launched the app from terminated state.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(initial);
        });
      }
    } catch (error) {
      debugPrint('NoellynePushService skipped: $error');
    }
  }

  Future<void> setPicksAlerts(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefPicksKey, enabled);
    await _applyTopic(topicPicks, enabled);
  }

  Future<void> setResultsAlerts(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefResultsKey, enabled);
    await _applyTopic(topicResults, enabled);
  }

  Future<void> _applyTopic(String topic, bool subscribe) async {
    if (!_available) return;
    try {
      if (subscribe) {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      }
    } catch (error) {
      debugPrint('FCM topic $topic update failed: $error');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final ctx = _navigatorKey?.currentContext;
    final title = message.notification?.title?.trim() ?? '';
    final body = message.notification?.body?.trim() ?? '';
    if (ctx == null || (title.isEmpty && body.isEmpty)) return;

    final text = title.isNotEmpty && body.isNotEmpty
        ? '$title\n$body'
        : (title.isNotEmpty ? title : body);
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openPicks(),
          ),
        ),
      );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route = (message.data['route'] ?? '').toString().toLowerCase();
    if (route == 'picks' || route == 'results' || route.isEmpty) {
      _openPicks();
    }
  }

  void _openPicks() {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const DailyPicksPage()),
    );
  }
}
