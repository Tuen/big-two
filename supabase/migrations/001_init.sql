-- Big Two. Clients may read their table. Only Edge Functions (the service role) write.
-- hand_secrets holds the shuffled deck and is not readable by players until deck_reveal is set.

create extension if not exists pgcrypto;

create table public.game_tables (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_id uuid not null,
  status text not null default 'lobby' check (status in ('lobby', 'playing', 'hand_end', 'round_end')),
  season int not null default 24,
  round_number int not null default 1,
  settings jsonb not null,
  created_at timestamptz not null default now()
);

create table public.seats (
  table_id uuid not null references public.game_tables (id) on delete cascade,
  seat_index int not null check (seat_index between 0 and 3),
  user_id uuid not null,
  display_name text not null check (char_length(display_name) between 1 and 24),
  last_seen timestamptz not null default now(),
  primary key (table_id, seat_index),
  unique (table_id, user_id)
);

create table public.hands (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references public.game_tables (id) on delete cascade,
  round_number int not null,
  hand_number int not null,
  first_hand boolean not null,
  previous_winner int,
  running_at_start int[] not null,
  commitment text not null,
  deck_reveal text,
  status text not null default 'playing' check (status in ('playing', 'complete')),
  turn_seat int,
  turn_started_at timestamptz not null default now(),
  last_message text,
  winner_seat int,
  round_over boolean not null default false,
  webhook_status text,
  webhook_attempts int not null default 0,
  webhook_body jsonb,
  created_at timestamptz not null default now(),
  unique (table_id, round_number, hand_number)
);

create table public.hand_secrets (
  hand_id uuid primary key references public.hands (id) on delete cascade,
  deck text not null
);

create table public.events (
  hand_id uuid not null references public.hands (id) on delete cascade,
  seq int not null,
  seat_index int not null,
  kind text not null check (kind in ('play', 'pass', 'timeout')),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (hand_id, seq)
);

create table public.holdings (
  hand_id uuid not null references public.hands (id) on delete cascade,
  seat_index int not null check (seat_index between 0 and 3),
  cards jsonb not null,
  primary key (hand_id, seat_index)
);

create table public.hand_results (
  hand_id uuid primary key references public.hands (id) on delete cascade,
  table_id uuid not null,
  round_number int not null,
  hand_number int not null,
  players text[] not null,
  cards_left int[] not null,
  hand_points int[] not null,
  running_totals int[] not null,
  bonuses jsonb not null,
  winner_seat int,
  round_over boolean not null,
  played_on text not null,
  commitment text not null,
  deck_reveal text not null,
  created_at timestamptz not null default now()
);

create table public.keep_alive (
  id int primary key,
  pinged_at timestamptz not null default now()
);

insert into public.keep_alive (id, pinged_at) values (1, now());

create index seats_user_idx on public.seats (user_id);
create index hands_table_idx on public.hands (table_id, round_number, hand_number);
create index results_table_idx on public.hand_results (table_id, round_number, hand_number);

create or replace function public.is_seated(tid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.seats
    where table_id = tid and user_id = auth.uid()
  );
$$;

revoke all on function public.is_seated(uuid) from public;
grant execute on function public.is_seated(uuid) to authenticated;

alter table public.game_tables enable row level security;
alter table public.seats enable row level security;
alter table public.hands enable row level security;
alter table public.hand_secrets enable row level security;
alter table public.events enable row level security;
alter table public.holdings enable row level security;
alter table public.hand_results enable row level security;
alter table public.keep_alive enable row level security;

revoke all on public.game_tables, public.seats, public.hands, public.hand_secrets,
  public.events, public.holdings, public.hand_results, public.keep_alive
  from anon, authenticated;

grant select on public.game_tables, public.seats, public.hands, public.events,
  public.holdings, public.hand_results to authenticated;

create policy tables_read on public.game_tables
  for select to authenticated
  using (public.is_seated(id));

create policy seats_read on public.seats
  for select to authenticated
  using (public.is_seated(table_id));

create policy hands_read on public.hands
  for select to authenticated
  using (public.is_seated(table_id));

create policy events_read on public.events
  for select to authenticated
  using (
    exists (
      select 1 from public.hands h
      where h.id = events.hand_id and public.is_seated(h.table_id)
    )
  );

create policy holdings_own on public.holdings
  for select to authenticated
  using (
    exists (
      select 1
      from public.hands h
      join public.seats s
        on s.table_id = h.table_id
       and s.seat_index = holdings.seat_index
      where h.id = holdings.hand_id
        and s.user_id = auth.uid()
    )
  );

create policy results_read on public.hand_results
  for select to authenticated
  using (public.is_seated(table_id));

-- No policy on hand_secrets or keep_alive: players cannot read the live deck.

alter table public.game_tables replica identity full;
alter table public.seats replica identity full;
alter table public.hands replica identity full;
alter table public.holdings replica identity full;

do $$
declare
  tbl text;
begin
  foreach tbl in array array['game_tables', 'seats', 'hands', 'holdings']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = tbl
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tbl);
    end if;
  end loop;
end $$;
