-- A pause may change only its own setting. A stale copy of the whole settings
-- object must not put an old pause back, or wipe a newer one.

create or replace function public.patch_table_setting(
  p_table uuid,
  p_key text,
  p_value jsonb,
  p_match text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_key not in ('hold', 'botWaitUntil') then
    raise exception 'That setting cannot be patched';
  end if;
  if p_value is null then
    update public.game_tables
    set settings = settings - p_key
    where id = p_table
      and (
        p_match is null
        or p_match = ''
        or settings -> p_key ->> 'at' = p_match
        or settings ->> p_key = p_match
      );
  else
    update public.game_tables
    set settings = jsonb_set(coalesce(settings, '{}'::jsonb), array[p_key], p_value, true)
    where id = p_table;
  end if;
end;
$$;

revoke all on function public.patch_table_setting(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.patch_table_setting(uuid, text, jsonb, text) to service_role;

create table if not exists public.move_log (
  id bigint generated always as identity primary key,
  table_code text not null,
  hand_number int,
  player text not null,
  kind text not null,
  table_cards text not null default '',
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.move_log enable row level security;
revoke all on public.move_log from anon, authenticated;
