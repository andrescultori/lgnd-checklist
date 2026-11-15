-- Defesa em profundidade (auditoria 2026-11-15):
-- o app só funciona logado, então 'anon' não precisa de nenhum privilégio
-- nas tabelas lgndcheck_*. A RLS já bloqueia, mas os GRANTs amplos
-- (inclusive TRUNCATE) tornariam qualquer policy errada um vazamento.
revoke all on table public.lgndcheck_profiles       from anon;
revoke all on table public.lgndcheck_checklist_items from anon;
revoke all on table public.lgndcheck_pack_meta       from anon;

-- Função de trigger (novo perfil): não precisa ser chamável via /rest/v1/rpc.
-- O trigger continua disparando normalmente.
revoke execute on function public.notify_new_profile() from public, anon, authenticated;
