-- Advisors do Supabase (auditoria 2026-11-15) — banco COMPARTILHADO com outros apps.
-- Escopo deliberadamente mínimo: só funções de TRIGGER, que disparam sem que o
-- chamador tenha EXECUTE (o privilégio é checado no CREATE TRIGGER, não ao disparar).
-- Assim deixam de aparecer em /rest/v1/rpc para anon e authenticated.
revoke execute on function public.lgnddoc_bump()              from public, anon, authenticated;
revoke execute on function public.lgnddoc_guard_profile()     from public, anon, authenticated;
revoke execute on function public.lgnddoc_sync_predicante()   from public, anon, authenticated;

-- set_updated_at: sem search_path fixo (lint 0011). A função só usa now() e NEW.
alter function public.set_updated_at() set search_path = '';

-- NÃO alterado de propósito:
--  * lgnddoc_is_admin / lgnddoc_is_approved / lgnddoc_can_read_escala / lgnddoc_can_read_predica:
--    chamadas por policies com role {public}; revogar EXECUTE de anon faria consultas anônimas
--    falharem com "permission denied" em vez de voltar vazias. Só devolvem boolean.
--  * pm_client_view(p_token): acesso anônimo por token é o recurso (visão do cliente no amshub).
--  * RPCs lgndcheck_* e lgnddoc_set_equipe: feitas para usuários autenticados.
