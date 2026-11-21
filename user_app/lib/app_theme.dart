import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Noellyne Bet design tokens — see DESIGN_SYSTEM.md (locked brief).
///
/// Warm Editorial Glassmorphism: alabaster canvas, terracotta ambient glow,
/// frosted cards, matte obsidian actions. Restraint over neon.
class NoellyneColors {
  // Light canvas + ink.
  static const canvasLight = Color(0xFFFAF7F5);
  static const ink = Color(0xFF1D1918);
  static const mutedLight = Color(0xFF736A66);

  // Ambient terracotta glow (light).
  static const glowSoft = Color(0xFFF4A28C);
  static const glowDeep = Color(0xFFE88267);

  // Glass surfaces (light) — faked with translucent gradients, no blur
  // inside scrolling lists (GPU-safe on mid-range Android).
  static const glassLight = Color(0xBDFFFFFF); // rgba(255,255,255,0.74)
  static const glassBorderLight = Color(0xA6FFFFFF); // rgba(255,255,255,0.65)
  static const innerLight = Color(0xF2FFFFFF); // white @ 0.95

  // Dark twin: #141212 base + burnt coral glow + 7% white glass.
  static const canvasDark = Color(0xFF141212);
  static const surfaceDark = Color(0xFF1D1918);
  static const innerDark = Color(0xFF241E1C);
  static const mutedDark = Color(0xFFA89C96);
  static const glowDark = Color(0xFFD96B52);
  static const glassDark = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static const glassBorderDark = Color(0x33FFFFFF); // rgba(255,255,255,0.20)

  // Live / highlight tint.
  static const liveBg = Color(0xFFFCE5DC);
  static const liveInk = Color(0xFFC85A3F);
  static const live = Color(0xFFE5484D);

  // Settlement outcome tokens (light & dark accessible).
  static const winBg = Color(0xFFE6F6EE);
  static const winInk = Color(0xFF177A48);
  static const winDark = Color(0xFF2FBF71);
  static const lossBg = Color(0xFFFDECEC);
  static const lossInk = Color(0xFFC23B3B);

  static const _seed = glowDeep;
}

/// Motion tokens (DESIGN_SYSTEM.md): snappy taps, expo-out reveals.
class NoellyneMotion {
  static const tap = Duration(milliseconds: 140);
  static const reveal = Duration(milliseconds: 320);
  static const tapCurve = Cubic(0.22, 1, 0.36, 1);
  static const revealCurve = Cubic(0.16, 1, 0.3, 1);
  static const pressScale = 0.96;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: NoellyneColors._seed,
      brightness: Brightness.light,
      surface: NoellyneColors.canvasLight,
    ).copyWith(
      primary: NoellyneColors.ink,
      onPrimary: Colors.white,
      secondary: NoellyneColors.glowDeep,
      onSecondary: Colors.white,
      tertiary: NoellyneColors.glowSoft,
      onSurface: NoellyneColors.ink,
      onSurfaceVariant: NoellyneColors.mutedLight,
      surfaceContainerHighest: NoellyneColors.innerLight,
      outlineVariant: const Color(0xFFE8DFDA),
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: NoellyneColors.canvasLight,
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3EDEA),
        selectedColor: NoellyneColors.glowDeep.withValues(alpha: .16),
        side: const BorderSide(color: Color(0xFFE6DCD7)),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: NoellyneColors.ink,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFFB4502F),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: NoellyneColors.glassLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: NoellyneColors.glassBorderLight),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: NoellyneColors.glowDark,
      brightness: Brightness.dark,
      surface: NoellyneColors.canvasDark,
    ).copyWith(
      primary: NoellyneColors.glowDark,
      onPrimary: NoellyneColors.ink,
      secondary: NoellyneColors.glowSoft,
      onSecondary: NoellyneColors.ink,
      tertiary: NoellyneColors.glowDark,
      onSurface: const Color(0xFFF5EFEA),
      onSurfaceVariant: NoellyneColors.mutedDark,
      surfaceContainerHighest: NoellyneColors.innerDark,
      outlineVariant: const Color(0xFF2E2624),
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: NoellyneColors.canvasDark,
      appBarTheme: _base(scheme).appBarTheme.copyWith(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF232020),
        selectedColor: NoellyneColors.glowDeep.withValues(alpha: .26),
        side: const BorderSide(color: Color(0x33FFFFFF)),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF3EDEA),
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: NoellyneColors.glowSoft,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: NoellyneColors.glassDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: NoellyneColors.glassBorderDark),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Plus Jakarta Sans (bundled asset) with Inter fallback.
      fontFamily: 'PlusJakartaSans',
      fontFamilyFallback: const ['Inter', 'Roboto'],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        // The app bars are transparent, so Android must be told explicitly
        // which icon colour reads on the warm canvas.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w900,
          letterSpacing: -.42, // -0.02em
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .5),
        thickness: 1,
        space: 1,
      ),
      // Every interactive control is a full pill (9999px).
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
        side: BorderSide.none,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .1,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
      // Soft, warm shadows — never muddy gray.
      shadowColor: dark
          ? const Color(0xFF000000)
          : const Color(0xFFE8C9BB),
    );
  }
}

/// Warm atmospheric backdrop: canvas + two heavily blurred terracotta orbs.
/// Wrap the home scaffold body in this so glass cards pick up the glow.
///
/// GPU rule: real blur lives ONLY here (backdrop), the sticky header, the
/// floating dock and sheets — never inside scrolling list items.
class NoellyneBackground extends StatelessWidget {
  const NoellyneBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: _GlowOrb(
            size: 320,
            color: (dark ? NoellyneColors.glowDark : NoellyneColors.glowSoft)
                .withValues(alpha: dark ? .18 : .45),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -100,
          child: _GlowOrb(
            size: 360,
            color: (dark ? NoellyneColors.glowDark : NoellyneColors.glowDeep)
                .withValues(alpha: dark ? .18 : .30),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
