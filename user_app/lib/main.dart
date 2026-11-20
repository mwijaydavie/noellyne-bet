import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'noellyne_config.dart';
import 'native_player.dart';
import 'widgets/noellyne_dock_bar.dart';
import 'screens/channels_page.dart';
import 'screens/daily_picks_page.dart';
import 'screens/home_page.dart';
import 'screens/splash_screen.dart';
import 'theme_controller.dart';

/// Root navigator, so the native player can switch tabs even when the screen
/// that opened it is gone.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge so the floating dock blurs the content behind it instead of
  // sitting on a solid black system bar.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _installNativeTabRouter();
  final backendReady = _initializeBackend();
  runApp(FootballViewerApp(backendReady: backendReady));

  // Render the app before optional network/storage setup finishes.
  unawaited(_loadTheme());
  unawaited(AnalyticsService.initialize());
}

/// A tab tap inside `NativePlayerActivity` (or a suggested channel) comes back
/// over the method channel; navigate the root shell here so it works no matter
/// which screen opened the player.
void _installNativeTabRouter() {
  void go(Widget page) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => page),
      (route) => false,
    );
  }

  NativePlayer.onNavigateToTab = (index) {
    final ctx = appNavigatorKey.currentContext;
    switch (index) {
      case 0:
        go(const HomePage());
      case 1:
        go(const ChannelsPage());
      case 2:
        go(const DailyPicksPage());
      case 3:
        go(const HomePage());
        if (ctx != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final live = appNavigatorKey.currentContext ?? ctx;
            unawaited(showNoellyneMoreSheet(live));
          });
        }
      case 4:
        if (ctx != null) {
          unawaited(openAiChat(ctx));
        }
    }
  };
}

Future<void> _initializeBackend() async {
  // Supabase is optional: with no project configured the app runs on the
  // public feed + local AI fallback instead of blocking startup.
  if (!NoellyneConfig.supabaseEnabled) return;

  const directUrl = NoellyneConfig.supabaseUrl;
  const anonKey = NoellyneConfig.supabaseAnonKey;

  try {
    final url = await resolveSupabaseUrl(
      directUrl: directUrl,
      publishableKey: anonKey,
    );
    await Supabase.initialize(url: url, anonKey: anonKey);
  } catch (_) {
    // Supabase is optional for Viewer startup. Cloudflare/Vercel fallbacks
    // keep the public match list usable on restricted networks.
  }
}

Future<void> _loadTheme() async {
  try {
    await AppThemeController.instance.load();
  } catch (_) {}
}

class FootballViewerApp extends StatelessWidget {
  const FootballViewerApp({super.key, this.backendReady});

  final Future<void>? backendReady;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Noellyne Bet',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemeController.instance.mode,
          navigatorObservers: [PosthogObserver()],
          // Status bar icons must follow the theme, otherwise the clock and
          // battery vanish on the alabaster canvas.
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: (dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                  .copyWith(
                statusBarColor: Colors.transparent,
                // Edge-to-edge: the dock's glass must sample real content, so
                // never paint a solid bar behind it.
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
                systemNavigationBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashGate(
            backendReady: backendReady,
            initialMatchId: Uri.base.queryParameters['match'],
          ),
        );
      },
    );
  }
}
