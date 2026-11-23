import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import '../theme_controller.dart';
import 'home_page.dart';

/// First-run welcome. Warm editorial canvas, coral thread, zero blur cost:
/// gradients only, so it stays 60fps on mid-range phones.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, this.onDone});

  final VoidCallback? onDone;

  static const storageKey = 'noellyne_welcome_v1';

  static Future<bool> seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(storageKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..forward();

  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(WelcomePage.storageKey, true);
    } catch (_) {}
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? NoellyneColors.canvasLight : NoellyneColors.ink;
    final muted = dark ? NoellyneColors.mutedDark : NoellyneColors.mutedLight;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [
                          Color(0xFF151212),
                          Color(0xFF1B1514),
                          Color(0xFF141212),
                        ]
                      : const [
                          Color(0xFFFAF7F5),
                          Color(0xFFFDEDE7),
                          Color(0xFFFAF7F5),
                        ],
                ),
              ),
            ),
          ),
          // Terracotta light leak (static gradient, no BackdropFilter).
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33F4A28C), Color(0x00F4A28C)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 46),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Reveal(
                          animation: _c,
                          interval: 0.0,
                          child: _brandMark(),
                        ),
                        const SizedBox(height: 26),
                        _Reveal(
                          animation: _c,
                          interval: 0.12,
                          child: Text(
                            'Welcome to\nNoellyne',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1.06,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.02 * 38,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Reveal(
                          animation: _c,
                          interval: 0.2,
                          child: Text(
                            'Live matches, clean channels and AI picks — '
                            'built for fast, low-data viewing.',
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              color: muted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        _Reveal(
                          animation: _c,
                          interval: 0.28,
                          child: _feature(
                            icon: Icons.sports_soccer_rounded,
                            title: 'Live and upcoming',
                            body:
                                'Every match with a real stream line, on air times and crests.',
                            ink: ink,
                            muted: muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Reveal(
                          animation: _c,
                          interval: 0.34,
                          child: _feature(
                            icon: Icons.graphic_eq_rounded,
                            title: 'Audio mode saves data',
                            body:
                                'Switch to audio only and keep listening while you browse.',
                            ink: ink,
                            muted: muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Reveal(
                          animation: _c,
                          interval: 0.4,
                          child: _feature(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Noellyne AI',
                            body:
                                'Ask about form, markets or a specific fixture — no fake odds.',
                            ink: ink,
                            muted: muted,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _Reveal(
                          animation: _c,
                          interval: 0.46,
                          child: _appearance(ink: ink, muted: muted),
                        ),
                        const SizedBox(height: 26),
                        _Reveal(
                          animation: _c,
                          interval: 0.52,
                          child: PillButton(
                            label: _busy ? 'Setting things up…' : 'Start watching',
                            icon: Icons.arrow_forward_rounded,
                            tone: PillTone.glow,
                            height: 54,
                            onPressed: _busy ? null : () => _finish(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Change this any time in More → Appearance',
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandMark() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [NoellyneColors.glowSoft, NoellyneColors.glowDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: NoellyneColors.glowDeep.withValues(alpha: 0.32),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'N',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 19,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'NOELLYNE',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }

  Widget _feature({
    required IconData icon,
    required String title,
    required String body,
    required Color ink,
    required Color muted,
  }) {
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NoellyneColors.glowDeep.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 19, color: NoellyneColors.glowDeep),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.28,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(fontSize: 12.5, height: 1.38, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearance({required Color ink, required Color muted}) {
    final current = AppThemeController.instance.mode;
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.light, 'Light', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
      (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APPEARANCE',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (mode, label, icon) in options) ...[
              Expanded(
                child: PressableScale(
                  onTap: () => AppThemeController.instance.setMode(mode),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: current == mode
                          ? NoellyneColors.glowDeep.withValues(alpha: 0.14)
                          : Colors.transparent,
                      border: Border.all(
                        color: current == mode
                            ? NoellyneColors.glowDeep.withValues(alpha: 0.55)
                            : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0x22FFFFFF)
                                : const Color(0xFFEAE3DF)),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: current == mode
                                ? NoellyneColors.glowDeep
                                : muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: current == mode
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current == mode
                                  ? NoellyneColors.glowDeep
                                  : ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (label != 'System') const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.interval,
    required this.child,
  });

  final Animation<double> animation;
  final double interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = interval.clamp(0.0, 0.75);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, (start + 0.42).clamp(0.0, 1.0),
          curve: NoellyneMotion.revealCurve),
    );
    final disabled = MediaQuery.of(context).disableAnimations;
    if (disabled) return child;
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final v = curved.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 16),
            child: child,
          ),
        );
      },
    );
  }
}
