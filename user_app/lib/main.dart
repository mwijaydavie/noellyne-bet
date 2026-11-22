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
import 'screens/welcome_page.dart';
import 'services/daily_picks_repository.dart';
import 'services/noellyne_auth_service.dart';
import 'services/noellyne_push_service.dart';
import 'widgets/root_back_guard.dart';
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
  unawaited(NoellyneAuthService.instance.initialize());
  unawaited(NoellynePushService.instance.initialize(appNavigatorKey));
  unawaited(const DailyPicksRepository().loadCachedBoard());
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
        go(const RootBackGuard(isHome: true, child: HomePage()));
      case 1:
        go(const RootBackGuard(child: ChannelsPage()));
      case 2:
        go(const RootBackGuard(child: DailyPicksPage()));
      case 3:
        go(const RootBackGuard(isHome: true, child: HomePage()));
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
              child: _OverlaySync(dark: dark, child: child ?? const SizedBox.shrink()),
            );
          },
          home: RootBackGuard(
            isHome: true,
            child: _FirstRunGate(
              backendReady: backendReady,
              initialMatchId: Uri.base.queryParameters['match'],
            ),
          ),
        );
      },
    );
  }
}

/// Shows the one-time welcome for brand-new installs, then the splash lobby.
class _FirstRunGate extends StatefulWidget {
  const _FirstRunGate({this.backendReady, this.initialMatchId});

  final Future<void>? backendReady;
  final String? initialMatchId;

  @override
  State<_FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<_FirstRunGate> {
  bool _checked = false;
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final seen = await WelcomePage.seen();
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (!_seen) {
      return WelcomePage(
        onDone: () {
          if (!mounted) return;
          setState(() => _seen = true);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => SplashGate(
                backendReady: widget.backendReady,
                initialMatchId: widget.initialMatchId,
              ),
            ),
          );
        },
      );
    }
    return SplashGate(
      backendReady: widget.backendReady,
      initialMatchId: widget.initialMatchId,
    );
  }
}

/// Re-applies the system bar icon colours after every theme change and after
/// the native player returns: the AnnotatedRegion alone can be missed on some
/// OEM builds, which left unreadable status-bar content in the light theme.
class _OverlaySync extends StatelessWidget {
  const _OverlaySync({required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = (dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(style);
    });
    return child;
  }
}
