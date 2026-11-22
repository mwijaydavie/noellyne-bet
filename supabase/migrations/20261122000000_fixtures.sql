-- Noellyne Bet: independent multi-source match fixtures, live scores & odds feed.
-- Populated every 15 minutes from EC2/n8n (ESPN + multi-source fallback) so the
-- Home tab always displays today's full Football & NBA slate even before third-party
-- stream servers publish links.

create table if not exists public.fixtures (
  id text primary key,
  event_id text not null,
  sport text not null default 'football' check (sport in ('football', 'basketball')),
  league text not null default 'Football',
  home_team text not null,
  away_team text not null,
  home_logo_url text default '',
  away_logo_url text default '',
  kickoff_at timestamptz not null,
  status text not null default 'scheduled',
  is_live boolean not null default false,
  home_score int,
  away_score int,
  clock text default '',
  odds_home numeric(6, 2),
  odds_draw numeric(6, 2),
  odds_away numeric(6, 2),
  odds_summary text default '',
  source text not null default 'espn-multi',
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

create index if not exists fixtures_active_kickoff_idx
  on public.fixtures (is_active, kickoff_at asc);

alter table public.fixtures enable row level security;

drop policy if exists "fixtures public read" on public.fixtures;
create policy "fixtures public read"
  on public.fixtures
  for select
  using (is_active = true);

grant usage on schema public to anon, authenticated;
grant select on public.fixtures to anon, authenticated;
grant all on public.fixtures to service_role;

notify pgrst, 'reload schema';
