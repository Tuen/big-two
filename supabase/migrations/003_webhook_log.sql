-- Score delivery. The Edge Function writes the log. Players can see the status on the hand.

alter table public.hand_results
  add column if not exists webhook_status text;

create table if not exists public.webhook_log (
  id bigint generated always as identity primary key,
  hand_id uuid not null references public.hands (id) on delete cascade,
  attempted_at timestamptz not null default now(),
  ok boolean not null,
  status_code int,
  detail text
);

alter table public.webhook_log enable row level security;
revoke all on public.webhook_log from public, anon, authenticated;
