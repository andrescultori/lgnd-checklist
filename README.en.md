[🇧🇷 Português](README.md) | 🇺🇸 English

# 🎒 Legendários — Gear Checklist

A trekking gear checklist, saved to the cloud and always within reach — no more paper lists getting lost between the daypack and the cargo bag.

A web app for members of the **Legendários** trekking group to organize what to pack in their two trail bags (attack pack and cargo pack) and what's still left to buy, with progress saved per user and synced in real time.

> This is the actual app used by the group in production — login is done with a real Google account, and data lives in the group's real database. There's no separate demo mode; the screenshots below show the interface running with a real account (mine).

![Legendários app login screen](screenshots/01-login.jpg)

## The original problem

Before this, the gear list floated around as loose text or a spreadsheet — every member kept their own version, with no standard split between the daypack (the one that stays with you the whole trail) and the cargo pack (handed over at check-in, only accessed at pre-set points). Easy to forget an item, easy to lose track of what's already packed or bought.

## The solution

```
Google login
      ↓
Profile created in Supabase (name, member number, trail, first TOP)
      ↓
Default checklist auto-seeded (3 packs, sections, items and sub-items)
      ↓
Progress checked item by item, synced in real time to the cloud
```

The result: every member opens the app and sees exactly what's left to pack in each bag, and can adjust the list (add, edit, remove items) without touching anyone else's.

## The checklist itself

- **Three packs organized as tabs** — Daypack, Cargo, and To Buy — each with its own progress and accent color
- **Numbered, collapsible sections** (General, Hygiene + Health, Food, Other), each showing a completed-item count
- **Items with sub-items** — e.g. "Head lamp" nested with "3 batteries," each checkable on its own
- **Optional notes, quantity, and link** per item (e.g. suggested model, purchase link)
- **Inline editing of pack suggestion and size** directly in the text, no modal needed
- **Add, edit, and delete items** in any section, at any time
- **Overall and per-pack progress bar**, updating in real time as items get checked
- **"Reset all"** with confirmation, to start fresh before a new trip

![Daypack checklist](screenshots/02-checklist-ataque.jpg)
![Cargo pack checklist](screenshots/03-checklist-cargueira.jpg)
![Shopping list](screenshots/04-checklist-comprar.jpg)
![Item edit modal](screenshots/05-editar-item.jpg)

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | Plain HTML, CSS and JavaScript — no framework, no build step |
| Backend / data | [Supabase](https://supabase.com) (Postgres + Realtime) |
| Auth | Supabase Auth with Google OAuth login |
| Typography | Google Fonts (Bitter + Work Sans) |

## Why no framework

The whole app lives in a single `index.html`. That's a deliberate choice: it's a small project with a well-defined scope, for one specific group — no bundler, no build pipeline, no dependencies beyond the Supabase JS client loaded from a CDN. Any browser can open the file directly, with no deploy step, and maintenance stays trivial: one person, with no frontend stack, can edit the file and ship it.

Data security doesn't rely on hiding the Supabase `anon key` (it's meant to live client-side) — it relies on the Row Level Security policies configured on the database, which restrict every user to reading and writing only their own data.

## Architecture

All the logic lives in [`index.html`](index.html):
- Supabase tables used: `profiles`, `checklist_items`, `pack_meta`
- Default item template (`TEMPLATE`) used to seed a new user's checklist on first login
- Auth and sign-up flow (`boot`, `afterLogin`, `seedDefaultItems`)
- Pack and section rendering (`renderPack`, `buildSections`)

## Running locally

No build step — just serve the static file:

```bash
git clone https://github.com/andrescultori/lgnd-checklist.git
cd lgnd-checklist
python3 -m http.server 8000
# open http://localhost:8000
```

To run it with your own data (instead of the real Legendários database), create a Supabase project, replicate the `profiles`, `checklist_items`, and `pack_meta` tables, and swap `SUPABASE_URL` and `SUPABASE_ANON_KEY` at the top of the `<script>` in `index.html`.

---

*This repository is made public for professional portfolio purposes. It's the real system in production for the Legendários group — see the license section for the code's terms of use.*

Built by [André Scultori](https://github.com/andrescultori)  ·  © 2026  ·  [GitHub](https://github.com/andrescultori/lgnd-checklist)
