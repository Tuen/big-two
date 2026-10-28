-- v1.6 seat handover.
-- Only Exit frees a seat during a game. A dropped connection does not, and there is no timeout.
-- The score name on the seat stays. A watcher or a computer may sit in it.
-- Watchers keep the time they started watching, so the first one is offered the seat.

alter table public.seats
  add column if not exists owner_name text,
  add column if not exists stand_in text check (stand_in in ('watcher', 'computer')),
  add column if not exists stand_in_name text,
  add column if not exists stand_in_joined_at timestamptz;

update public.seats
set owner_name = display_name
where owner_name is null;

alter table public.table_viewers
  add column if not exists joined_at timestamptz not null default now();

alter table public.table_messages
  add column if not exists notice boolean not null default false;

alter table public.hands
  add column if not exists stand_ins jsonb not null default '[null,null,null,null]'::jsonb;

alter table public.hand_results
  add column if not exists stand_ins jsonb not null default '[]'::jsonb;

alter table public.game_tables
  add column if not exists host_name text;

-- While the original player is sitting, the score name follows a lobby rename.
-- A stand-in must not replace that name.
create or replace function public.seats_keep_owner_name()
returns trigger
language plpgsql
as $$
begin
  if new.stand_in is null then
    new.owner_name := new.display_name;
  elsif new.owner_name is null or new.owner_name = '' then
    new.owner_name := new.display_name;
  end if;
  return new;
end;
$$;

drop trigger if exists seats_keep_owner_name on public.seats;
create trigger seats_keep_owner_name
before insert or update on public.seats
for each row execute function public.seats_keep_owner_name();

create or replace function public.append_stand_in(current jsonb, seat int, who text)
returns jsonb
language plpgsql
immutable
as $$
declare
  slot jsonb;
  names jsonb;
begin
  if current is null or jsonb_typeof(current) is distinct from 'array' then
    current := '[null,null,null,null]'::jsonb;
  end if;
  while jsonb_array_length(current) < 4 loop
    current := current || 'null'::jsonb;
  end loop;
  slot := current -> seat;
  if slot is null or jsonb_typeof(slot) = 'null' then
    names := '[]'::jsonb;
  else
    names := coalesce(slot -> 'who', '[]'::jsonb);
    if jsonb_typeof(names) is distinct from 'array' then
      names := '[]'::jsonb;
    end if;
  end if;
  if not names ? who then
    names := names || to_jsonb(who);
  end if;
  slot := jsonb_build_object('played', true, 'who', names);
  return jsonb_set(current, array[seat::text], slot, true);
end;
$$;

-- Exit. Opening lobby: the seat becomes empty. During a game: the earliest
-- watcher takes it, or a computer does. The turn, cards, and score name stay.
create or replace function public.exit_seat(p_table uuid, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_round int;
  v_host uuid;
  v_seat public.seats%rowtype;
  v_game boolean;
  v_watcher public.table_viewers%rowtype;
  v_leaver text;
  v_notice text;
  v_who text;
  v_taker text;
  v_hand uuid;
  v_hand_status text;
begin
  select status, round_number, host_id
    into v_status, v_round, v_host
  from public.game_tables
  where id = p_table
  for update;

  if v_status is null then
    return jsonb_build_object('kind', 'absent');
  end if;

  select * into v_seat
  from public.seats
  where table_id = p_table and user_id = p_user
  for update;

  if not found then
    delete from public.table_viewers
    where table_id = p_table and user_id = p_user;
    if found then
      return jsonb_build_object('kind', 'watching');
    end if;
    return jsonb_build_object('kind', 'absent');
  end if;

  if v_seat.is_bot and v_seat.stand_in is null then
    return jsonb_build_object('kind', 'absent');
  end if;

  v_game := v_status is distinct from 'lobby'
    or exists (select 1 from public.hands where table_id = p_table);

  if not v_game then
    delete from public.seats
    where table_id = p_table and user_id = p_user;
    if v_host = p_user then
      update public.game_tables
      set host_id = coalesce((
        select s.user_id
        from public.seats s
        where s.table_id = p_table and s.is_bot = false
        order by s.seat_index
        limit 1
      ), host_id)
      where id = p_table;
    end if;
    return jsonb_build_object('kind', 'lobby');
  end if;

  if v_host = p_user then
    update public.game_tables
    set host_name = coalesce(host_name, v_seat.owner_name, v_seat.display_name)
    where id = p_table;
  end if;

  -- Same 20 second window as the app's watcher list. A closed app is not waiting.
  select * into v_watcher
  from public.table_viewers
  where table_id = p_table
    and last_seen > now() - interval '20 seconds'
  order by joined_at asc, user_id asc
  limit 1
  for update;

  if found then
    v_who := v_watcher.display_name;
    v_taker := 'watcher';
    delete from public.table_viewers
    where table_id = p_table and user_id = v_watcher.user_id;

    update public.seats
    set user_id = v_watcher.user_id,
        is_bot = false,
        bot_difficulty = 'normal',
        stand_in = 'watcher',
        stand_in_name = v_watcher.display_name,
        stand_in_joined_at = v_watcher.joined_at,
        last_seen = now()
    where table_id = p_table and seat_index = v_seat.seat_index;
  else
    v_who := 'computer';
    v_taker := 'computer';
    update public.seats
    set user_id = gen_random_uuid(),
        is_bot = true,
        bot_difficulty = 'normal',
        stand_in = 'computer',
        stand_in_name = 'computer',
        stand_in_joined_at = null,
        last_seen = now()
    where table_id = p_table and seat_index = v_seat.seat_index;
  end if;

  v_leaver := coalesce(
    case when v_seat.stand_in is not null then v_seat.stand_in_name else null end,
    v_seat.owner_name,
    v_seat.display_name
  );
  if v_taker = 'computer' then
    v_notice := v_leaver || ' left. A computer took their seat.';
  else
    v_notice := v_leaver || ' left. ' || v_who || ' took their seat.';
  end if;

  select id, status into v_hand, v_hand_status
  from public.hands
  where table_id = p_table
  order by round_number desc, hand_number desc
  limit 1;

  if v_hand_status = 'playing' then
    update public.hands
    set stand_ins = public.append_stand_in(stand_ins, v_seat.seat_index, v_who)
    where id = v_hand;
  end if;

  insert into public.table_messages (table_id, round_number, display_name, viewer, body, notice)
  values (p_table, v_round, 'Table', false, v_notice, true);

  return jsonb_build_object(
    'kind', 'handover',
    'taker', v_taker,
    'notice', v_notice,
    'seat', v_seat.seat_index
  );
end;
$$;

-- The person who pressed Exit comes back with the same name, ignoring capitals.
-- A watcher who was sitting returns to the queue at the place they started.
create or replace function public.reclaim_seat(p_table uuid, p_user uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round int;
  v_seat public.seats%rowtype;
  v_owner text;
  v_notice text;
begin
  select round_number into v_round
  from public.game_tables
  where id = p_table
  for update;

  if not found then
    return jsonb_build_object('reclaimed', false);
  end if;

  if exists (
    select 1 from public.seats
    where table_id = p_table and user_id = p_user
  ) then
    return jsonb_build_object('reclaimed', false, 'already', true);
  end if;

  select * into v_seat
  from public.seats
  where table_id = p_table
    and stand_in is not null
    and lower(coalesce(owner_name, display_name)) = lower(btrim(p_name))
  order by seat_index
  limit 1
  for update;

  if not found then
    return jsonb_build_object('reclaimed', false);
  end if;

  delete from public.table_viewers
  where table_id = p_table and user_id = p_user;

  if v_seat.stand_in = 'watcher' then
    insert into public.table_viewers (table_id, user_id, display_name, last_seen, joined_at)
    values (
      p_table,
      v_seat.user_id,
      coalesce(v_seat.stand_in_name, 'Watcher'),
      now(),
      coalesce(v_seat.stand_in_joined_at, now())
    )
    on conflict (table_id, user_id) do update
      set display_name = excluded.display_name,
          last_seen = excluded.last_seen,
          joined_at = excluded.joined_at;
  end if;

  v_owner := coalesce(v_seat.owner_name, v_seat.display_name);

  update public.seats
  set user_id = p_user,
      is_bot = false,
      bot_difficulty = 'normal',
      stand_in = null,
      stand_in_name = null,
      stand_in_joined_at = null,
      last_seen = now(),
      display_name = v_owner
  where table_id = p_table and seat_index = v_seat.seat_index;

  update public.game_tables
  set host_id = p_user
  where id = p_table
    and host_name is not null
    and lower(host_name) = lower(btrim(p_name));

  v_notice := v_owner || ' is back in their seat.';

  insert into public.table_messages (table_id, round_number, display_name, viewer, body, notice)
  values (p_table, v_round, 'Table', false, v_notice, true);

  return jsonb_build_object(
    'reclaimed', true,
    'seat', v_seat.seat_index,
    'notice', v_notice
  );
end;
$$;

revoke all on function public.seats_keep_owner_name() from public, anon, authenticated;
revoke all on function public.append_stand_in(jsonb, int, text) from public, anon, authenticated;
revoke all on function public.exit_seat(uuid, uuid) from public, anon, authenticated;
revoke all on function public.reclaim_seat(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.append_stand_in(jsonb, int, text) to service_role;
grant execute on function public.exit_seat(uuid, uuid) to service_role;
grant execute on function public.reclaim_seat(uuid, uuid, text) to service_role;

-- Shuffle must keep the score name and any stand-in.
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
  kept jsonb;
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

  select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into kept
  from public.seats s
  where s.table_id = p_table;

  delete from public.seats
  where table_id = p_table
    and user_id = any(current_ids);

  insert into public.seats (
    table_id, seat_index, user_id, display_name, last_seen, is_bot, bot_difficulty,
    owner_name, stand_in, stand_in_name, stand_in_joined_at
  )
  select
    p_table,
    o.ord::int - 1,
    (item->>'user_id')::uuid,
    item->>'display_name',
    (item->>'last_seen')::timestamptz,
    coalesce((item->>'is_bot')::boolean, false),
    coalesce(item->>'bot_difficulty', 'normal'),
    coalesce(item->>'owner_name', item->>'display_name'),
    nullif(item->>'stand_in', ''),
    nullif(item->>'stand_in_name', ''),
    nullif(item->>'stand_in_joined_at', '')::timestamptz
  from unnest(wanted) with ordinality as o(user_id, ord)
  join lateral jsonb_array_elements(kept) as item
    on (item->>'user_id')::uuid = o.user_id
  where o.user_id is not null;
exception
  when unique_violation then
    raise exception 'That seating does not match the players here';
end;
$$;

revoke all on function public.reorder_seats(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.reorder_seats(uuid, jsonb) to service_role;

-- One read, now including watcher names in the order they sat down to watch.
create or replace function public.load_table_bundle(p_table uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select *
    from public.hands
    where table_id = p_table
    order by round_number desc, hand_number desc
    limit 1
  )
  select jsonb_build_object(
    'table', (select to_jsonb(t) from public.game_tables t where t.id = p_table),
    'seats', (
      select coalesce(jsonb_agg(to_jsonb(s) order by s.seat_index), '[]'::jsonb)
      from public.seats s
      where s.table_id = p_table
    ),
    'hand', (select to_jsonb(h) from latest h),
    'secret', (
      select hs.deck
      from public.hand_secrets hs
      join latest on latest.id = hs.hand_id
    ),
    'events', (
      select coalesce(jsonb_agg(to_jsonb(e) order by e.seq), '[]'::jsonb)
      from public.events e
      join latest on latest.id = e.hand_id
    ),
    'viewers', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'user_id', v.user_id,
            'last_seen', v.last_seen,
            'display_name', v.display_name,
            'joined_at', v.joined_at
          )
          order by v.joined_at, v.user_id
        ),
        '[]'::jsonb
      )
      from public.table_viewers v
      where v.table_id = p_table
    ),
    'messages', (
      select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]'::jsonb)
      from (
        select id, display_name, viewer, body, notice
        from public.table_messages
        where table_id = p_table
          and round_number = (select round_number from public.game_tables where id = p_table)
        order by id desc
        limit 40
      ) m
    ),
    'results', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.round_number, r.hand_number), '[]'::jsonb)
      from public.hand_results r
      where r.table_id = p_table
    )
  );
$$;

revoke all on function public.load_table_bundle(uuid) from public, anon, authenticated;
grant execute on function public.load_table_bundle(uuid) to service_role;

notify pgrst, 'reload schema';
