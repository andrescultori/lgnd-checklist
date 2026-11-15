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

## Skills installed (`.claude/skills/`, escopo do projeto)
| Skill | Origem | Para quê |
|---|---|---|
| `impeccable` | pbakaus/impeccable v4.9.1 (cópia manual, **sem** hook de design) | Design/critique/polish de UI. Use `/impeccable init` uma vez para o contexto de design (lê `DESIGN.md`). |
| `supabase` | supabase/agent-skills | Auth, migrations, CLI. |
| `supabase-postgres-best-practices` | supabase/agent-skills | RLS e schema; obrigatório com dados pessoais (LGPD). |
| `security-audit` | cloudflare/security-audit-skill | Modo guia por padrão; auditoria completa só sob pedido explícito. |

Já disponíveis na conta (sem instalar): `/security-review` antes de cada merge, `webapp-testing`, `design:design-critique`, `design:accessibility-review`, `seo-ai-visibility`, `lgpd-web`.

Notas: `skills-lock.json` registra as versões dos skills instalados via `npx skills`. O Impeccable foi copiado sem hook porque hooks rodam fora da aprovação do modelo e baixam um binário na primeira edição; para ativar, rode `npx impeccable install` e revise o hook.
