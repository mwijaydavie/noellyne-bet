import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Broadcast-style buffering indicator.
///
/// A coral sweep arc rotates inside expanding radar rings, drawn by a single
/// [CustomPainter] that repaints straight off the controller (no widget
/// rebuilds), wrapped in a [RepaintBoundary]. The status line steps through
/// "Connecting…" → "Optimizing HD stream…" with a 350ms crossfade.
class NoellyneStreamLoader extends StatefulWidget {
  const NoellyneStreamLoader({
    super.key,
    this.label = 'Connecting…',
    this.optimizingLabel = 'Optimizing HD stream…',
    this.size = 64,
    this.showLabel = true,
  });

  final String label;
  final String optimizingLabel;
  final double size;
  final bool showLabel;

  @override
  State<NoellyneStreamLoader> createState() => _NoellyneStreamLoaderState();
}

class _NoellyneStreamLoaderState extends State<NoellyneStreamLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  Timer? _phaseTimer;
  bool _optimizing = false;

  @override
  void initState() {
    super.initState();
    _phaseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _optimizing = true);
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _StreamLoaderPainter(
                    progress: reducedMotion ? .35 : _controller.value,
                    accent: NoellyneColors.glowDeep,
                    glow: NoellyneColors.glowSoft,
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.showLabel) ...[
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              _optimizing ? widget.optimizingLabel : widget.label,
              key: ValueKey(_optimizing),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .1,
                color: Color(0xFFF4A28C),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StreamLoaderPainter extends CustomPainter {
  _StreamLoaderPainter({
    required this.progress,
    required this.accent,
    required this.glow,
  });

  final double progress;
  final Color accent;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;

    // Expanding radar rings: three staggered pulses rising and fading out.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      final radius = maxRadius * (.45 + .55 * t);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = glow.withValues(alpha: (.34 * (1 - t)).clamp(0.0, .34).toDouble());
      canvas.drawCircle(center, radius, paint);
    }

    // Static track.
    final trackRadius = maxRadius * .62;
    canvas.drawCircle(
      center,
      trackRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: .10),
    );

    // Coral sweep arc with a soft gradient tail.
    final arcRect = Rect.fromCircle(center: center, radius: trackRadius);
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: .15),
          accent,
        ],
        stops: const [0, .55, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(arcRect);
    canvas.drawArc(
      arcRect,
      progress * math.pi * 2 - math.pi / 2,
      math.pi * 1.25,
      false,
      sweepPaint,
    );

    // Core dot pulsing with the sweep.
    final pulse = .5 + .5 * math.sin(progress * math.pi * 2);
    canvas.drawCircle(
      center,
      3.2 + pulse * 1.6,
      Paint()..color = accent.withValues(alpha: .55 + .35 * pulse),
    );
  }

  @override
  bool shouldRepaint(covariant _StreamLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.glow != glow;
}
