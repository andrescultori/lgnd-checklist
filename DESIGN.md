# Design — Checklist Legendários

Contexto de design para quem (ou o quê) for mexer na interface. Extraído do CSS real de `index.html`; se o CSS mudar, atualize aqui.

## Princípios
- **Mobile first, uso em campo.** Coluna única de até 640px, alvos de toque generosos, respeita safe-area do iPhone. É usado na mochila, no celular.
- **Papel de caderno de trilha.** Fundo areia, "folhas" de papel creme, tinta escura quente. Sem preto puro, sem branco puro, sem azul de interface genérico.
- **Progresso é o protagonista.** Barra de progresso geral e por mochila sempre visíveis; seções mostram "x/y".
- **Tema só claro** (`color-scheme: light`). Não há modo escuro.
- **Português do Brasil**, tom direto e de grupo ("Área Restrita", "Painel Admin").

## Cor
| Token | Valor | Uso |
|---|---|---|
| `--canvas` | `#EDE4CF` | fundo da página |
| `--canvas-deep` | `#E1D3B2` | fundo mais fundo / contraste |
| `--paper` | `#F6F0E1` | cartões, modais, campos |
| `--ink` | `#262420` | texto principal |
| `--ink-soft` | `#56503f` | texto secundário, rodapé |
| `--line` | `#C9B993` | bordas e divisórias |
| `--forest` / `-deep` / `-tint` | `#3F4B3A` / `#2C3527` / `#DFE4D6` | acento padrão (mochila de ataque) |
| `--clay` / `-deep` / `-tint` | `#A6532E` / `#7C3D22` / `#F0DFCF` | acento da cargueira |
| `--steel` / `-deep` / `-tint` | `#3D6B72` / `#294A50` / `#DCE7E7` | acento da aba Comprar |

Cada mochila define `--accent`, `--accent-deep` e `--accent-tint` a partir de uma das três famílias. Use sempre os tokens, nunca hex solto.

## Tipografia
- **Títulos:** Bitter (serifada), peso 700–800. Títulos de modal 19px, títulos de seção em Bitter.
- **Interface e texto:** Work Sans, 14px base; rótulos e botões em 600–700, 12.5–14px.
- Fallbacks: Georgia / `-apple-system`, `Segoe UI`, sans-serif.

## Forma e componentes
- Cartões e modais: raio 14px, fundo `--paper`, borda `--line`.
- Botões: raio 9–10px, Work Sans 600. Campos: raio 8px, borda 1.5px `--line`.
- Checkbox: 19px, raio 5px, borda 2px.
- Bloco de informação da mochila: borda esquerda de 4px na cor de acento, cantos `2px 10px 10px 2px`.
- Barra de progresso: 8px, trilho em papel translúcido, preenchimento `--paper`, transição `.4s cubic-bezier(.4,0,.2,1)`.
- Seções numeradas (círculo `--accent` com número em `--paper`), recolhíveis com `<details>`.
- Banner de desfazer: papel translúcido sobre acento, botões com borda translúcida.

## Telas
Login (Google) → Cadastro (primeiro acesso) → Checklist com abas **Ataque / Cargueira / Comprar** → Configurações (perfil, presets, consentimento) → `privacidade.html` e `admin.html` (painel só do administrador).

## Regras ao mexer
- Sem framework e sem build: CSS inline em `index.html`, variáveis em `:root`.
- Contraste mínimo AA: texto em `--ink`/`--ink-soft` sobre `--canvas`/`--paper`; texto em `--paper` só sobre os tons `-deep` ou cheios do acento.
- Respeitar `prefers-reduced-motion` em qualquer animação nova (hoje só há a transição da barra).
- Não introduzir modo escuro sem decisão do André.

## Pendências conhecidas
- Revisão de acessibilidade (foco visível, labels, contraste real medido) ainda não feita.
- OG tags / ícones sociais ausentes.
