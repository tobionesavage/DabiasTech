-- ============================================================
-- DabiasTech · Backend primario (Supabase / PostgreSQL)
-- Ejecutá en: Supabase → SQL Editor → New query
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 1. Perfiles
create table if not exists public.profiles (
  id          uuid references auth.users on delete cascade primary key,
  name        text not null,
  email       text not null unique,
  phone       text,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2. Sitios / Tiendas
create table if not exists public.sites (
  id           uuid primary key default uuid_generate_v4(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  name         text not null,
  slug         text not null unique,
  rubro        text not null default 'otr' check (rubro in ('tec','com','rop','bel','otr')),
  color        text not null default '#2563EB',
  tagline      text,
  template     text not null default 'classic'
               check (template in ('classic','minimal','showcase','editorial','boutique')),
  whatsapp     text,
  instagram    text,
  tiktok       text,
  plan         text not null default 'starter' check (plan in ('starter','pro','premium')),
  status       text not null default 'pend' check (status in ('act','pend','pau')),
  valid_until  timestamptz,
  settings     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists sites_owner_id_idx on public.sites (owner_id);
create index if not exists sites_status_idx on public.sites (status);
create index if not exists sites_slug_idx on public.sites (slug);

-- 3. Productos
create table if not exists public.products (
  id          uuid primary key default uuid_generate_v4(),
  site_id     uuid not null references public.sites(id) on delete cascade,
  name        text not null,
  description text,
  price       numeric(12,2) not null check (price >= 0),
  image_url   text,
  emoji       text,
  stock       int,
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists products_site_id_idx on public.products (site_id);

-- 4. Pedidos
create table if not exists public.orders (
  id               uuid primary key default uuid_generate_v4(),
  site_id          uuid not null references public.sites(id) on delete cascade,
  customer_name    text not null,
  customer_phone   text not null,
  customer_email   text,
  customer_address text,
  notes            text,
  status           text not null default 'new'
                   check (status in ('new','confirmed','preparing','shipped','delivered','cancelled')),
  subtotal         numeric(12,2) not null default 0,
  shipping         numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0,
  currency         text not null default 'ARS',
  channel          text not null default 'web' check (channel in ('web','whatsapp','admin')),
  meta             jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists orders_site_id_idx on public.orders (site_id);
create index if not exists orders_status_idx on public.orders (site_id, status);

-- 5. Ítems
create table if not exists public.order_items (
  id          uuid primary key default uuid_generate_v4(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,
  unit_price  numeric(12,2) not null,
  qty         int not null check (qty > 0),
  line_total  numeric(12,2) not null
);
create index if not exists order_items_order_id_idx on public.order_items (order_id);

-- 6. Triggers
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), new.email)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists sites_updated_at on public.sites;
create trigger sites_updated_at before update on public.sites
  for each row execute procedure public.set_updated_at();
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products
  for each row execute procedure public.set_updated_at();
drop trigger if exists orders_updated_at on public.orders;
create trigger orders_updated_at before update on public.orders
  for each row execute procedure public.set_updated_at();
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
  for each row execute procedure public.set_updated_at();

create or replace function public.is_site_owner(p_site_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sites s where s.id = p_site_id and s.owner_id = auth.uid())
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_admin = true);
$$;

-- 7. RLS
alter table public.profiles enable row level security;
alter table public.sites enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Ver propio perfil" on public.profiles;
drop policy if exists "Actualizar propio perfil" on public.profiles;
drop policy if exists "Insertar propio perfil" on public.profiles;
create policy "Ver propio perfil" on public.profiles for select using (auth.uid() = id or public.is_admin());
create policy "Actualizar propio perfil" on public.profiles for update using (auth.uid() = id);
create policy "Insertar propio perfil" on public.profiles for insert with check (auth.uid() = id);

drop policy if exists "Ver mis sitios" on public.sites;
drop policy if exists "Crear mis sitios" on public.sites;
drop policy if exists "Actualizar mis sitios" on public.sites;
drop policy if exists "Eliminar mis sitios" on public.sites;
drop policy if exists "Público ve sitios activos" on public.sites;
create policy "Ver mis sitios" on public.sites for select using (auth.uid() = owner_id or public.is_admin());
create policy "Crear mis sitios" on public.sites for insert with check (auth.uid() = owner_id);
create policy "Actualizar mis sitios" on public.sites for update using (auth.uid() = owner_id or public.is_admin());
create policy "Eliminar mis sitios" on public.sites for delete using (auth.uid() = owner_id or public.is_admin());
create policy "Público ve sitios activos" on public.sites for select using (status = 'act');

drop policy if exists "Dueño gestiona productos" on public.products;
drop policy if exists "Público ve productos activos" on public.products;
create policy "Dueño gestiona productos" on public.products for all
  using (public.is_site_owner(site_id)) with check (public.is_site_owner(site_id));
create policy "Público ve productos activos" on public.products for select using (
  active = true and exists (select 1 from public.sites s where s.id = site_id and s.status = 'act')
);

drop policy if exists "Dueño ve pedidos" on public.orders;
drop policy if exists "Dueño actualiza pedidos" on public.orders;
drop policy if exists "Crear pedido público" on public.orders;
create policy "Dueño ve pedidos" on public.orders for select using (public.is_site_owner(site_id));
create policy "Dueño actualiza pedidos" on public.orders for update using (public.is_site_owner(site_id));
create policy "Crear pedido público" on public.orders for insert with check (
  exists (select 1 from public.sites s where s.id = site_id and s.status = 'act')
);

drop policy if exists "Ver items de mis pedidos" on public.order_items;
drop policy if exists "Insertar items con pedido" on public.order_items;
create policy "Ver items de mis pedidos" on public.order_items for select using (
  exists (select 1 from public.orders o where o.id = order_id and public.is_site_owner(o.site_id))
);
create policy "Insertar items con pedido" on public.order_items for insert with check (
  exists (
    select 1 from public.orders o join public.sites s on s.id = o.site_id
    where o.id = order_id and s.status = 'act'
  )
);

-- 8. RPC checkout
create or replace function public.create_store_order(
  p_site_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_customer_email text default null,
  p_customer_address text default null,
  p_notes text default null,
  p_shipping numeric default 0,
  p_items jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_order_id uuid;
  v_subtotal numeric := 0;
  v_item jsonb;
begin
  if not exists (select 1 from public.sites where id = p_site_id and status = 'act') then
    raise exception 'Sitio no disponible';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Carrito vacío';
  end if;
  if coalesce(trim(p_customer_name), '') = '' or coalesce(trim(p_customer_phone), '') = '' then
    raise exception 'Nombre y teléfono requeridos';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal + (v_item->>'unit_price')::numeric * (v_item->>'qty')::int;
  end loop;

  insert into public.orders (
    site_id, customer_name, customer_phone, customer_email, customer_address, notes,
    subtotal, shipping, total, channel
  ) values (
    p_site_id, trim(p_customer_name), trim(p_customer_phone),
    nullif(trim(p_customer_email), ''), nullif(trim(p_customer_address), ''), nullif(trim(p_notes), ''),
    v_subtotal, coalesce(p_shipping, 0), v_subtotal + coalesce(p_shipping, 0), 'web'
  ) returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (order_id, product_id, name, unit_price, qty, line_total)
    values (
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      v_item->>'name',
      (v_item->>'unit_price')::numeric,
      (v_item->>'qty')::int,
      (v_item->>'unit_price')::numeric * (v_item->>'qty')::int
    );
  end loop;

  return v_order_id;
end; $$;

grant execute on function public.create_store_order to anon, authenticated;

-- Admin: update public.profiles set is_admin = true where email = 'tu@email.com';
