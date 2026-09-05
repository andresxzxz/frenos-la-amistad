-- Ejecuta este archivo UNA vez en Supabase > SQL Editor > New query.
-- Añade clientes y citas al sistema existente.

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  vehicle_make text not null default '',
  vehicle_model text not null default '',
  plate text not null default '',
  notes text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  requested_service text not null,
  preferred_date date,
  status text not null default 'pendiente' check (status in ('pendiente', 'confirmada', 'atendida', 'cancelada')),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

alter table public.clients enable row level security;
alter table public.appointments enable row level security;

revoke all on public.clients, public.appointments from anon;
grant select, insert, update on public.clients to authenticated;
grant select, insert, update on public.appointments to authenticated;

create policy "admins manage clients"
on public.clients for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "admins manage appointments"
on public.appointments for all to authenticated
using (public.is_admin()) with check (public.is_admin());
