import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/app_update_service.dart';
import 'package:football_viewer/noellyne_config.dart';

void main() {
  test('Viewer checks only our own rolling manifest', () {
    expect(AppUpdateService.manifestUrls, hasLength(1));
    expect(AppUpdateService.manifestUrls.single,
        NoellyneConfig.updateManifestUrl);
  });

  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final ownApk = 'https://github.com/mwijaydavie/noellyne-bet/releases/'
      'download/apk-18/NoellyneBet-10.0.0-40018.apk';

  test('Our own signed release is accepted', () {
    expect(
      validViewerRelease(<String, dynamic>{
        'app': 'noellyne_viewer',
        'version_name': '10.0.0',
        'build_number': 40018,
        'apk_url': ownApk,
        'sha256': digest,
        'size_bytes': 30000000,
      }),
      isTrue,
    );
  });

  test('Upstream project releases can never be offered again', () {
    for (final foreign in <String>[
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
          'football-stream-app/feed/public/releases/NCA-arm64-v8a-latest.apk',
      'https://github.com/nyeinchanaung75299-eng/football-stream-app/'
          'releases/download/apk-1/NCA.apk',
      'https://nca.nyeinchanaung.us.ci/football-stream-app/releases/x.apk',
      'https://untrusted.example/NoellyneBet.apk',
    ]) {
      expect(
        validViewerRelease(<String, dynamic>{
          'app': 'noellyne_viewer',
          'version_name': '10.0.0',
          'build_number': 40018,
          'apk_url': foreign,
          'sha256': digest,
          'size_bytes': 30000000,
        }),
        isFalse,
        reason: foreign,
      );
    }
  });

  test('Broken metadata is rejected', () {
    for (final changes in <Map<String, dynamic>>[
      {'app': 'nca_admin'},
      {'sha256': 'invalid'},
      {'build_number': 0},
      {'size_bytes': 0},
      {'version_name': 'latest'},
      {'apk_url': '$ownApk?download=1'},
    ]) {
      expect(
        validViewerRelease(<String, dynamic>{
          'app': 'noellyne_viewer',
          'version_name': '10.0.0',
          'build_number': 40018,
          'apk_url': ownApk,
          'sha256': digest,
          'size_bytes': 30000000,
          ...changes,
        }),
        isFalse,
        reason: changes.toString(),
      );
    }
  });
}
