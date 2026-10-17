🇧🇷 Português | [🇺🇸 English](README.en.md)

# 🎒 Legendários — Checklist de Equipamentos

Checklist de equipamentos de trilha, salva na nuvem e sempre à mão — sem mais lista de papel se perdendo entre a mochila de ataque e a cargueira.

App web **gratuito** para os membros do grupo de trekking **Legendários** organizarem o que levar nas duas mochilas da trilha (ataque e cargueira) e o que ainda falta comprar, com progresso salvo por usuário na nuvem.

> Este é o app real usado pelo grupo em produção — o login é feito com conta Google de verdade e os dados ficam no banco real dos Legendários. Não há um modo demo separado; as capturas de tela abaixo mostram a interface funcionando com uma conta real (a minha).

![Tela de login do app Legendários](screenshots/01-login.jpg)

## O problema original

Antes disso, a lista de equipamentos circulava como texto solto ou planilha — cada Legendário mantinha sua própria versão, sem padronização entre o que vai na mochila de ataque (a que fica com você o tempo todo na trilha) e o que vai na cargueira (entregue no check-in, acessada só em pontos pré-determinados). Fácil esquecer item, fácil perder o controle do que já foi separado ou comprado.

## A solução

```
Login com Google
      ↓
Perfil criado no Supabase (nome, nº de Legendário, pista, 1º TOP)
      ↓
Checklist padrão semeada automaticamente (3 packs, seções, itens e subitens)
      ↓
Progresso marcado item a item, salvo automaticamente na nuvem
```

O resultado: cada Legendário abre o app, vê exatamente o que falta separar em cada mochila, e pode ajustar a lista (adicionar, editar, remover itens) sem afetar a lista de mais ninguém.

## O checklist em si

- **Três packs organizados em abas** — Ataque, Cargueira e Comprar — cada um com progresso próprio e cor de destaque diferente
- **Seções numeradas e recolhíveis** (Geral, Higiene + Saúde, Comida, Outros), cada uma com contador de itens concluídos
- **Itens com subitens** — ex: "Lanterna de cabeça" com "3 pilhas" dentro, cada um marcável separadamente
- **Notas, quantidade e link opcional** por item (ex: modelo sugerido, link de compra)
- **Edição inline da sugestão e do tamanho de mochila** direto no texto, sem precisar abrir modal
- **Adicionar, editar e excluir itens** em qualquer seção, a qualquer momento
- **Barra de progresso geral** e por pack, atualizada na hora a cada item marcado
- **"Zerar tudo"** com confirmação, para reiniciar a checklist antes de uma nova trilha

![Checklist da mochila de ataque](screenshots/02-checklist-ataque.jpg)
![Checklist da mochila cargueira](screenshots/03-checklist-cargueira.jpg)
![Lista de itens para comprar](screenshots/04-checklist-comprar.jpg)
![Modal de edição de item](screenshots/05-editar-item.jpg)

## Presets de checklist

Além de editar item a item, cada Legendário pode montar a própria checklist do zero e guardá-la como **preset** — um molde sem marcações que dá pra restaurar quando quiser, ou compartilhar com outro Legendário por um código de 10 caracteres / link.

- **1 preset por usuário** no plano gratuito (o modelo já suporta mais de um; o limite é aplicado no servidor)
- **Restaurar** (preset próprio, preset compartilhado por outro usuário, ou a lista básica padrão) sempre pede confirmação, zera as marcações e cria um **backup automático** da lista atual (com marcações) — dá pra desfazer uma vez
- **Compartilhar** gera um código curto que sempre aponta pro conteúdo *atual* do preset; revogar o código não apaga cópias já importadas por outros usuários

### Modelo de dados

Quatro tabelas em `public`, mesmo prefixo `lgndcheck_`, RLS ligado, sem nenhum privilégio para `anon`:

| Tabela | O que guarda |
|---|---|
| `lgndcheck_presets` | Snapshot do preset (JSON, sem marcações) + `share_code` opcional |
| `lgndcheck_entitlements` | Limite de presets por usuário (sem linha = 1) |
| `lgndcheck_list_backups` | Backup automático (com marcações) antes de um restaurar — um por usuário, o mais recente |
| `lgndcheck_share_rate_limit` | Contador de tentativas de uso de código de compartilhamento (10/min) |

Toda escrita nessas tabelas passa pelas RPCs abaixo — não existe policy de insert/update direta pro usuário.

### RPCs (`SECURITY DEFINER`, só `authenticated`)

| RPC | O que faz |
|---|---|
| `lgndcheck_salvar_preset_da_lista_atual(nome, id_para_substituir?)` | Monta o snapshot a partir da lista atual do próprio usuário (nunca aceita JSON do cliente) e cria ou substitui o preset |
| `lgndcheck_aplicar_preset(id)` | Restaura um preset próprio |
| `lgndcheck_resetar_para_base(snapshot_base)` | Restaura a lista básica padrão |
| `lgndcheck_desfazer_ultima_substituicao()` | Restaura o backup mais recente e o apaga |
| `lgndcheck_compartilhar_preset(id, ativar)` | Gera ou revoga o `share_code` |
| `lgndcheck_ver_preset_compartilhado(codigo)` | Prévia de um preset compartilhado (nome, dono, contagem por pack, títulos) — nunca o e-mail do dono |
| `lgndcheck_aplicar_preset_compartilhado(codigo)` | Restaura direto um preset de outro usuário |
| `lgndcheck_salvar_preset_compartilhado(codigo, id_para_substituir?)` | Importa uma cópia própria de um preset compartilhado |

Migrations: [`supabase/migrations/20261016000000_user_presets.sql`](supabase/migrations/20261016000000_user_presets.sql) e [`supabase/migrations/20261017000000_lgndcheck_presets_restore_e_desfazer.sql`](supabase/migrations/20261017000000_lgndcheck_presets_restore_e_desfazer.sql).

### Elevar o limite de presets de um usuário

O plano com mais de 1 preset ainda não tem fluxo de compra na UI, mas o backend já suporta — basta uma linha na tabela de entitlements:

```sql
insert into public.lgndcheck_entitlements (user_id, max_presets)
values ('<uuid-do-usuario>', 3)
on conflict (user_id) do update set max_presets = excluded.max_presets;
```

## Stack técnica

| Camada | Tecnologia |
|---|---|
| Frontend | HTML, CSS e JavaScript puros — sem framework, sem build |
| Backend / dados | [Supabase](https://supabase.com) (Postgres) |
| Autenticação | Supabase Auth com login via Google OAuth |
| Tipografia | Google Fonts (Bitter + Work Sans) |

## Por que sem framework

O app inteiro vive em um único `index.html`. A escolha foi deliberada: é um projeto pequeno, de escopo bem definido, para um grupo específico — não precisa de bundler, pipeline de build ou dependências além do cliente JS do Supabase via CDN. Isso significa que qualquer navegador abre o arquivo direto, sem etapa de deploy, e a manutenção fica trivial: uma pessoa só, sem stack de frontend, consegue editar o arquivo e publicar.

A segurança dos dados não depende de esconder a `anon key` do Supabase (ela é feita para ficar no cliente) — depende das políticas de Row Level Security configuradas no banco, que restringem cada usuário a ler e escrever apenas os próprios dados.

## Arquitetura

Toda a lógica está em [`index.html`](index.html):
- Tabelas do Supabase usadas: `lgndcheck_profiles`, `lgndcheck_checklist_items`, `lgndcheck_pack_meta`, mais as 4 tabelas de presets (ver seção acima) — prefixo `lgndcheck_` porque o projeto Supabase é compartilhado com outras aplicações
- Template padrão de itens (`TEMPLATE`) usado para semear a checklist de um usuário novo no primeiro login, e convertido (`templateToSnapshot`) pro formato de snapshot usado em "Restaurar lista básica"
- Fluxo de autenticação e cadastro (`boot`, `afterLogin`, `seedDefaultItems`)
- Renderização dos packs e seções (`renderPack`, `buildSections`)
- Presets (`loadPresetState`, `renderPresetSection`, `openRestoreConfirm`, fluxo de compartilhar/importar)

## Rodando localmente

Não há build — é servir o arquivo estático:

```bash
git clone https://github.com/andrescultori/lgnd-checklist.git
cd lgnd-checklist
python3 -m http.server 8000
# abra http://localhost:8000
```

Para rodar com dados próprios (em vez do banco real dos Legendários), crie um projeto no Supabase, replique as tabelas `lgndcheck_profiles`, `lgndcheck_checklist_items` e `lgndcheck_pack_meta`, e troque `SUPABASE_URL` e `SUPABASE_ANON_KEY` no topo do `<script>` em `index.html`.

---

*Este repositório é disponibilizado publicamente para fins de portfólio profissional. Trata-se do sistema real em produção para o grupo Legendários — veja a seção de licença para os termos de uso do código.*

Desenvolvido por [André Scultori](https://github.com/andrescultori)  ·  © 2026  ·  [GitHub](https://github.com/andrescultori/lgnd-checklist)
