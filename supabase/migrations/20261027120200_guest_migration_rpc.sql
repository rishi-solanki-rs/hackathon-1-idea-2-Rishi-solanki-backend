-- M003 migrate_guest_data: copies a guest's browser wallet and trips into their account, exactly once
-- per migration_id (doc 03 RPC migrate_guest_data, doc 06 guest migration). Runs as the caller
-- (security invoker) so every write is checked by RLS.

create or replace function public.migrate_guest_data(
  p_migration_id uuid,
  p_balances jsonb default '[]'::jsonb,
  p_trips jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_existing jsonb;
  v_balances integer := 0;
  v_trips integer := 0;
  v_trip jsonb;
  v_leg jsonb;
  v_trip_id uuid;
  v_pos integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if jsonb_typeof(p_balances) <> 'array' or jsonb_typeof(p_trips) <> 'array' then
    raise exception 'balances and trips must be arrays' using errcode = '22023';
  end if;

  -- Serialise concurrent calls for the same user and migration.
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || p_migration_id::text, 0));

  select counts into v_existing from public.guest_migrations
  where user_id = v_user and migration_id = p_migration_id;
  if v_existing is not null then
    return v_existing || jsonb_build_object('status', 'already_done');
  end if;

  insert into public.loyalty_balances (user_id, program_id, points)
  select v_user, b ->> 'program', (b ->> 'points')::bigint
  from jsonb_array_elements(p_balances) as b
  on conflict (user_id, program_id) do update set points = excluded.points, updated_at = now();
  get diagnostics v_balances = row_count;

  for v_trip in select * from jsonb_array_elements(p_trips) loop
    insert into public.trips (user_id, client_id, title, cabin, adults, objective)
    values (
      v_user,
      v_trip ->> 'clientId',
      coalesce(v_trip ->> 'title', 'Saved trip'),
      v_trip ->> 'cabin',
      (v_trip ->> 'adults')::integer,
      coalesce(v_trip ->> 'objective', 'B_ECONOMIC_COST')
    )
    on conflict (user_id, client_id) do nothing
    returning id into v_trip_id;

    if v_trip_id is not null then
      v_trips := v_trips + 1;
      v_pos := 0;
      for v_leg in select * from jsonb_array_elements(coalesce(v_trip -> 'legs', '[]'::jsonb)) loop
        insert into public.trip_legs (trip_id, user_id, position, origin, destination, depart_date)
        values (v_trip_id, v_user, v_pos, v_leg ->> 'origin', v_leg ->> 'destination', (v_leg ->> 'date')::date);
        v_pos := v_pos + 1;
      end loop;
    end if;
    v_trip_id := null;
  end loop;

  insert into public.guest_migrations (user_id, migration_id, counts)
  values (v_user, p_migration_id, jsonb_build_object('balances', v_balances, 'trips', v_trips));

  return jsonb_build_object('balances', v_balances, 'trips', v_trips, 'status', 'done');
end;
$$;

revoke all on function public.migrate_guest_data(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.migrate_guest_data(uuid, jsonb, jsonb) to authenticated;
