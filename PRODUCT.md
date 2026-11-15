# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
Members of the Legendários trekking group, preparing the gear for a trail. Confirmed situations: packing at home (checking items off before the trip) and shopping for what is still missing. Group leaders are a confirmed secondary audience (they share presets with other members).

Not confirmed: use on the move (at check-in or the trailhead). Do not design around low-signal, one-handed field use unless the owner says so.

## Product Purpose
A free web app where each member keeps a personal gear checklist split across the group's two trail bags (daypack and cargo pack) plus a "to buy" list, with progress saved to the cloud per user. It replaces loose texts and spreadsheets that every member kept in their own version. Success: a member opens the app and sees exactly what is left to pack or buy, and can adapt the list without touching anyone else's.

## Positioning
Three things a generic notes app or spreadsheet could not truthfully claim:
- shareable presets: a member saves their list as a mold and shares it by a 10-character code;
- the group's real default list: new users are seeded with the Legendários standard gear list (sections, items, sub-items);
- free and saved to the cloud, with Google login.

## Operating Context
Run by one person (André Scultori) as a personal project, in production for the group. Login is a real Google account; data lives in a shared Supabase project. Single `index.html` plus `admin.html` and `privacidade.html`, no framework or build step. Admin tools exist only for the owner.

## Capabilities and Constraints
- Three packs as tabs: Ataque (daypack), Cargueira (cargo), Comprar (to buy, automatic from items marked to buy).
- Numbered collapsible sections, items with sub-items, notes, quantity, link, inline editing.
- Presets: 1 per user on the free tier (backend supports more), restore with confirmation and one-step undo, sharing by code.
- Optional contact consent (`aceita_contato`) used by the owner for updates and other projects.
- UI language is Brazilian Portuguese only; keep it that way.
- No ads, no trackers, no paywall; this matches the published privacy page.
- Undecided: a paid tier with more presets (backend ready, no purchase flow), self-service account deletion, LGPD contact channel.

## Brand Commitments
Keep the Legendários name and the existing white logo (`logo-legendarios-branco.png`) as they are. Do not invent endorsements by the group or its leadership.

## Evidence on Hand
- `README.md` / `README.en.md`: problem, solution, data model.
- `screenshots/`: five screens of the live app.
- `logo-legendarios-branco.png`, `icon-180.png`.
- The default checklist template (`TEMPLATE` in `index.html`).
- Absent and must not be fabricated: testimonials, member counts, reviews, group endorsements, benchmarks, pricing.

## Product Principles
1. Progress is the point: what is left to pack or buy is visible at a glance.
2. Each member owns their list; nothing a member does changes anyone else's.
3. Sharing is explicit and reversible; a shared code never exposes a member's email.
4. Stay free, tracker-free and simple to maintain by one person.
5. Speak the group's language (pt-BR, direct, trail vocabulary).
