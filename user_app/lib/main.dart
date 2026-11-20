import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'noellyne_config.dart';
import 'screens/home_page.dart';
import 'screens/splash_screen.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backendReady = _initializeBackend();
  runApp(FootballViewerApp(backendReady: backendReady));

  // Render the app before optional network/storage setup finishes.
  unawaited(_loadTheme());
  unawaited(AnalyticsService.initialize());
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
                systemNavigationBarColor:
                    Theme.of(context).colorScheme.surface,
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
