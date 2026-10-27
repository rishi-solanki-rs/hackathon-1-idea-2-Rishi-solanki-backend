-- DB-007..014: one user can never read, change or reference another user's rows.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'user.a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'user.b@example.com');

create function pg_temp.act_as(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid::text, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

-- User A creates data.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$
  insert into public.trips (id, user_id, title, cabin, adults, objective)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Asia loop', 'economy', 1, 'B_ECONOMIC_COST');
  insert into public.trip_legs (trip_id, user_id, position, origin, destination, depart_date)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 0, 'MAD', 'PEK', '2027-04-01');
  insert into public.loyalty_balances (user_id, program_id, points)
  values ('11111111-1111-1111-1111-111111111111', 'iberia_club', 30000);
$$, 'user A can create their own trip, leg and balance');
select is((select count(*)::int from public.trips), 1, 'user A sees their trip');

-- User B tries to reach it.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.trips), 0, 'user B cannot see A''s trips');
select is((select count(*)::int from public.trip_legs), 0, 'user B cannot see A''s legs');
select is((select count(*)::int from public.loyalty_balances), 0, 'user B cannot see A''s balances');

create temp table b_updated as select 1 as n from (select 1) s where false;
with u as (update public.trips set title = 'changed' returning 1) insert into b_updated select 1 from u;
select is((select count(*)::int from b_updated), 0, 'user B cannot update A''s trip');

create temp table b_deleted as select 1 as n from (select 1) s where false;
with d as (delete from public.loyalty_balances returning 1) insert into b_deleted select 1 from d;
select is((select count(*)::int from b_deleted), 0, 'user B cannot delete A''s balances');

select throws_ok($$
  insert into public.trips (user_id, title, cabin, adults, objective)
  values ('11111111-1111-1111-1111-111111111111', 'spoof', 'economy', 1, 'B_ECONOMIC_COST') $$,
  '42501', null, 'user B cannot create a trip owned by A');

select throws_ok($$
  insert into public.trip_legs (trip_id, user_id, position, origin, destination, depart_date)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 1, 'PEK', 'PVG', '2027-04-05') $$,
  '23503', null, 'user B cannot attach a leg to A''s trip (composite foreign key)');

select throws_ok($$
  insert into public.airports (iata, name, city, country, tz, lat, lon)
  values ('ZZZ', 'Nowhere', 'Nowhere', 'ES', 'Europe/Madrid', 0, 0) $$,
  '42501', null, 'users cannot write the catalogue');
select is((select count(*)::int from public.airports), 31, 'users can read the catalogue');

-- Back as A: data is intact.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select title from public.trips), 'Asia loop', 'A''s trip was not changed by B');
select is((select points from public.loyalty_balances)::int, 30000, 'A''s balance was not deleted by B');

-- Anonymous visitors get nothing.
reset role;
set local role anon;
select throws_ok($$ select count(*) from public.trips $$, '42501', null, 'anon cannot read trips at all');

reset role;
select * from finish();
rollback;
