
-- ============================================================
-- DabiasTech · Mercado Pago (pagos de planes mensuales)
-- Ejecutá DESPUÉS del schema principal
-- ============================================================

create table if not exists public.payments (
  id              uuid primary key default uuid_generate_v4(),
  site_id         uuid not null references public.sites(id) on delete cascade,
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  plan            text not null check (plan in ('starter','pro','premium')),
  amount          numeric(12,2) not null check (amount >= 0),
  currency        text not null default 'ARS',
  status          text not null default 'pending'
                  check (status in ('pending','approved','rejected','cancelled','refunded')),
  mp_preference_id text,
  mp_payment_id   text,
  mp_status       text,
  external_reference text,
  raw             jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists payments_site_id_idx on public.payments (site_id);
create index if not exists payments_owner_id_idx on public.payments (owner_id);
create index if not exists payments_mp_payment_id_idx on public.payments (mp_payment_id);

alter table public.sites
  add column if not exists mp_last_payment_id text;

drop trigger if exists payments_updated_at on public.payments;
create trigger payments_updated_at before update on public.payments
  for each row execute procedure public.set_updated_at();

alter table public.payments enable row level security;

drop policy if exists "Ver mis pagos" on public.payments;
drop policy if exists "Crear mis pagos" on public.payments;
create policy "Ver mis pagos" on public.payments for select
  using (auth.uid() = owner_id or public.is_admin());
create policy "Crear mis pagos" on public.payments for insert
  with check (auth.uid() = owner_id);

-- Activa un sitio tras pago aprobado (solo service_role / edge function)
create or replace function public.activate_site_from_payment(
  p_site_id uuid,
  p_payment_id text default null,
  p_mp_status text default 'approved',
  p_raw jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_until timestamptz;
begin
  v_until := now() + interval '30 days';
  update public.sites
     set status = 'act',
         valid_until = v_until,
         mp_last_payment_id = coalesce(p_payment_id, mp_last_payment_id),
         updated_at = now()
   where id = p_site_id;

  if p_payment_id is not null then
    update public.payments
       set status = 'approved',
           mp_payment_id = p_payment_id,
           mp_status = p_mp_status,
           raw = coalesce(p_raw, raw),
           updated_at = now()
     where site_id = p_site_id
       and status = 'pending'
       and (mp_payment_id is null or mp_payment_id = p_payment_id);
  end if;
end;
$$;

revoke all on function public.activate_site_from_payment from public;
grant execute on function public.activate_site_from_payment to service_role;
