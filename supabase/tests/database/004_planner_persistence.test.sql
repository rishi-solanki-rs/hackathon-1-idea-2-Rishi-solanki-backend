-- DB-019..028: planner documents and plan history are private, bounded and immutable where intended.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

select is((select count(*)::int from public.card_products), 5, 'seed: 5 card products');
select is((select count(*)::int from public.card_products where annual_fee_status = 'UNKNOWN' and annual_fee_eur is not null), 0, 'unknown fees carry no value');
select throws_ok($$ insert into public.card_products (id, name, issuer, country, program, earn, annual_fee_status, source_url, checked_at)
  values ('x_card', 'X', 'X', 'ES', 'iberia_club', '[]', 'VERIFIED', 'https://example.org', '2026-10-27') $$, '23514', null, 'a VERIFIED fee needs a value');

insert into auth.users (id, email) values
  ('aaaaaaaa-1111-1111-1111-111111111111', null),
  ('bbbbbbbb-2222-2222-2222-222222222222', null);

create function pg_temp.act_as(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid::text, 'role', 'authenticated', 'is_anonymous', true)::text, true);
$$;

select ok(not has_table_privilege('anon', 'public.planner_profiles', 'SELECT'), 'anon cannot read planner profiles');
select ok(not has_table_privilege('anon', 'public.plans', 'INSERT'), 'anon cannot write plans');
select ok(not has_table_privilege('authenticated', 'public.plans', 'UPDATE'), 'plans cannot be edited');

set local role authenticated;
select pg_temp.act_as('aaaaaaaa-1111-1111-1111-111111111111');
select lives_ok($$
  insert into public.planner_profiles (user_id, draft) values ('aaaaaaaa-1111-1111-1111-111111111111', '{"profile":{"balances":[{"program":"iberia_club","points":30000}]}}');
  insert into public.plans (user_id, inputs_hash, engine_version, verdict, result)
  values ('aaaaaaaa-1111-1111-1111-111111111111', 'abcd1234', 'plan-2026.10.27', 'CASH_BETTER', '{"ok":true}');
$$, 'an anonymous user can save their own planner profile and a plan');
select lives_ok($$
  insert into public.planner_profiles (user_id, draft) values ('aaaaaaaa-1111-1111-1111-111111111111', '{"v":2}')
  on conflict (user_id) do update set draft = excluded.draft, updated_at = now()
$$, 'upsert updates the same user''s document');
select is((select draft->>'v' from public.planner_profiles), '2', 'the document was updated in place');
select throws_ok($$
  insert into public.plans (user_id, inputs_hash, engine_version, verdict, result)
  values ('aaaaaaaa-1111-1111-1111-111111111111', 'abcd1234', 'plan-2026.10.27', 'CASH_BETTER', '{}') $$,
  '23505', null, 'the same inputs are stored once');
select throws_ok($$
  insert into public.plans (user_id, inputs_hash, engine_version, verdict, result)
  values ('aaaaaaaa-1111-1111-1111-111111111111', 'efgh5678', 'v', 'BOOK_IT_ALL', '{}') $$,
  '23514', null, 'only known verdicts are accepted');
select throws_ok($$ insert into public.planner_profiles (user_id, draft) values ('aaaaaaaa-1111-1111-1111-111111111111', '[]') on conflict (user_id) do update set draft = excluded.draft $$,
  '23514', null, 'the document must be a JSON object');

select pg_temp.act_as('bbbbbbbb-2222-2222-2222-222222222222');
select is((select count(*)::int from public.planner_profiles), 0, 'user B cannot see A''s planner profile');
select is((select count(*)::int from public.plans), 0, 'user B cannot see A''s plans');
select throws_ok($$ insert into public.planner_profiles (user_id, draft) values ('aaaaaaaa-1111-1111-1111-111111111111', '{}') $$,
  '42501', null, 'user B cannot write a profile owned by A');

select pg_temp.act_as('aaaaaaaa-1111-1111-1111-111111111111');
create temp table a_deleted as select 1 as n from (select 1) s where false;
with d as (delete from public.plans returning 1) insert into a_deleted select 1 from d;
select is((select count(*)::int from a_deleted), 1, 'a user can delete their own plan history (clear my data)');

reset role;
select * from finish();
rollback;
