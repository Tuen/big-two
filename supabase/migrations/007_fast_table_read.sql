-- One read for a table, and one write for an ordinary move.
-- Each separate database call was costing the best part of a second,
-- so a computer turn was taking about twenty.

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
        jsonb_agg(jsonb_build_object('user_id', v.user_id, 'last_seen', v.last_seen)),
        '[]'::jsonb
      )
      from public.table_viewers v
      where v.table_id = p_table
    ),
    'messages', (
      select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]'::jsonb)
      from (
        select id, display_name, viewer, body
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

create or replace function public.save_playing_move(
  p_hand uuid,
  p_seq int,
  p_seat int,
  p_kind text,
  p_cards jsonb,
  p_turn int,
  p_message text,
  p_holdings jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.events (hand_id, seq, seat_index, kind, payload)
  values (p_hand, p_seq, p_seat, p_kind, jsonb_build_object('cards', p_cards));

  update public.hands
  set status = 'playing',
      turn_seat = p_turn,
      turn_started_at = now(),
      last_message = p_message,
      winner_seat = null
  where id = p_hand;

  insert into public.holdings (hand_id, seat_index, cards)
  select p_hand, (item ->> 'seat')::int, item -> 'cards'
  from jsonb_array_elements(p_holdings) as item
  on conflict (hand_id, seat_index) do update set cards = excluded.cards;
end;
$$;

revoke all on function public.save_playing_move(uuid, int, int, text, jsonb, int, text, jsonb) from public, anon, authenticated;
grant execute on function public.save_playing_move(uuid, int, int, text, jsonb, int, text, jsonb) to service_role;
