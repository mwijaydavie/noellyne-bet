import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../screens/home_page.dart';

/// Android back handling for every root screen.
///
/// * nested routes pop normally,
/// * a non-Home root tab returns to Home instead of closing the app,
/// * Home itself asks for a second press ("Press back again to exit").
class RootBackGuard extends StatefulWidget {
  const RootBackGuard({super.key, required this.child, this.isHome = false});

  final Widget child;
  final bool isHome;

  @override
  State<RootBackGuard> createState() => _RootBackGuardState();
}

class _RootBackGuardState extends State<RootBackGuard> {
  DateTime? _lastPress;

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const RootBackGuard(isHome: true, child: HomePage()),
      ),
      (route) => false,
    );
  }

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (!widget.isHome) {
      _goHome();
      return;
    }
    final now = DateTime.now();
    final previous = _lastPress;
    if (previous == null || now.difference(previous) > const Duration(seconds: 2)) {
      _lastPress = now;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 108),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? NoellyneColors.surfaceDark
                : NoellyneColors.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            content: const Text(
              'Press back again to exit',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
