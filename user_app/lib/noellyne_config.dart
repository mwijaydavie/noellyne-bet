/// Noellyne Bet build-time configuration.
///
/// Every value can be overridden without touching code:
///   flutter build apk --dart-define=SUPABASE_URL=... \
///                     --dart-define=SUPABASE_ANON_KEY=... \
///                     --dart-define=PUBLIC_API_BASE=... \
///                     --dart-define=UPDATE_MANIFEST_URL=...
///
/// The defaults keep the current public feed working while the Noellyne
/// backend is being provisioned. Once the new Supabase project exists, only
/// these defaults (or the CI `--dart-define` flags) need to change.
class NoellyneConfig {
  const NoellyneConfig._();

  /// Supabase is OPTIONAL. Leave both empty (the default) and the app still
  /// runs: the match feed, playback and AI chat work without it. Only
  /// realtime updates and cloud Daily Picks need a project.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get supabaseEnabled =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// n8n webhook that powers the in-app Noellyne AI chat. Point this at a
  /// `Webhook` node wired to your Hermes prompt + provider fallback chain.
  /// Empty → the app uses its built-in offline betting assistant.
  static const aiChatWebhook = String.fromEnvironment(
    'AI_CHAT_WEBHOOK',
    defaultValue: '',
  );

  /// Cloudflare / Vercel match feed.
  static const publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );

  /// Rolling manifest published by `.github/workflows/build-noellyne-apk.yml`
  /// on the `viewer-latest` release of OUR repository.
  static const updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/mwijaydavie/noellyne-bet/'
        'releases/download/viewer-latest/latest.json',
  );

  /// Owner/repo that in-app updates are allowed to come from.
  static const releaseRepoPath = '/mwijaydavie/noellyne-bet/releases/download/';
}
