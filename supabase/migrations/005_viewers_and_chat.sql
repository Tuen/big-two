-- Viewers and table chat. Players still cannot write. Edge Functions use the service role.
-- There is no read policy: phones only see this through the table view, never a raw hand.

create table if not exists public.table_viewers (
  table_id uuid not null references public.game_tables (id) on delete cascade,
  user_id uuid not null,
  display_name text not null check (char_length(display_name) between 1 and 24),
  last_seen timestamptz not null default now(),
  primary key (table_id, user_id)
);

create table if not exists public.table_messages (
  id bigint generated always as identity primary key,
  table_id uuid not null references public.game_tables (id) on delete cascade,
  round_number int not null,
  display_name text not null,
  viewer boolean not null default false,
  body text not null check (char_length(body) between 1 and 200),
  created_at timestamptz not null default now()
);

create index if not exists table_messages_round_idx
  on public.table_messages (table_id, round_number, id);

alter table public.table_viewers enable row level security;
alter table public.table_messages enable row level security;

revoke all on public.table_viewers, public.table_messages from anon, authenticated;
