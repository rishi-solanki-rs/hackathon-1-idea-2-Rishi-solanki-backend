-- DB-015..018: test bookings are immutable and idempotent; guest migration runs exactly once.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'user.c@example.com');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);

select lives_ok($$
  insert into public.test_bookings (user_id, idempotency_key, offer_ref, mode, reference, total_minor)
  values ('33333333-3333-3333-3333-333333333333', 'key-aaaaaaaaaaaaaaaa', 'fixture:x:exact', 'SIMULATED', 'SIM-ABC123', 70200) $$,
  'a test booking can be recorded');
select throws_ok($$
  insert into public.test_bookings (user_id, idempotency_key, offer_ref, mode, reference, total_minor)
  values ('33333333-3333-3333-3333-333333333333', 'key-aaaaaaaaaaaaaaaa', 'fixture:x:exact', 'SIMULATED', 'SIM-OTHER', 70200) $$,
  '23505', null, 'the same idempotency key cannot book twice');
select throws_ok($$ update public.test_bookings set total_minor = 1 $$, '42501', null, 'test bookings cannot be edited');
select throws_ok($$
  insert into public.test_bookings (user_id, idempotency_key, offer_ref, mode, reference, total_minor)
  values ('33333333-3333-3333-3333-333333333333', 'key-bbbbbbbbbbbbbbbb', 'x', 'LIVE', 'R', 1) $$,
  '23514', null, 'only SIMULATED or DUFFEL_TEST bookings are allowed');

select is(
  public.migrate_guest_data(
    '44444444-4444-4444-4444-444444444444',
    '[{"program":"iberia_club","points":120000},{"program":"amex_mr_es","points":15000}]',
    '[{"clientId":"t1","title":"Chile","cabin":"business","adults":1,"legs":[{"origin":"MAD","destination":"SCL","date":"2027-02-10"}]}]'),
  '{"balances": 2, "trips": 1, "status": "done"}'::jsonb,
  'first guest migration copies balances and trips');
select is(
  public.migrate_guest_data(
    '44444444-4444-4444-4444-444444444444',
    '[{"program":"iberia_club","points":999}]',
    '[{"clientId":"t2","title":"Other","cabin":"economy","adults":1,"legs":[]}]'),
  '{"balances": 2, "trips": 1, "status": "already_done"}'::jsonb,
  'repeating the same migration id changes nothing');
select is((select count(*)::int from public.trips), 1, 'no duplicate trips after a repeated migration');
select is((select points from public.loyalty_balances where program_id = 'iberia_club')::int, 120000, 'balances were not overwritten by the repeat');
select is((select count(*)::int from public.trip_legs), 1, 'trip legs were copied');

select throws_ok(
  $$ select public.migrate_guest_data('55555555-5555-5555-5555-555555555555', '{}', '[]') $$,
  '22023', null, 'malformed payloads are rejected');

select set_config('request.jwt.claims', '', true);
select throws_ok(
  $$ select public.migrate_guest_data('66666666-6666-6666-6666-666666666666', '[]', '[]') $$,
  '42501', null, 'guest migration requires a signed-in user');

reset role;
select * from finish();
rollback;
