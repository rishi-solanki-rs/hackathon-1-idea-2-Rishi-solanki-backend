-- M002 user-owned data for AUTH_MODE=supabase (doc 03 TBL-10..33, scoped to implemented features).
-- Every row carries user_id; child rows use a composite FK (parent_id, user_id) so a row can never
-- point at another user's parent. RLS uses (select auth.uid()) for per-statement evaluation.

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 80),
  created_at timestamptz not null default now()
);

create table public.loyalty_balances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  program_id text not null references public.loyalty_programs (id),
  points bigint not null check (points between 0 and 50000000),
  eur_per_point numeric(8, 5) check (eur_per_point is null or eur_per_point between 0 and 1),
  as_of date not null default current_date,
  updated_at timestamptz not null default now(),
  unique (user_id, program_id)
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id text check (client_id is null or char_length(client_id) <= 64),
  title text not null check (char_length(title) between 1 and 120),
  cabin text not null check (cabin in ('economy', 'premium_economy', 'business', 'first')),
  adults integer not null check (adults between 1 and 9),
  objective text not null check (objective in ('A_CASH_TODAY', 'B_ECONOMIC_COST')),
  created_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, client_id)
);

create table public.trip_legs (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  position integer not null check (position between 0 and 5),
  origin char(3) not null references public.airports (iata),
  destination char(3) not null references public.airports (iata),
  depart_date date not null,
  foreign key (trip_id, user_id) references public.trips (id, user_id) on delete cascade,
  unique (trip_id, position),
  check (origin <> destination)
);
create index trip_legs_user_idx on public.trip_legs (user_id);

-- Test bookings are an immutable log: insert and read only, one row per idempotency key.
create table public.test_bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  idempotency_key text not null check (idempotency_key ~ '^[A-Za-z0-9-]{16,64}$'),
  offer_ref text not null check (char_length(offer_ref) <= 200),
  mode text not null check (mode in ('SIMULATED', 'DUFFEL_TEST')),
  reference text not null,
  total_minor bigint not null check (total_minor >= 0),
  currency char(3) not null default 'EUR',
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create table public.guest_migrations (
  user_id uuid not null references auth.users (id) on delete cascade,
  migration_id uuid not null,
  counts jsonb not null default '{}'::jsonb,
  completed_at timestamptz not null default now(),
  primary key (user_id, migration_id)
);

alter table public.profiles enable row level security;
alter table public.loyalty_balances enable row level security;
alter table public.trips enable row level security;
alter table public.trip_legs enable row level security;
alter table public.test_bookings enable row level security;
alter table public.guest_migrations enable row level security;

-- Explicit grants: anon gets nothing; authenticated gets only what each table needs.
revoke all on table public.profiles, public.loyalty_balances, public.trips, public.trip_legs,
  public.test_bookings, public.guest_migrations from anon, authenticated;
grant select, insert, update, delete on table public.profiles, public.loyalty_balances, public.trips,
  public.trip_legs to authenticated;
grant select, insert on table public.test_bookings, public.guest_migrations to authenticated;

-- Owner-only policies.
create policy "own profile" on public.profiles for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own balances" on public.loyalty_balances for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own trips" on public.trips for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own trip legs" on public.trip_legs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "read own test bookings" on public.test_bookings for select to authenticated
  using (user_id = (select auth.uid()));
create policy "insert own test bookings" on public.test_bookings for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "read own migrations" on public.guest_migrations for select to authenticated
  using (user_id = (select auth.uid()));
create policy "insert own migrations" on public.guest_migrations for insert to authenticated
  with check (user_id = (select auth.uid()));
