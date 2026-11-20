import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Noellyne Bet shared UI kit — see DESIGN_SYSTEM.md.
///
/// GPU rules enforced here:
///  * [GlassCard] never blurs (scrolling lists stay cheap): it fakes glass
///    with a translucent gradient + 1px crisp border.
///  * [GlassBlur] is only for sticky headers, the floating dock and sheets.
///  * [PressableScale] uses transform + opacity only (140ms, .96).
class NoellyneUI {
  const NoellyneUI._();

  /// -0.02em headline tracking.
  static const headlineTracking = -.42;

  static List<FontFeature> get tabular =>
      const [FontFeature.tabularFigures()];
}

/// Tabular numerals — scores, odds, clocks never jitter.
class TabularText extends StatelessWidget {
  const TabularText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        fontFeatures: NoellyneUI.tabular,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Tap feedback: snappy 140ms scale to .96 with the house curve.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = NoellyneMotion.pressScale,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: NoellyneMotion.tap,
        curve: NoellyneMotion.tapCurve,
        child: widget.child,
      ),
    );
  }
}

/// Frosted glass surface for cards. **No backdrop blur** — safe in lists.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 26,
    this.onTap,
    this.glowCorner = false,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Adds the terracotta light-leak in the top-right corner.
  final bool glowCorner;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = dark
        ? NoellyneColors.glassBorderDark
        : NoellyneColors.glassBorderLight;
    final radiusGeo = BorderRadius.circular(radius);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radiusGeo,
        border: Border.all(color: border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0x1AFFFFFF), Color(0x0AFFFFFF)]
              : const [Color(0xC4FFFFFF), Color(0xA8FFFFFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: .35)
                : const Color(0x0D1D1918), // rgba(29,25,24,.05)
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (glowCorner) {
      card = ClipRRect(
        borderRadius: radiusGeo,
        child: Stack(
          children: [
            card,
            Positioned(
              top: -70,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (dark ? NoellyneColors.glowDark : NoellyneColors.glowSoft)
                            .withValues(alpha: dark ? .22 : .55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final result = Padding(padding: margin, child: card);
    if (onTap == null) return result;
    return PressableScale(onTap: onTap, borderRadius: radiusGeo, child: result);
  }
}

/// Backdrop-blurred surface. **Only** for sticky headers, floating dock,
/// bottom sheets and modals — never inside scrolling lists.
class GlassBlur extends StatelessWidget {
  const GlassBlur({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(8),
    this.sigma = 22,
    this.border = true,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double sigma;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radiusGeo = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radiusGeo,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .45 : .14),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radiusGeo,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radiusGeo,
              color: dark ? NoellyneColors.glassDark : NoellyneColors.glassLight,
              border: border
                  ? Border.all(
                      color: dark
                          ? NoellyneColors.glassBorderDark
                          : NoellyneColors.glassBorderLight,
                    )
                  : null,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Primary obsidian CTA (pill). In dark mode it becomes burnt coral.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.tone = PillTone.obsidian,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final PillTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final (bg, fg, side) = switch (tone) {
      PillTone.obsidian => (
          dark ? NoellyneColors.glowDark : NoellyneColors.ink,
          dark ? NoellyneColors.ink : Colors.white,
          null,
        ),
      PillTone.glow => (
          dark
              ? NoellyneColors.glowDark.withValues(alpha: .18)
              : NoellyneColors.liveBg,
          dark ? NoellyneColors.glowSoft : NoellyneColors.liveInk,
          null,
        ),
      PillTone.ghost => (
          dark ? NoellyneColors.innerDark : NoellyneColors.innerLight,
          scheme.onSurface,
          BorderSide(
            color: dark
                ? NoellyneColors.glassBorderDark
                : NoellyneColors.glassBorderLight,
          ),
        ),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              letterSpacing: .1,
            ),
          ),
        ),
      ],
    );

    final body = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
        border: side == null ? null : Border.fromBorderSide(side),
        boxShadow: tone == PillTone.obsidian
            ? [
                BoxShadow(
                  color: (dark ? NoellyneColors.glowDark : NoellyneColors.ink)
                      .withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: content,
    );

    final wrapped = onPressed == null
        ? Opacity(opacity: .5, child: body)
        : PressableScale(onTap: onPressed, child: body);

    return expand
        ? SizedBox(width: double.infinity, child: wrapped)
        : wrapped;
  }
}

enum PillTone { obsidian, glow, ghost }

/// Filter / segment pill used in horizontal rails.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onInk = dark ? NoellyneColors.ink : Colors.white;
    final bg = selected
        ? (dark ? NoellyneColors.glowDark : NoellyneColors.ink)
        : (dark ? NoellyneColors.innerDark : NoellyneColors.innerLight);
    final fg = selected ? onInk : Theme.of(context).colorScheme.onSurfaceVariant;

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: NoellyneMotion.tap,
        curve: NoellyneMotion.tapCurve,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9999),
          border: selected
              ? null
              : Border.all(
                  color: dark
                      ? NoellyneColors.glassBorderDark
                      : NoellyneColors.glassBorderLight,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LIVE / kickoff status pill.
class LivePill extends StatelessWidget {
  const LivePill({
    super.key,
    this.text = 'LIVE',
    this.pulse = true,
    this.tint,
  });

  final String text;
  final bool pulse;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? NoellyneColors.live;
    return _PulsingBadge(text: text, color: color, pulse: pulse);
  }
}

class _PulsingBadge extends StatefulWidget {
  const _PulsingBadge({
    required this.text,
    required this.color,
    required this.pulse,
  });

  final String text;
  final Color color;
  final bool pulse;

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: widget.pulse
                ? Tween<double>(begin: 1, end: .35).animate(_c)
                : const AlwaysStoppedAnimation(1),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (actionLabel != null)
            PressableScale(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NoellyneColors.glowDeep,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Staggered expo-out reveal for feed items.
class RevealIn extends StatefulWidget {
  const RevealIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: NoellyneMotion.reveal,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: NoellyneMotion.revealCurve,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.offset / 100),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Floating frosted bottom dock + detached glowing AI button (right).
/// This is one of the few places real blur is allowed.
class FloatingDock extends StatelessWidget {
  const FloatingDock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
    this.onAiPressed,
    this.aiTooltip = 'Daily Picks',
  });

  final List<DockItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback? onAiPressed;
  final String aiTooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stadium capsule: 60 high, fully rounded, 5px inner inset.
          Expanded(
            child: SizedBox(
              height: 60,
              child: GlassBlur(
                radius: 999,
                padding: const EdgeInsets.all(5),
                sigma: 18,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _DockTile(
                          item: items[i],
                          active: i == index,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onSelected(i);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onAiPressed != null) ...[
            const SizedBox(width: 12),
            PressableScale(
              onTap: () {
                HapticFeedback.lightImpact();
                onAiPressed!();
              },
              scale: .95,
              child: Tooltip(
                message: aiTooltip,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF4977E), Color(0xFFE57558)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE57558).withValues(alpha: .45),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: dark ? NoellyneColors.ink : Colors.white,
                    size: 25,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DockItem {
  const DockItem({required this.icon, required this.label, this.activeIcon});

  final IconData icon;
  final String label;
  final IconData? activeIcon;
}

class _DockTile extends StatelessWidget {
  const _DockTile({required this.item, required this.active, required this.onTap});

  final DockItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = dark ? NoellyneColors.glowDark : NoellyneColors.ink;
    final activeFg = dark ? NoellyneColors.ink : Colors.white;
    final fg = active ? activeFg : Theme.of(context).colorScheme.onSurfaceVariant;

    return PressableScale(
      onTap: onTap,
      scale: .95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: NoellyneMotion.tapCurve,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          // Full pill so the indicator curve runs concentrically inside the
          // 999-radius dock capsule.
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              active ? (item.activeIcon ?? item.icon) : item.icon,
              size: 20,
              color: fg,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sliding segmented control (999 capsule with a spring-glide indicator).
///
/// Used for the Channels library (All / Favorites / Recent). The indicator is
/// an [AnimatedAlign] + [FractionallySizedBox] pair, so it slides without
/// rebuilding the labels and without clipping on either edge.
class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 42,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final count = labels.isEmpty ? 1 : labels.length;
    final clamped = index.clamp(0, count - 1);
    final alignX = count == 1 ? 0.0 : -1 + (2 * clamped) / (count - 1);

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? NoellyneColors.innerDark : const Color(0xFFF0E8E4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark ? NoellyneColors.glassBorderDark : const Color(0xFFE6DAD4),
        ),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: NoellyneMotion.tapCurve,
            alignment: Alignment(alignX, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF2C2726) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? .35 : .08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == clamped) return;
                      HapticFeedback.selectionClick();
                      onChanged(i);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              i == clamped ? FontWeight.w800 : FontWeight.w600,
                          letterSpacing: -.1,
                          color: i == clamped
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
