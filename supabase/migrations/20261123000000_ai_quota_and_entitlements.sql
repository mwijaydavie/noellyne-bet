-- Noellyne Bet: persistent anti-abuse AI quota ledger & future-ready subscription entitlements.
-- Supports hardware-stable device fingerprints (survives Clear Cache / Clear Data / Reinstall),
-- signed-in Google accounts (10/day), guests (3/day), future Pro paid users, and VIP Owner bypass.

create table if not exists public.ai_usage_daily (
  subject_key text not null,
  usage_date date not null,
  count int not null default 0,
  tier text not null default 'guest',
  last_ip text default '',
  updated_at timestamptz not null default now(),
  primary key (subject_key, usage_date)
);

alter table public.ai_usage_daily enable row level security;
revoke all on public.ai_usage_daily from anon, authenticated;
grant all on public.ai_usage_daily to service_role;

create table if not exists public.user_entitlements (
  email text primary key,
  plan text not null default 'free' check (plan in ('free', 'pro', 'vip_owner')),
  daily_limit int not null default 10,
  expires_at timestamptz,
  payment_ref text default '',
  notes text default '',
  updated_at timestamptz not null default now()
);

alter table public.user_entitlements enable row level security;

drop policy if exists "user_entitlements self read" on public.user_entitlements;
create policy "user_entitlements self read"
  on public.user_entitlements
  for select
  to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

revoke all on public.user_entitlements from anon;
grant select on public.user_entitlements to authenticated;
grant all on public.user_entitlements to service_role;

-- Seed VIP Owner emails (UNLIMITED: daily_limit = -1)
insert into public.user_entitlements (email, plan, daily_limit, notes)
values
  ('davidbyanmwijage@gmail.com', 'vip_owner', -1, 'Founder / Engineering Lead'),
  ('mwijaydavie@gmail.com', 'vip_owner', -1, 'Founder / Engineering Lead'),
  ('faidahq.tz@gmail.com', 'vip_owner', -1, 'Altraware Founder Account'),
  ('altrawaretechnology@gmail.com', 'vip_owner', -1, 'Altraware Technology Official')
on conflict (email) do update
  set plan = excluded.plan,
      daily_limit = excluded.daily_limit,
      updated_at = now();

-- Atomic quota check + increment across ALL identity keys (hardware fingerprint + user id).
-- When p_limit < 0 (VIP Owner / Unlimited Pro), returns allowed=true without incrementing.
create or replace function public.consume_ai_quota(
  p_keys text[],
  p_date date,
  p_limit int,
  p_tier text default 'guest',
  p_ip text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keys text[];
  v_max int := 0;
  v_next int := 0;
  v_key text;
begin
  if p_limit < 0 then
    return jsonb_build_object(
      'allowed', true,
      'unlimited', true,
      'used', 0,
      'limit', -1,
      'remaining', -1,
      'tier', p_tier
    );
  end if;

  select array_agg(distinct trim(k))
    into v_keys
  from unnest(coalesce(p_keys, array[]::text[])) as k
  where trim(coalesce(k, '')) <> '';

  if v_keys is null or array_length(v_keys, 1) is null then
    v_keys := array['ip:' || coalesce(nullif(trim(p_ip), ''), 'unknown')];
  end if;

  -- Lock existing rows for these keys on p_date to prevent race bursts
  select coalesce(max(count), 0)
    into v_max
  from public.ai_usage_daily
  where usage_date = p_date
    and subject_key = any(v_keys);

  if v_max >= p_limit then
    return jsonb_build_object(
      'allowed', false,
      'unlimited', false,
      'used', v_max,
      'limit', p_limit,
      'remaining', 0,
      'tier', p_tier
    );
  end if;

  v_next := v_max + 1;

  foreach v_key in array v_keys loop
    insert into public.ai_usage_daily (subject_key, usage_date, count, tier, last_ip, updated_at)
    values (v_key, p_date, v_next, p_tier, left(coalesce(p_ip, ''), 64), now())
    on conflict (subject_key, usage_date) do update
      set count = greatest(public.ai_usage_daily.count + 1, excluded.count),
          tier = excluded.tier,
          last_ip = excluded.last_ip,
          updated_at = now();
  end loop;

  return jsonb_build_object(
    'allowed', true,
    'unlimited', false,
    'used', v_next,
    'limit', p_limit,
    'remaining', greatest(0, p_limit - v_next),
    'tier', p_tier
  );
end;
$$;

revoke all on function public.consume_ai_quota(text[], date, int, text, text) from public, anon, authenticated;
grant execute on function public.consume_ai_quota(text[], date, int, text, text) to service_role;

notify pgrst, 'reload schema';
