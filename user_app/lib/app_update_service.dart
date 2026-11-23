import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'app_update_installer.dart';
import 'noellyne_config.dart';

/// Refuse unrelated or corrupted manifests before comparing version codes.
/// Noellyne manifests are served from OUR GitHub releases only.
@visibleForTesting
bool isNoellyneRelease(Map<String, dynamic> release) {
  final uri = Uri.tryParse(release['apk_url']?.toString() ?? '');
  final digest = (release['sha256'] ?? '').toString().trim().toLowerCase();
  final version = (release['version_name'] ?? '').toString().trim();
  final size = int.tryParse(release['size_bytes']?.toString() ?? '') ?? 0;
  final build = int.tryParse(release['build_number']?.toString() ?? '') ?? 0;
  return release['app'] == 'noellyne_viewer' &&
      uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.path.startsWith(NoellyneConfig.releaseRepoPath) &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) &&
      RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) &&
      size > 0 &&
      size <= 120 * 1024 * 1024 &&
      build > 0;
}

/// Only our own signed release may be offered to the user.
@visibleForTesting
bool validViewerRelease(Map<String, dynamic> release) =>
    isNoellyneRelease(release);

class _RemoteUpdatePolicy {
  const _RemoteUpdatePolicy({
    this.minSupportedBuild = 0,
    this.customNotice = '',
  });

  final int minSupportedBuild;
  final String customNotice;
}

class AppUpdateService {
  AppUpdateService._();

  static bool _checked = false;
  static bool _downloading = false;
  static const _dismissedBuildKey = 'noellyne_update_dismissed_build_v1';
  static const _dismissedAtKey = 'noellyne_update_dismissed_at_v1';
  static const _snoozeDuration = Duration(hours: 12);

  static const _manifestUrls = <String>[
    NoellyneConfig.updateManifestUrl,
  ];

  @visibleForTesting
  static List<String> get manifestUrls => _manifestUrls;

  /// Reads optional remote update policy (`min_supported_build`, `update_notice`)
  /// from Supabase `public.app_config` so the founder can enforce a polite
  /// mandatory upgrade remotely (e.g. when launching payments or security fixes).
  static Future<_RemoteUpdatePolicy> _fetchRemotePolicy() async {
    if (!NoellyneConfig.picksSupabaseEnabled) {
      return const _RemoteUpdatePolicy();
    }
    try {
      final base = NoellyneConfig.picksSupabaseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        '$base/rest/v1/app_config?key=in.(min_supported_build,update_notice)&select=key,value',
      );
      final resp = await http
          .get(
            uri,
            headers: const {
              'apikey': NoellyneConfig.picksSupabaseAnonKey,
              'Authorization': 'Bearer ${NoellyneConfig.picksSupabaseAnonKey}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const _RemoteUpdatePolicy();
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (decoded is! List) return const _RemoteUpdatePolicy();
      var minBuild = 0;
      var notice = '';
      for (final row in decoded.whereType<Map>()) {
        final k = '${row['key'] ?? ''}'.trim();
        final v = '${row['value'] ?? ''}'.trim();
        if (k == 'min_supported_build') {
          minBuild = int.tryParse(v) ?? 0;
        } else if (k == 'update_notice') {
          notice = v;
        }
      }
      return _RemoteUpdatePolicy(
        minSupportedBuild: minBuild,
        customNotice: notice,
      );
    } catch (_) {
      return const _RemoteUpdatePolicy();
    }
  }

  static Future<String> versionSummary() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version.trim().isEmpty
          ? '10.0.0'
          : info.version.trim();
      final currentBuild = info.buildNumber.trim();
      final installed = currentBuild.isEmpty
          ? 'V$currentVersion'
          : 'V$currentVersion ($currentBuild)';

      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return 'Installed $installed';
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (final base in _manifestUrls) {
        try {
          final response = await http
              .get(
                Uri.parse('$base?t=$stamp'),
                headers: const {
                  'Accept': 'application/json',
                  'Cache-Control': 'no-cache',
                },
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
          if (decoded is! Map ||
              !validViewerRelease(Map<String, dynamic>.from(decoded))) {
            continue;
          }

          final latestVersion =
              decoded['version_name']?.toString().trim() ?? '';
          final latestBuild = decoded['build_number']?.toString().trim() ?? '';
          if (latestVersion.isEmpty && latestBuild.isEmpty) {
            return 'Installed $installed';
          }

          final latest = latestBuild.isEmpty
              ? 'V$latestVersion'
              : 'V$latestVersion ($latestBuild)';
          return 'Installed $installed • Latest $latest';
        } catch (_) {}
      }

      return 'Installed $installed • Latest unavailable';
    } catch (_) {
      return 'Version unavailable';
    }
  }

  static Future<bool> _isSnoozed(int latestBuild) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedBuild = prefs.getInt(_dismissedBuildKey) ?? 0;
      final dismissedAtMs = prefs.getInt(_dismissedAtKey) ?? 0;
      if (dismissedBuild != latestBuild || dismissedAtMs <= 0) return false;
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(dismissedAtMs),
      );
      return elapsed >= Duration.zero && elapsed < _snoozeDuration;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _snooze(int latestBuild) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedBuildKey, latestBuild);
      await prefs.setInt(
        _dismissedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> check(BuildContext context, {bool force = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_checked && !force) return;
    _checked = true;

    await AnalyticsService.capture(
      'update check',
      properties: {'manual': force},
    );

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final policyFuture = _fetchRemotePolicy();
      Map<dynamic, dynamic>? data;

      for (final base in _manifestUrls) {
        try {
          final response = await http
              .get(
                Uri.parse('$base?t=$stamp'),
                headers: const {
                  'Accept': 'application/json',
                  'Cache-Control': 'no-cache',
                },
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
          if (decoded is Map) {
            final candidate = Map<String, dynamic>.from(decoded);
            if (!validViewerRelease(candidate)) continue;
            data = candidate;
            break;
          }
        } catch (_) {}
      }

      final policy = await policyFuture;

      if (data == null) {
        await AnalyticsService.capture(
          'update check failed',
          properties: {'manual': force, 'reason': 'manifest_unavailable'},
        );
        if (force && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not check for updates right now.'),
            ),
          );
        }
        return;
      }

      final latestBuild =
          int.tryParse(data['build_number']?.toString() ?? '') ?? 0;
      if (latestBuild <= currentBuild) {
        await AnalyticsService.capture(
          'update current',
          properties: {
            'manual': force,
            'current_build': currentBuild,
            'latest_build': latestBuild,
          },
        );
        if (force && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Noellyne ${info.version} (build ${info.buildNumber}) is up to date.',
              ),
            ),
          );
        }
        return;
      }

      final version = data['version_name']?.toString().trim().isNotEmpty == true
          ? data['version_name'].toString()
          : 'new version';
      final apkUrl = data['apk_url']?.toString().trim() ?? '';
      final apkSha256 = data['sha256']?.toString().trim().toLowerCase() ?? '';
      final manifestNotes = data['notes']?.toString().trim() ?? '';
      final notes = policy.customNotice.isNotEmpty
          ? policy.customNotice
          : manifestNotes;
      final mandatory = data['mandatory'] == true ||
          (policy.minSupportedBuild > 0 &&
              currentBuild < policy.minSupportedBuild);
      final validHash = RegExp(r'^[0-9a-f]{64}$').hasMatch(apkSha256);

      if (apkUrl.isEmpty || !validHash) {
        await AnalyticsService.capture(
          'update check failed',
          properties: {
            'manual': force,
            'reason': apkUrl.isEmpty
                ? 'apk_url_missing'
                : 'apk_sha256_missing_or_invalid',
          },
        );
        if (force && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The update package could not be verified.'),
            ),
          );
        }
        return;
      }

      // Respect 12h snooze on optional updates unless user tapped Check manually.
      if (!mandatory && !force && await _isSnoozed(latestBuild)) {
        return;
      }
      if (!context.mounted) return;

      await AnalyticsService.capture(
        'update available',
        properties: {
          'manual': force,
          'current_build': currentBuild,
          'latest_build': latestBuild,
          'version': version,
          'mandatory': mandatory,
        },
      );

      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (dialogContext) => PopScope(
          canPop: !mandatory,
          child: AlertDialog(
            icon: Icon(
              mandatory
                  ? Icons.security_update_warning_rounded
                  : Icons.system_update_alt_rounded,
            ),
            title: Text(
              mandatory
                  ? 'Toleo Jipya la Noellyne Linahitajika'
                  : 'Noellyne $version inapatikana',
            ),
            content: Text(
              mandatory
                  ? (notes.isEmpty
                      ? 'Tumeongeza maboresho muhimu ya usalama na kasi kwenye Noellyne ($version · build $latestBuild). Tafadhali sasisha sasa ili kuendelea.'
                      : '$notes\n\nSasisha sasa (build $latestBuild) ili kuendelea kutumia Noellyne.')
                  : (notes.isEmpty
                      ? 'Toleo jipya la Noellyne ($version · build $latestBuild) liko tayari na maboresho mapya. Ungependa kusasisha sasa?'
                      : notes),
            ),
            actions: [
              if (!mandatory)
                TextButton(
                  onPressed: () {
                    unawaited(_snooze(latestBuild));
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Baadaye'),
                ),
              FilledButton.icon(
                onPressed: () {
                  AnalyticsService.capture(
                    'update accepted',
                    properties: {'latest_build': latestBuild, 'version': version},
                  );
                  if (!mandatory) {
                    Navigator.pop(dialogContext);
                  }
                  _download(context, apkUrl, apkSha256);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Update Now'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      await AnalyticsService.capture(
        'update check failed',
        properties: {'manual': force, 'reason': 'unexpected_error'},
      );
      if (force && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check for updates right now.'),
          ),
        );
      }
    }
  }

  static Future<void> _download(
    BuildContext context,
    String apkUrl,
    String apkSha256,
  ) async {
    if (_downloading || !context.mounted) return;
    _downloading = true;
    final progress = ValueNotifier<double>(0);
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => AlertDialog(
            title: const Text('Downloading Noellyne update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value > 0 && value < 1 ? value : null,
                ),
                const SizedBox(height: 12),
                Text(
                  value > 0
                      ? '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%'
                      : 'Starting download…',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    unawaited(navigator.push(route));

    try {
      await AnalyticsService.capture('update download started');
      await downloadAndInstallApk(
        apkUrl,
        expectedSha256: apkSha256,
        onProgress: (value) => progress.value = value,
      );
      await AnalyticsService.capture(
        'update download completed',
        properties: {'sha256_verified': true},
      );
    } catch (error) {
      final verificationFailure =
          error.toString().toLowerCase().contains('sha-256') ||
          error.toString().toLowerCase().contains('verified');
      await AnalyticsService.capture(
        'update download failed',
        properties: {
          'reason': verificationFailure
              ? 'sha256_verification_failed'
              : 'download_or_installer_failed',
        },
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verificationFailure
                  ? 'Update verification failed. The APK was not installed.'
                  : 'Update download failed. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (route.isActive) navigator.removeRoute(route);
      progress.dispose();
      _downloading = false;
    }
  }
}
