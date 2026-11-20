import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Skeleton loaders for Noellyne Bet.
///
/// One [AnimationController] per skeleton tree drives every bone through an
/// [AnimatedBuilder], so a loading lobby costs a single ticker instead of one
/// per box — and nothing calls setState per frame.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.dark});

  final Widget child;
  final bool? dark;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark ?? Theme.of(context).brightness == Brightness.dark;
    final disabled = MediaQuery.of(context).disableAnimations;
    final base = dark ? const Color(0xFF221E1D) : const Color(0xFFEDE7E3);
    final highlight = dark ? const Color(0xFF2C2726) : const Color(0xFFF7F2EF);

    if (disabled) {
      return _SkeletonTint(
        color: base,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value * 2 - 1; // -1 → 1
        return _SkeletonTint(
          gradient: LinearGradient(
            begin: Alignment(t - 1, -0.35),
            end: Alignment(t + 1, 0.35),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ),
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

class _SkeletonTint extends StatelessWidget {
  const _SkeletonTint({required this.child, this.color, this.gradient});

  final Widget child;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    // The bones are white/black by default: a single blend pass recolours the
    // whole tree without per-box decoration.
    return _SkeletonScope(
      gradient: gradient,
      color: color,
      child: child,
    );
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({
    required this.gradient,
    required this.color,
    required super.child,
  });

  final Gradient? gradient;
  final Color? color;

  static _SkeletonScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      oldWidget.gradient != gradient || oldWidget.color != color;
}

/// One shimmering bone.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 8,
    this.opacity = 1,
  });

  final double? width;
  final double height;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scope = _SkeletonScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final plain = scope?.color ??
        (dark ? const Color(0xFF221E1D) : const Color(0xFFEDE7E3));
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scope?.gradient == null ? plain : null,
          gradient: scope?.gradient,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Rounded skeleton surface (card / stage).
class BoneBlock extends StatelessWidget {
  const BoneBlock({
    super.key,
    this.height = 64,
    this.width,
    this.radius = 16,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1918) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0x1AFFFFFF) : const Color(0xFFEAE3DF),
        ),
      ),
      child: Bone(height: height, width: width, radius: radius),
    );
  }
}

/// Lobby: filter pills + three match cards.
class SkeletonLobby extends StatelessWidget {
  const SkeletonLobby({super.key, this.cards = 3, this.padding});

  final int cards;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 120),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(
            children: const [
              Expanded(child: Bone(height: 40, radius: 999)),
              SizedBox(width: 8),
              Expanded(child: Bone(height: 40, radius: 999)),
              SizedBox(width: 8),
              Expanded(child: Bone(height: 40, radius: 999)),
            ],
          ),
          const SizedBox(height: 18),
          const Bone(width: 128, height: 13, radius: 6),
          const SizedBox(height: 12),
          const BoneBlock(height: 168, radius: 26),
          const SizedBox(height: 16),
          for (var i = 0; i < cards; i++) ...[
            const _SkeletonMatchCard(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SkeletonMatchCard extends StatelessWidget {
  const _SkeletonMatchCard();

  @override
  Widget build(BuildContext context) {
    return const BoneBlock(radius: 24, height: 132);
  }
}

/// Channels library grid.
class SkeletonChannelGrid extends StatelessWidget {
  const SkeletonChannelGrid({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
        ),
        itemBuilder: (context, index) => const BoneBlock(radius: 22),
      ),
    );
  }
}

/// Generic rows (settings, sources, diagnostics).
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 120),
    this.height = 62,
  });

  final int count;
  final EdgeInsetsGeometry padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => Row(
          children: [
            BoneBlock(height: 42, width: 42, radius: 999),
            const SizedBox(width: 12),
            Expanded(child: Bone(height: height - 30, radius: 10)),
          ],
        ),
      ),
    );
  }
}

/// Small inline bone used while a single line is being re-resolved.
class SkeletonInline extends StatelessWidget {
  const SkeletonInline({super.key, this.width = 72, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Bone(width: width, height: height, radius: 999),
    );
  }
}
