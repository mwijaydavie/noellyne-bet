import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../design/noellyne_ui.dart';
import 'home_page.dart';

/// First frame of the app: a warm alabaster canvas, a terracotta glow that
/// blooms outward, the Noellyne "N" mark landing with an elastic settle and a
/// shimmering broadcast ring. After ~1.5s it crossfades into the lobby.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, this.backendReady, this.initialMatchId});

  final Future<void>? backendReady;
  final String? initialMatchId;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Never block startup on the network: the lobby loads in parallel.
    _timer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: NoellyneMotion.revealCurve,
      switchOutCurve: NoellyneMotion.revealCurve,
      child: _ready
          ? HomePage(
              key: const ValueKey('lobby'),
              backendReady: widget.backendReady,
              initialMatchId: widget.initialMatchId,
            )
          : const NoellyneSplash(key: ValueKey('splash')),
    );
  }
}

class NoellyneSplash extends StatefulWidget {
  const NoellyneSplash({super.key});

  @override
  State<NoellyneSplash> createState() => _NoellyneSplashState();
}

class _NoellyneSplashState extends State<NoellyneSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  late final Animation<double> _mark = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, .55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _glow = CurvedAnimation(
    parent: _c,
    curve: const Interval(.1, .9, curve: NoellyneMotion.revealCurve),
  );
  late final Animation<double> _text = CurvedAnimation(
    parent: _c,
    curve: const Interval(.45, 1, curve: NoellyneMotion.revealCurve),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: NoellyneBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glow bloom + landing mark.
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    FadeTransition(
                      opacity: _glow,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .6, end: 1.25).animate(
                          reduceMotion
                              ? const AlwaysStoppedAnimation(1)
                              : _glow,
                        ),
                        child: Container(
                          width: 168,
                          height: 168,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                NoellyneColors.glowDeep.withValues(
                                  alpha: dark ? .30 : .45,
                                ),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Broadcast ring.
                    FadeTransition(
                      opacity: _glow,
                      child: Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: NoellyneColors.glowDeep
                                .withValues(alpha: .45),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    ScaleTransition(
                      scale: Tween<double>(begin: .72, end: 1).animate(
                        reduceMotion
                            ? const AlwaysStoppedAnimation(1)
                            : _mark,
                      ),
                      child: Container(
                        width: 86,
                        height: 86,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              NoellyneColors.glowSoft,
                              NoellyneColors.glowDeep,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: NoellyneColors.glowDeep
                                  .withValues(alpha: .45),
                              blurRadius: 36,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Text(
                          'N',
                          style: TextStyle(
                            fontSize: 44,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: dark
                                ? NoellyneColors.ink
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _text,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .25),
                    end: Offset.zero,
                  ).animate(_text),
                  child: Column(
                    children: [
                      Text(
                        'Noellyne Bet',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'LIVE FOOTBALL · AI PICKS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
