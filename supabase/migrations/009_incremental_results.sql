-- Repeat reads of a table were shipping every saved hand, including the revealed deck.
-- The first read still returns every hand. A later read passes the last hand the
-- phone already has and gets only what changed: newer hands, that hand again
-- (its score status can still change), and any hand whose score is not finished.
-- A caller that is only playing a move can skip the results list entirely.
-- Same rule as resultIncluded() in supabase/functions/_shared/traffic.ts.

drop function if exists public.load_table_bundle(uuid);

create or replace function public.load_table_bundle(
  p_table uuid,
  p_after_round int default null,
  p_after_hand int default null,
  p_include_results boolean default true
)
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
    'results', case
      when coalesce(p_include_results, true) is false then '[]'::jsonb
      else (
        select coalesce(jsonb_agg(to_jsonb(r) order by r.round_number, r.hand_number), '[]'::jsonb)
        from public.hand_results r
        where r.table_id = p_table
          and (
            p_after_round is null
            or r.round_number > p_after_round
            or (r.round_number = p_after_round and r.hand_number > coalesce(p_after_hand, 0))
            or (
              coalesce(p_after_hand, 0) > 0
              and r.round_number = p_after_round
              and r.hand_number = p_after_hand
            )
            or r.webhook_status in ('pending', 'sending', 'failed')
          )
      )
    end
  );
$$;

revoke all on function public.load_table_bundle(uuid, int, int, boolean) from public, anon, authenticated;
grant execute on function public.load_table_bundle(uuid, int, int, boolean) to service_role;

notify pgrst, 'reload schema';
