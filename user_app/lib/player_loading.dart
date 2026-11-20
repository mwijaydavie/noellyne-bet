import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/noellyne_stream_loader.dart';

// Surface only locally-authored, fixed source error text. Never echo raw
// upstream exceptions, private stream URLs, tokens, or response payloads.
String safeLineLoadError(Object? error) {
  const fallback = 'Could not load lines. Check your connection and try again.';
  return fallback;
}

/// Dismissing the loading dialog cancels opening the chooser. Only remove our
/// own route when the request completes, never the page beneath it.
Future<T?> loadPlayerSources<T>(
  BuildContext context,
  Future<T> Function() load, {
  void Function()? onCancelled,
  void Function(Object)? onFailure,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      content: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: NoellyneStreamLoader(
          size: 58,
          label: 'Loading lines…',
          optimizingLabel: 'Optimizing HD stream…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  unawaited(navigator.push(route));
  var loadFinished = false;
  unawaited(
    route.popped.then((_) {
      if (!loadFinished) onCancelled?.call();
    }),
  );
  T? result;
  Object? failure;
  var cancelled = false;
  try {
    result = await load();
  } catch (error) {
    failure = error;
  } finally {
    loadFinished = true;
    cancelled = !route.isActive;
    if (route.isActive) navigator.removeRoute(route);
  }
  if (cancelled || !context.mounted) return null;
  if (failure != null) {
    if (onFailure != null) {
      onFailure(failure);
      return null;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(safeLineLoadError(failure))));
    return null;
  }
  return result;
}
