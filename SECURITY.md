# Segurança

- **Dados:** perfis e checklists de membros reais (LGPD). Tabelas `lgndcheck_*` com RLS; cada usuário só acessa as próprias linhas. `anon` não tem privilégio nas tabelas.
- **Chave no front:** `SUPABASE_ANON_KEY` é pública por design. A proteção está nas policies de RLS, nunca em esconder a chave. Nunca commitar `service_role`.
- **Escritas de presets:** só via RPCs `SECURITY DEFINER` (somente `authenticated`).
- **Admin:** Edge Function `admin-api` com JWT + allowlist de e-mail no servidor. A allowlist não fica neste repo público.
- **Banco compartilhado:** o projeto Supabase também serve outros apps (prefixos diferentes). Toda tabela nova precisa de RLS e prefixo próprio.
- **Reportar vulnerabilidade:** abra contato pelo perfil https://github.com/andrescultori (não publique detalhes em issue pública).
