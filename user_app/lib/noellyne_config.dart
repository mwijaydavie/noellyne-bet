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

  /// Supabase is ON by default — it is not decoration, it powers:
  ///   • realtime refresh: websocket on `matches` + `stream_links`, so a new
  ///     match or a fixed line appears in ~1s instead of the 60s poll;
  ///   • a second authoritative match source (Postgres) that is raced against
  ///     the Cloudflare API when a network blocks one route;
  ///   • channel group ordering (`channel_group_order`);
  ///   • the cloud Daily Picks feed written by n8n.
  ///
  /// Every call is guarded, so the app still runs if the project is
  /// unreachable — you just lose freshness and cloud picks. Pass empty
  /// defines (`SUPABASE_URL=""`) to disable it entirely.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://woggzixprvyjnfjzsglz.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O',
  );

  static bool get supabaseEnabled =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Shown in diagnostics/More so the operator can see which project is live.
  static String get supabaseLabel {
    if (!supabaseEnabled) return 'disabled (local only)';
    final uri = Uri.tryParse(supabaseUrl);
    return uri?.host ?? supabaseUrl;
  }

  /// Dedicated Supabase project for Noellyne Bet Daily Picks & Settled Results
  /// written by the n8n Hermes pipeline (kept separate from the live stream DB
  /// so stream feeds stay independent). Only the public read-only publishable
  /// key lives in the app — all write keys stay on the n8n server.
  static const picksSupabaseUrl = String.fromEnvironment(
    'PICKS_SUPABASE_URL',
    defaultValue: 'https://tahigoqhuyxedhmeqhnp.supabase.co',
  );

  static const picksSupabaseAnonKey = String.fromEnvironment(
    'PICKS_SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_o2i64llO0OwnaUMD5NUEAQ_ARb4R7T5',
  );

  static bool get picksSupabaseEnabled =>
      picksSupabaseUrl.trim().isNotEmpty &&
      picksSupabaseAnonKey.trim().isNotEmpty;

  static String get picksSupabaseLabel {
    if (!picksSupabaseEnabled) return 'disabled';
    final uri = Uri.tryParse(picksSupabaseUrl);
    return uri?.host ?? picksSupabaseUrl;
  }

  /// n8n webhook that powers the in-app Noellyne AI chat. All LLM API keys
  /// (Groq, Gemini, OpenRouter) stay strictly server-side on n8n — zero API
  /// secrets are bundled into the app.
  static const aiChatWebhook = String.fromEnvironment(
    'AI_CHAT_WEBHOOK',
    defaultValue: 'https://mwijay.duckdns.org/webhook/noellyne-ai-chat',
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
