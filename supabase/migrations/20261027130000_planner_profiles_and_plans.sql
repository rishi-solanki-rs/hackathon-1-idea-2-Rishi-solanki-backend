-- M004 planner persistence (additive). One private planner document per user (trip, cards with
-- per-field evidence, balances, spending) plus an append-only log of computed plans.
-- Users are Supabase anonymous or signed-in users; RLS keeps every row private to its owner.

create table public.planner_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  schema_version integer not null default 1 check (schema_version between 1 and 100),
  draft jsonb not null check (jsonb_typeof(draft) = 'object' and octet_length(draft::text) <= 200000),
  updated_at timestamptz not null default now()
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  inputs_hash text not null check (char_length(inputs_hash) between 4 and 64),
  engine_version text not null check (char_length(engine_version) <= 40),
  verdict text not null check (verdict in ('BOOK_CASH_NOW', 'AWARD_WORTH_CHECKING', 'MONITOR_NO_TRANSFER', 'ACCUMULATE_FROM_PLANNED_SPEND', 'CASH_BETTER', 'INSUFFICIENT_BY_DEADLINE', 'TOO_UNCERTAIN')),
  result jsonb not null check (jsonb_typeof(result) = 'object' and octet_length(result::text) <= 400000),
  created_at timestamptz not null default now(),
  unique (user_id, inputs_hash)
);
create index plans_user_created_idx on public.plans (user_id, created_at desc);

alter table public.planner_profiles enable row level security;
alter table public.plans enable row level security;

revoke all on table public.planner_profiles, public.plans from anon, authenticated;
grant select, insert, update, delete on table public.planner_profiles to authenticated;
-- Plans are an immutable history: read, add and delete (for "clear my data"), never edit.
grant select, insert, delete on table public.plans to authenticated;

create policy "own planner profile" on public.planner_profiles for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "read own plans" on public.plans for select to authenticated using (user_id = (select auth.uid()));
create policy "add own plans" on public.plans for insert to authenticated with check (user_id = (select auth.uid()));
create policy "delete own plans" on public.plans for delete to authenticated using (user_id = (select auth.uid()));
