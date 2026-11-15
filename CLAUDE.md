# lgnd-checklist

App gratuito de checklist de equipamentos para o grupo Legendários. Projeto **pessoal** do André (não é da UniMissional nem de cliente).

## Stack
HTML/CSS/JS puro, sem build. `index.html` (app) e `admin.html` (painel). Supabase (Postgres, Auth Google, Edge Function `admin-api`). Idioma da UI: pt-BR.

## Regras
- Tudo mora em `index.html`; não introduzir framework nem bundler.
- Tabelas com prefixo `lgndcheck_`, RLS sempre ligada, zero privilégio para `anon`.
- Mudanças de banco: arquivo novo em `supabase/migrations/` (timestamp maior que o último), nunca editar migration antiga. Aplicar em produção só após o André aprovar o PR.
- Escrita de preset só por RPC. Não aceitar JSON do cliente para montar presets.
- Nunca commitar e-mails de admin, service key ou dados de usuários (repo público).
- Decisões de nome institucional, licença e o que sanitizar são do André.

## Rodar
`python3 -m http.server 8000` e abrir http://localhost:8000
