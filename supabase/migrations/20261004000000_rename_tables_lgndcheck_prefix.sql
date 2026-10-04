-- Isola o schema deste app dentro do projeto Supabase compartilhado
-- (ref rbtcgurgjoounqwokygj, compartilhado com outras aplicações —
-- ex: portfolio_admins/portfolio_projects de outro projeto).
--
-- ALTER TABLE ... RENAME TO preserva dados, índices, foreign keys,
-- triggers e políticas de RLS automaticamente (todos permanecem
-- associados à tabela pelo OID interno, não pelo nome) — confirmado
-- antes de aplicar: nenhuma policy, trigger ou função do schema
-- referencia esses nomes de tabela literalmente no corpo, e nenhuma
-- view depende delas.

alter table public.profiles rename to lgndcheck_profiles;
alter table public.checklist_items rename to lgndcheck_checklist_items;
alter table public.pack_meta rename to lgndcheck_pack_meta;
