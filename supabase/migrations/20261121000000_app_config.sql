-- Noellyne Bet: remote runtime config table for zero-APK-rebuild server migration
-- and feature toggles, plus explicit PostgREST grants for dedicated Supabase projects
-- where automatic table grants are disabled.

create table if not exists public.app_config (
  key text primary key,
  value text not null,
  description text default '',
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

drop policy if exists "app_config public read" on public.app_config;
create policy "app_config public read"
  on public.app_config
  for select
  using (true);

grant usage on schema public to anon, authenticated;
grant select on public.app_config to anon, authenticated;
grant select on public.daily_picks to anon, authenticated;
grant all on public.app_config to service_role;
grant all on public.daily_picks to service_role;

insert into public.app_config (key, value, description)
values (
  'ai_chat_webhook',
  'https://mwijay.duckdns.org/webhook/noellyne-ai-chat',
  'Active n8n AI Chat webhook URL (update here on VPS migration for zero-APK cutover)'
)
on conflict (key) do nothing;

comment on table public.app_config is
  'Public non-secret runtime endpoints and feature flags read by the Noellyne Bet client.';
