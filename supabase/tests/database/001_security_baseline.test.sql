-- DB-001..006: RLS everywhere, explicit grants, catalogue integrity.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every public table');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and not exists (select 1 from pg_policy p where p.polrelid = c.oid)),
  0, 'every public table has at least one policy');

select ok(has_table_privilege('anon', 'public.airports', 'SELECT'), 'anon can read airports');
select ok(not has_table_privilege('anon', 'public.airports', 'INSERT'), 'anon cannot write airports');
select ok(not has_table_privilege('authenticated', 'public.transfer_routes', 'UPDATE'), 'users cannot change transfer routes');
select ok(not has_table_privilege('authenticated', 'public.loyalty_programs', 'DELETE'), 'users cannot delete programmes');

select ok(not has_table_privilege('anon', 'public.trips', 'SELECT'), 'anon cannot read trips');
select ok(not has_table_privilege('anon', 'public.loyalty_balances', 'SELECT'), 'anon cannot read balances');
select ok(not has_table_privilege('anon', 'public.test_bookings', 'INSERT'), 'anon cannot create test bookings');
select ok(not has_table_privilege('authenticated', 'public.test_bookings', 'UPDATE'), 'test bookings cannot be updated');
select ok(not has_table_privilege('authenticated', 'public.test_bookings', 'DELETE'), 'test bookings cannot be deleted');
select ok(not has_function_privilege('anon', 'public.migrate_guest_data(uuid, jsonb, jsonb)', 'EXECUTE'), 'anon cannot run the guest migration');
select ok(has_function_privilege('authenticated', 'public.migrate_guest_data(uuid, jsonb, jsonb)', 'EXECUTE'), 'signed-in users can run the guest migration');

select is((select count(*)::int from public.airports), 31, 'seed: 31 airports');
select is((select count(*)::int from public.transfer_routes where verification = 'VERIFIED'), 0, 'seed: no transfer rule claims VERIFIED');

select throws_ok(
  $$ insert into public.transfer_routes (id, from_program, to_program, ratio_num, ratio_den, min_points, increment, status, verification, max_delay_days)
     values ('x', 'amex_mr_es', 'iberia_club', 1, 1, 1, 1, 'active', 'VERIFIED', 0) $$,
  '23514', null, 'a rule cannot be VERIFIED without a source and a check date');

select * from finish();
rollback;
