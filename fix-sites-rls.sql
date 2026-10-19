
-- Fix permisos sites + payments (403)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.sites to authenticated;
grant select on public.sites to anon;
grant select, insert, update on public.payments to authenticated;
grant select, update on public.profiles to authenticated;
grant insert on public.profiles to authenticated;

-- Asegurar políticas de lectura de sitios
drop policy if exists "Ver mis sitios" on public.sites;
create policy "Ver mis sitios" on public.sites
  for select to authenticated
  using (auth.uid() = owner_id or public.is_admin());

drop policy if exists "Público ve sitios activos" on public.sites;
create policy "Público ve sitios activos" on public.sites
  for select to anon, authenticated
  using (status = 'act');

drop policy if exists "Crear mis sitios" on public.sites;
create policy "Crear mis sitios" on public.sites
  for insert to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "Actualizar mis sitios" on public.sites;
create policy "Actualizar mis sitios" on public.sites
  for update to authenticated
  using (auth.uid() = owner_id or public.is_admin())
  with check (auth.uid() = owner_id or public.is_admin());

drop policy if exists "Eliminar mis sitios" on public.sites;
create policy "Eliminar mis sitios" on public.sites
  for delete to authenticated
  using (auth.uid() = owner_id or public.is_admin());

-- is_admin ejecutable
grant execute on function public.is_admin() to authenticated, anon;
grant execute on function public.is_site_owner(uuid) to authenticated, anon;
grant execute on function public.activate_site_from_payment(uuid, text, text, jsonb) to service_role;

-- Verificar tu admin
select id, email, is_admin from public.profiles;
