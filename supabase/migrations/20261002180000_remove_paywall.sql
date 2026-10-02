-- Remove completamente o sistema de pagamento (paywall) do app.
-- Contexto: projeto pessoal, não institucional. O app passa a ser gratuito
-- de entrada para captação de leads. Nenhum pagamento real existia até esta
-- migration — os 4 acessos liberados até aqui vieram de cupom de teste
-- (confirmado por auditoria antes de aplicar: profiles.pago=true em 4/4
-- linhas, todas com cupom_usado preenchido; payments só tem status='isento').

-- ============================================================
-- 1) Trigger/função que protegiam os campos de pagamento
-- ============================================================
drop trigger if exists protect_payment_fields_trigger on public.profiles;
drop function if exists public.protect_payment_fields();

-- ============================================================
-- 2) Aviso de lead novo (Make.com): deixa de depender de `pago`
--    e passa a disparar no cadastro (INSERT), não mais quando o
--    perfil "vira pago".
-- ============================================================
drop trigger if exists on_profile_paid_notify_make on public.profiles;

create trigger on_profile_created_notify_make
  after insert on public.profiles
  for each row
  execute function public.notify_new_profile();

-- ============================================================
-- 3) Tabelas 100% ligadas ao paywall
-- ============================================================
drop table if exists public.payments;
drop table if exists public.coupons;
drop table if exists public.app_config;

-- ============================================================
-- 4) Colunas de pagamento em profiles
-- ============================================================
alter table public.profiles
  drop column if exists pago,
  drop column if exists valor_pago_centavos,
  drop column if exists cupom_usado,
  drop column if exists mp_payment_id,
  drop column if exists paid_at;

-- ============================================================
-- 5) RLS: reescreve as policies de profiles/checklist_items/pack_meta
--    usando (select auth.uid()) em vez de auth.uid() direto, pra evitar
--    reavaliação por linha (achado do advisor de performance: 11
--    policies com esse problema antes desta migration).
-- ============================================================

-- profiles
drop policy if exists "Usuário vê o próprio perfil" on public.profiles;
create policy "Usuário vê o próprio perfil"
  on public.profiles for select
  using (id = (select auth.uid()));

drop policy if exists "Usuário cria o próprio perfil" on public.profiles;
create policy "Usuário cria o próprio perfil"
  on public.profiles for insert
  with check (id = (select auth.uid()));

drop policy if exists "Usuário edita o próprio perfil" on public.profiles;
create policy "Usuário edita o próprio perfil"
  on public.profiles for update
  using (id = (select auth.uid()));

-- checklist_items
drop policy if exists "Usuário vê os próprios itens" on public.checklist_items;
create policy "Usuário vê os próprios itens"
  on public.checklist_items for select
  using (user_id = (select auth.uid()));

drop policy if exists "Usuário cria os próprios itens" on public.checklist_items;
create policy "Usuário cria os próprios itens"
  on public.checklist_items for insert
  with check (user_id = (select auth.uid()));

drop policy if exists "Usuário edita os próprios itens" on public.checklist_items;
create policy "Usuário edita os próprios itens"
  on public.checklist_items for update
  using (user_id = (select auth.uid()));

drop policy if exists "Usuário apaga os próprios itens" on public.checklist_items;
create policy "Usuário apaga os próprios itens"
  on public.checklist_items for delete
  using (user_id = (select auth.uid()));

-- pack_meta
drop policy if exists "Usuário vê o próprio pack_meta" on public.pack_meta;
create policy "Usuário vê o próprio pack_meta"
  on public.pack_meta for select
  using (user_id = (select auth.uid()));

drop policy if exists "Usuário cria o próprio pack_meta" on public.pack_meta;
create policy "Usuário cria o próprio pack_meta"
  on public.pack_meta for insert
  with check (user_id = (select auth.uid()));

drop policy if exists "Usuário edita o próprio pack_meta" on public.pack_meta;
create policy "Usuário edita o próprio pack_meta"
  on public.pack_meta for update
  using (user_id = (select auth.uid()));
