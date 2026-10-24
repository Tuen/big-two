-- Host seating changes while the table is in the lobby.
-- The table Edge Function calls this with the service role. Players cannot.

create or replace function public.reorder_seats(p_table uuid, p_order jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  seat_status text;
  wanted uuid[];
  current_ids uuid[];
  old_rows public.seats[];
begin
  if p_order is null or jsonb_typeof(p_order) <> 'array' or jsonb_array_length(p_order) <> 4 then
    raise exception 'Give all four seats';
  end if;

  select status into seat_status
  from public.game_tables
  where id = p_table
  for update;

  if seat_status is null then
    raise exception 'Missing table';
  end if;
  if seat_status is distinct from 'lobby' then
    raise exception 'Seats can change only before a hand is dealt';
  end if;

  wanted := array[
    nullif(p_order ->> 0, '')::uuid,
    nullif(p_order ->> 1, '')::uuid,
    nullif(p_order ->> 2, '')::uuid,
    nullif(p_order ->> 3, '')::uuid
  ];

  if (
    select count(*) from unnest(wanted) as seat_id where seat_id is not null
  ) <> (
    select count(distinct seat_id) from unnest(wanted) as seat_id where seat_id is not null
  ) then
    raise exception 'That seating does not match the players here';
  end if;

  perform 1
  from public.seats
  where table_id = p_table
  for update;

  select coalesce(array_agg(user_id order by user_id), '{}'::uuid[])
    into current_ids
  from public.seats
  where table_id = p_table;

  if (
    select coalesce(array_agg(seat_id order by seat_id), '{}'::uuid[])
    from unnest(wanted) as seat_id
    where seat_id is not null
  ) is distinct from current_ids then
    raise exception 'That seating does not match the players here';
  end if;

  select coalesce(array_agg(s), '{}'::public.seats[])
    into old_rows
  from public.seats s
  where s.table_id = p_table;

  delete from public.seats
  where table_id = p_table
    and user_id = any(current_ids);

  insert into public.seats (table_id, seat_index, user_id, display_name, last_seen)
  select p_table, o.ord::int - 1, r.user_id, r.display_name, r.last_seen
  from unnest(wanted) with ordinality as o(user_id, ord)
  join unnest(old_rows) as r(table_id, seat_index, user_id, display_name, last_seen)
    on r.user_id = o.user_id
  where o.user_id is not null;
exception
  when unique_violation then
    raise exception 'That seating does not match the players here';
end;
$$;

revoke all on function public.reorder_seats(uuid, jsonb) from public;
revoke all on function public.reorder_seats(uuid, jsonb) from anon;
revoke all on function public.reorder_seats(uuid, jsonb) from authenticated;
grant execute on function public.reorder_seats(uuid, jsonb) to service_role;

notify pgrst, 'reload schema';
