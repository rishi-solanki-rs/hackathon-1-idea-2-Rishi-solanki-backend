-- M005 card catalogue (additive, public read-only). Terms are VERIFIED only with an official source and
-- a check date; everything else is UNKNOWN and asked from the user.

create table public.card_products (
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  name text not null,
  issuer text not null,
  country char(2) not null check (country ~ '^[A-Z]{2}$'),
  program text not null references public.loyalty_programs (id),
  earn jsonb not null check (jsonb_typeof(earn) = 'array'),
  annual_fee_eur numeric(10, 2),
  annual_fee_status text not null check (annual_fee_status in ('VERIFIED', 'USER_ENTERED', 'ILLUSTRATIVE', 'CONFLICTING', 'UNKNOWN')),
  notes text[] not null default '{}',
  source_url text not null check (source_url like 'https://%'),
  checked_at date not null,
  check (annual_fee_status <> 'VERIFIED' or annual_fee_eur is not null),
  check (annual_fee_status <> 'UNKNOWN' or annual_fee_eur is null)
);

alter table public.card_products enable row level security;
revoke all on table public.card_products from anon, authenticated;
grant select on table public.card_products to anon, authenticated;
create policy "card products are public" on public.card_products for select to anon, authenticated using (true);
