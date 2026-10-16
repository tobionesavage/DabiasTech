-- ============================================================
-- DabiasTech · Schema de base de datos (Supabase / PostgreSQL)
-- Ejecutá esto en: Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- Extensiones
create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- 1. Perfiles (extiende auth.users)
-- ------------------------------------------------------------
create table public.profiles (
  id          uuid references auth.users on delete cascade primary key,
  name        text not null,
  email       text not null unique,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. Sitios / Tiendas
-- ------------------------------------------------------------
create table public.sites (
  id           uuid primary key default uuid_generate_v4(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  name         text not null,
  slug         text not null unique,
  rubro        text not null check (rubro in ('tec','com','rop','bel','otr')),
  color        text not null default '#4f46e5',
  whatsapp     text,
  plan         text not null check (plan in ('starter','pro','premium')),
  status       text not null default 'pend' check (status in ('act','pend','pau')),
  valid_until  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Índices
create index sites_owner_id_idx on public.sites (owner_id);
create index sites_status_idx   on public.sites (status);
create index sites_slug_idx     on public.sites (slug);

-- ------------------------------------------------------------
-- 3. Trigger: crear perfil automáticamente al registrarse
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ------------------------------------------------------------
-- 4. Trigger: actualizar updated_at
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger sites_updated_at
  before update on public.sites
  for each row execute procedure public.set_updated_at();

-- ------------------------------------------------------------
-- 5. Row Level Security (RLS)
-- ------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.sites    enable row level security;

-- Profiles
create policy "Ver propio perfil"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Actualizar propio perfil"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Insertar propio perfil"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Sites · usuarios normales
create policy "Ver mis sitios"
  on public.sites for select
  using (auth.uid() = owner_id);

create policy "Crear mis sitios"
  on public.sites for insert
  with check (auth.uid() = owner_id);

create policy "Actualizar mis sitios"
  on public.sites for update
  using (auth.uid() = owner_id);

create policy "Eliminar mis sitios"
  on public.sites for delete
  using (auth.uid() = owner_id);

-- Sites · administradores (pueden ver y modificar todos)
create policy "Admins ven todos los sitios"
  on public.sites for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_admin = true
    )
  );

create policy "Admins actualizan todos los sitios"
  on public.sites for update
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- ------------------------------------------------------------
-- 6. Función útil: generar slug único a partir del nombre
-- (opcional, el frontend también lo genera)
-- ------------------------------------------------------------
create or replace function public.generate_slug(base text)
returns text
language plpgsql
as $$
declare
  s text;
  n int := 0;
begin
  s := lower(regexp_replace(
        unaccent(base),
        '[^a-z0-9]+', '-', 'g'
      ));
  s := trim(both '-' from s);
  while exists (select 1 from public.sites where slug = s || case when n=0 then '' else '-'||n end) loop
    n := n + 1;
  end loop;
  return s || case when n=0 then '' else '-'||n end;
end;
$$;

-- ------------------------------------------------------------
-- 7. (Opcional) Hacer admin a un usuario después de registrarse
-- Reemplazá el email por el tuyo y ejecutá:
-- ------------------------------------------------------------
-- update public.profiles set is_admin = true where email = 'tu@email.com';

-- ============================================================
-- Listo. Ahora en Authentication → Providers activá Email.
-- En Project Settings → API copiá la URL y la anon key.
-- ============================================================
