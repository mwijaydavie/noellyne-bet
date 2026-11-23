-- Noellyne: persistent cloud AI user memory & remote minimum-build update gate.

create table if not exists public.user_ai_memory (
  subject_key text primary key,
  display_name text default '',
  favorite_teams text[] not null default '{}',
  usual_stake_tzs int,
  preferred_sport text default '',
  notes text default '',
  updated_at timestamptz not null default now()
);

alter table public.user_ai_memory enable row level security;
revoke all on public.user_ai_memory from anon, authenticated;
grant all on public.user_ai_memory to service_role;

insert into public.app_config (key, value, description)
values
  (
    'min_supported_build',
    '0',
    'Minimum Android build_number allowed before showing a polite mandatory update screen (set to e.g. 40037 when launching payments)'
  ),
  (
    'update_notice',
    '',
    'Optional Kiswahili/English release notes shown inside the in-app update dialog'
  )
on conflict (key) do nothing;

notify pgrst, 'reload schema';
