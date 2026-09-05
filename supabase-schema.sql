-- Frenos La Amistad: base de datos, roles y reglas de acceso.
-- Ejecuta este archivo completo en Supabase > SQL Editor > New query.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null default 'employee' check (role in ('admin', 'employee')),
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id text primary key,
  name text not null,
  category text not null default '',
  location text not null default '',
  quantity integer not null default 0 check (quantity >= 0),
  "minStock" integer not null default 0 check ("minStock" >= 0),
  unit text not null default 'un',
  "buyPrice" numeric,
  "sellPrice" numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.movements (
  id uuid primary key default gen_random_uuid(),
  item_id text not null references public.items(id) on delete restrict,
  item_name text not null,
  type text not null check (type in ('in', 'out')),
  qty integer not null check (qty > 0),
  note text not null default '',
  user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.movements enable row level security;

-- Acceso mínimo: nadie anónimo accede; las políticas de abajo delimitan
-- exactamente lo que puede hacer cada usuario autenticado.
revoke all on public.profiles, public.items, public.movements from anon;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.items to authenticated;
grant select on public.movements to authenticated;

create policy "users can read their profile"
on public.profiles for select to authenticated
using (id = auth.uid());

create policy "authenticated users can read items"
on public.items for select to authenticated
using (true);

create policy "admins can add items"
on public.items for insert to authenticated
with check (public.is_admin());

create policy "admins can edit items"
on public.items for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "admins can delete items"
on public.items for delete to authenticated
using (public.is_admin());

create policy "admins can read movements"
on public.movements for select to authenticated
using (public.is_admin());

-- Los empleados solo pueden usar esta función: no pueden editar inventario directo.
create or replace function public.record_inventory_movement(
  p_item_id text,
  p_type text,
  p_qty integer,
  p_note text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  current_item public.items;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  if p_type not in ('in', 'out') or p_qty <= 0 then
    raise exception 'Movimiento inválido';
  end if;

  select * into current_item from public.items where id = p_item_id for update;
  if not found then raise exception 'Referencia no encontrada'; end if;
  if p_type = 'out' and p_qty > current_item.quantity then
    raise exception 'No hay suficiente inventario';
  end if;

  update public.items
  set quantity = quantity + case when p_type = 'in' then p_qty else -p_qty end,
      updated_at = now()
  where id = p_item_id;

  insert into public.movements (item_id, item_name, type, qty, note, user_id)
  values (current_item.id, current_item.name, p_type, p_qty, coalesce(p_note, ''), auth.uid());
end;
$$;

revoke all on function public.record_inventory_movement(text, text, integer, text) from public;
grant execute on function public.record_inventory_movement(text, text, integer, text) to authenticated;

-- DESPUÉS de crear cada usuario en Authentication > Users, conviértelo en admin.
-- Reemplaza los correos por los que usarán Nelson y Paola:
-- update public.profiles set name = 'Nelson', role = 'admin'
-- where id = (select id from auth.users where email = 'nelson@ejemplo.com');
-- update public.profiles set name = 'Paola', role = 'admin'
-- where id = (select id from auth.users where email = 'paola@ejemplo.com');
-- update public.profiles set name = 'Grillo', role = 'employee'
-- where id = (select id from auth.users where email = 'grillo@ejemplo.com');
