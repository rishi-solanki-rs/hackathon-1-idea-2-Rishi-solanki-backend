-- M001 catalogue: public, read-only reference data (doc 03 TBL-01..03).

create table public.airports (
  iata char(3) primary key check (iata ~ '^[A-Z]{3}$'),
  name text not null check (char_length(name) between 2 and 120),
  city text not null check (char_length(city) between 2 and 80),
  country char(2) not null check (country ~ '^[A-Z]{2}$'),
  tz text not null,
  lat numeric(8, 5) not null check (lat between -90 and 90),
  lon numeric(8, 5) not null check (lon between -180 and 180)
);

create table public.loyalty_programs (
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  name text not null,
  unit text not null,
  kind text not null check (kind in ('airline', 'bank', 'fintech')),
  website text not null check (website like 'https://%')
);

create table public.transfer_routes (
  id text primary key,
  from_program text not null references public.loyalty_programs (id),
  to_program text not null references public.loyalty_programs (id),
  ratio_num integer not null check (ratio_num > 0),
  ratio_den integer not null check (ratio_den > 0),
  min_points integer not null check (min_points >= 0),
  increment integer not null check (increment > 0),
  status text not null check (status in ('active', 'suspended')),
  verification text not null check (verification in ('VERIFIED', 'UNVERIFIED', 'ILLUSTRATIVE')),
  max_delay_days integer not null check (max_delay_days >= 0),
  preconditions text[] not null default '{}',
  source_url text check (source_url is null or source_url like 'https://%'),
  checked_at date,
  check (from_program <> to_program),
  -- A rule may only claim VERIFIED with a source and a check date.
  check (verification <> 'VERIFIED' or (source_url is not null and checked_at is not null))
);

create index transfer_routes_to_program_idx on public.transfer_routes (to_program);
create index transfer_routes_from_program_idx on public.transfer_routes (from_program);

alter table public.airports enable row level security;
alter table public.loyalty_programs enable row level security;
alter table public.transfer_routes enable row level security;

-- Explicit grants (no reliance on default privileges).
revoke all on table public.airports, public.loyalty_programs, public.transfer_routes from anon, authenticated;
grant select on table public.airports, public.loyalty_programs, public.transfer_routes to anon, authenticated;

create policy "airports are public" on public.airports for select to anon, authenticated using (true);
create policy "programs are public" on public.loyalty_programs for select to anon, authenticated using (true);
create policy "transfer routes are public" on public.transfer_routes for select to anon, authenticated using (true);
