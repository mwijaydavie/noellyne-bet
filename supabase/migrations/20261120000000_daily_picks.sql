-- Noellyne Bet: structured daily picks written by the n8n betting pipeline.
--
-- n8n contract (POST JSON):
-- {
--   "match": "Arsenal vs Chelsea",
--   "league": "Premier League",
--   "pick": "Arsenal Win & Over 1.5",
--   "odds": 1.85,
--   "confidence": 84,
--   "reasoning": "short AI reasoning",
--   "stream_id": "<matches.id or stream id>",
--   "kickoff_time": "2026-11-20T17:30:00Z",
--   "tags": ["sure2+", "over2.5"],
--   "slip_code": "NLY-8K2F",
--   "status": "published"
-- }
--
-- Auth: n8n calls the `ingest-daily-picks` Edge Function with a shared
-- secret header, OR writes with the service-role key. Viewers only read.

create table if not exists public.daily_picks (
  id uuid primary key default gen_random_uuid(),
  match text not null,
  league text not null default 'Football',
  pick text not null,
  market text,
  odds numeric(6, 2) not null default 0,
  confidence int not null default 0 check (confidence between 0 and 100),
  reasoning text not null default '',
  stream_id text,
  kickoff_time timestamptz,
  tags text[] not null default '{}',
  slip_code text,
  status text not null default 'published'
    check (status in ('draft', 'published', 'settled', 'void')),
  result text check (result in ('won', 'lost', 'void')),
  source text not null default 'n8n',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists daily_picks_feed_idx
  on public.daily_picks (status, kickoff_time);

create index if not exists daily_picks_created_idx
  on public.daily_picks (created_at desc);

-- Dedupe guard for repeated n8n runs (same match + pick + kickoff day).
create unique index if not exists daily_picks_dedupe_idx
  on public.daily_picks (match, pick, (kickoff_time::date))
  where status = 'published';

alter table public.daily_picks enable row level security;

-- Public read of published picks only.
drop policy if exists "daily_picks public read" on public.daily_picks;
create policy "daily_picks public read"
  on public.daily_picks
  for select
  using (status in ('published', 'settled'));

-- Service role (Edge Function / n8n) handles all writes; admins may too.
drop policy if exists "daily_picks admin write" on public.daily_picks;
create policy "daily_picks admin write"
  on public.daily_picks
  for all
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );

create or replace function public.touch_daily_picks_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists daily_picks_touch on public.daily_picks;
create trigger daily_picks_touch
  before update on public.daily_picks
  for each row execute function public.touch_daily_picks_updated_at();

comment on table public.daily_picks is
  'Structured betting picks produced by the Noellyne n8n pipeline and '
  'rendered in the viewer Daily Picks feed.';
