-- Feature "Comprar": toggle de carrinho em qualquer item (parent ou filho),
-- que faz o item aparecer também na aba Comprar, mesclado com os itens
-- manuais que já existem no pack 'comprar'. Adiciona também o conserto de
-- indentação de dois pares item/subitem que ficaram mal aninhados em
-- algumas contas já existentes.
--
-- Não toca em lgndcheck_profiles, lgndcheck_pack_meta, lgndcheck_presets,
-- lgndcheck_entitlements, lgndcheck_list_backups, lgndcheck_share_rate_limit,
-- nem em nenhuma tabela de outro app (portfolio_*, onica_*, blayafunilaria_*,
-- lgnddoc_*, pm_*, sports_*).

-- ============================================================
-- 1) SCHEMA
-- ============================================================

alter table public.lgndcheck_checklist_items
  add column comprar boolean not null default false,
  add column buy_name text,
  add column buy_qty int not null default 1 check (buy_qty between 1 and 999),
  add column comprado boolean not null default false;

comment on column public.lgndcheck_checklist_items.comprar is 'Item marcado para aparecer também na aba Comprar (mesclado por buy_name).';
comment on column public.lgndcheck_checklist_items.buy_name is 'Nome usado para mesclar este item com outros na aba Comprar. Null = usa o title.';
comment on column public.lgndcheck_checklist_items.buy_qty is 'Quantidade usada na soma da aba Comprar (1 a 999).';
comment on column public.lgndcheck_checklist_items.comprado is 'Marcado como comprado na aba Comprar. Independente do campo checked (separado/empacotado).';

-- As policies de RLS da tabela (select/insert/update/delete por
-- user_id = auth.uid()) e os grants (tabela inteira, sem coluna
-- restrita) já cobrem as 4 colunas novas automaticamente — não há
-- view nem grant específico de coluna que precise de ajuste.

-- ============================================================
-- 2) BACKFILL — comprar/comprado ficam false (valor padrão da coluna já
--    cobre as linhas existentes). Só buy_name/buy_qty são preenchidos.
-- ============================================================

-- Regra geral, para toda linha (parent ou filho): se o title começa com um
-- número seguido de espaço, isso é a quantidade e o resto (capitalizado) é
-- o nome de compra ("2 barrinhas de cereal" -> buy_qty 2, buy_name
-- "Barrinhas de cereal"). Sem número no começo: buy_qty 1, buy_name = title.
with base as (
  select
    id,
    (regexp_match(title, '^([0-9]+)\s+(.*)$'))[1] as qty_str,
    (regexp_match(title, '^([0-9]+)\s+(.*)$'))[2] as rest
  from public.lgndcheck_checklist_items
)
update public.lgndcheck_checklist_items t
set
  buy_qty = coalesce(b.qty_str::int, 1),
  buy_name = case
    when b.rest is not null then upper(left(b.rest, 1)) || substring(b.rest from 2)
    else t.title
  end
from base b
where b.id = t.id;

-- Pack 'comprar': a quantidade mora no note, não no title ("2", "6", "2
-- peq"); sobrescreve o buy_qty calculado acima pra esse pack.
with base as (
  select id, (regexp_match(note, '^([0-9]+)'))[1] as qty_str
  from public.lgndcheck_checklist_items
  where pack = 'comprar'
)
update public.lgndcheck_checklist_items t
set buy_qty = coalesce(b.qty_str::int, 1)
from base b
where b.id = t.id;

-- Casos específicos onde o nome de compra precisa ficar igual ao de outra
-- fonte pra mesclar certo na aba Comprar (os dois primeiros já davam esse
-- resultado pela regra geral — reforçados aqui só por clareza/robustez).
update public.lgndcheck_checklist_items
set buy_name = 'Pilhas', buy_qty = 3
where parent_id is not null and title = '3 pilhas';

update public.lgndcheck_checklist_items
set buy_name = 'Pilhas'
where title = 'Pilhas extras';

update public.lgndcheck_checklist_items
set buy_name = 'Pilhas'
where pack = 'comprar' and title = 'Pilhas';

update public.lgndcheck_checklist_items
set buy_name = 'Manta térmica'
where title = 'Manta térmica';

-- Itens manuais do pack 'comprar' já usavam o campo checked como "já
-- comprei" (era a única marcação que existia ali antes desta feature).
-- Carrega esse histórico pro novo campo comprado, que passa a ser o único
-- usado pela aba Comprar a partir de agora.
update public.lgndcheck_checklist_items
set comprado = checked
where pack = 'comprar';

-- ============================================================
-- 3) CONSERTO DE INDENTAÇÃO — achata "Chinelo" (filho de "Roupa p/
--    dormir") e "Tênis extra" (filho de "Roupa p/ voltar") pra item de
--    primeiro nível, bem depois do antigo pai, na mesma seção. Só nas
--    linhas que ainda batem título do filho + título do pai (quem já
--    editou um dos dois títulos fica como está).
-- ============================================================

do $$
declare
  v_pair record;
  v_child record;
begin
  for v_pair in
    select * from (values
      ('Chinelo', 'Roupa p/ dormir'),
      ('Tênis extra', 'Roupa p/ voltar')
    ) as t(child_title, parent_title)
  loop
    for v_child in
      select c.id as child_id, c.user_id, c.pack, c.section_title, c.section_order,
             p.item_order as parent_item_order
      from public.lgndcheck_checklist_items c
      join public.lgndcheck_checklist_items p on p.id = c.parent_id
      where c.title = v_pair.child_title and p.title = v_pair.parent_title
    loop
      update public.lgndcheck_checklist_items
      set item_order = item_order + 1
      where user_id = v_child.user_id and pack = v_child.pack
        and section_title = v_child.section_title and section_order = v_child.section_order
        and parent_id is null
        and item_order > v_child.parent_item_order;

      update public.lgndcheck_checklist_items
      set parent_id = null, item_order = v_child.parent_item_order + 1
      where id = v_child.child_id;
    end loop;
  end loop;
end;
$$;

-- ============================================================
-- 4) FUNÇÕES DE SNAPSHOT — passam a levar comprar/buy_name/buy_qty
--    (nunca comprado, que é estado de compra em andamento, não faz
--    parte do molde salvo). Chaves ausentes num snapshot antigo são
--    tratadas como false/null/1, então presets e o snapshot base
--    anteriores a esta migration continuam aplicando normalmente.
-- ============================================================

create or replace function public._lgndcheck_build_snapshot(p_user uuid, p_include_checked boolean default false)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_packs jsonb := '[]'::jsonb;
  v_pack record;
  v_sections jsonb;
  v_sec record;
  v_items jsonb;
  v_item record;
  v_children jsonb;
  v_child record;
  v_item_obj jsonb;
  v_sugestao text;
  v_tamanho text;
begin
  for v_pack in
    select distinct pack from public.lgndcheck_checklist_items
    where user_id = p_user
    order by pack
  loop
    v_sections := '[]'::jsonb;

    for v_sec in
      select distinct section_title, section_order
      from public.lgndcheck_checklist_items
      where user_id = p_user and pack = v_pack.pack and parent_id is null
      order by section_order
    loop
      v_items := '[]'::jsonb;

      for v_item in
        select * from public.lgndcheck_checklist_items
        where user_id = p_user and pack = v_pack.pack
          and section_title = v_sec.section_title and section_order = v_sec.section_order
          and parent_id is null
        order by item_order
      loop
        v_children := '[]'::jsonb;

        for v_child in
          select * from public.lgndcheck_checklist_items
          where parent_id = v_item.id
          order by item_order
        loop
          v_children := v_children || jsonb_build_array(
            jsonb_build_object(
              'title', v_child.title, 'note', v_child.note, 'quantity', v_child.quantity,
              'link', v_child.link, 'order', v_child.item_order,
              'comprar', v_child.comprar, 'buy_name', v_child.buy_name, 'buy_qty', v_child.buy_qty
            ) || case when p_include_checked
                   then jsonb_build_object('checked', v_child.checked)
                   else '{}'::jsonb end
          );
        end loop;

        v_item_obj := jsonb_build_object(
          'title', v_item.title, 'note', v_item.note, 'quantity', v_item.quantity,
          'link', v_item.link, 'obrigatorio', v_item.obrigatorio, 'order', v_item.item_order,
          'comprar', v_item.comprar, 'buy_name', v_item.buy_name, 'buy_qty', v_item.buy_qty,
          'children', v_children
        );
        if p_include_checked then
          v_item_obj := v_item_obj || jsonb_build_object('checked', v_item.checked);
        end if;
        v_items := v_items || jsonb_build_array(v_item_obj);
      end loop;

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'title', v_sec.section_title, 'order', v_sec.section_order, 'items', v_items
      ));
    end loop;

    select sugestao, tamanho into v_sugestao, v_tamanho
    from public.lgndcheck_pack_meta
    where user_id = p_user and pack = v_pack.pack;

    v_packs := v_packs || jsonb_build_array(jsonb_build_object(
      'pack', v_pack.pack, 'sugestao', v_sugestao, 'tamanho', v_tamanho, 'sections', v_sections
    ));
  end loop;

  return jsonb_build_object('version', 1, 'packs', v_packs);
end;
$$;

create or replace function public._lgndcheck_restore_items(p_user uuid, p_snapshot jsonb, p_force_unchecked boolean)
returns text[]
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_pack jsonb;
  v_sec jsonb;
  v_item jsonb;
  v_child jsonb;
  v_new_parent_id uuid;
  v_known_packs text[] := array['ataque','cargueira','comprar'];
  v_avisos text[] := '{}';
begin
  delete from public.lgndcheck_checklist_items where user_id = p_user;
  delete from public.lgndcheck_pack_meta where user_id = p_user;

  for v_pack in select * from jsonb_array_elements(coalesce(p_snapshot->'packs', '[]'::jsonb))
  loop
    if not (v_pack->>'pack' = any(v_known_packs)) then
      v_avisos := v_avisos || (v_pack->>'pack');
      continue;
    end if;

    insert into public.lgndcheck_pack_meta (user_id, pack, sugestao, tamanho)
    values (p_user, v_pack->>'pack', v_pack->>'sugestao', v_pack->>'tamanho');

    for v_sec in select * from jsonb_array_elements(coalesce(v_pack->'sections', '[]'::jsonb))
    loop
      for v_item in select * from jsonb_array_elements(coalesce(v_sec->'items', '[]'::jsonb))
      loop
        insert into public.lgndcheck_checklist_items
          (user_id, pack, section_title, section_order, item_order, title, note, quantity, link,
           obrigatorio, checked, comprar, buy_name, buy_qty)
        values (
          p_user, v_pack->>'pack', v_sec->>'title', coalesce((v_sec->>'order')::int, 0),
          coalesce((v_item->>'order')::int, 0), v_item->>'title', v_item->>'note', v_item->>'quantity',
          v_item->>'link', coalesce((v_item->>'obrigatorio')::boolean, false),
          case when p_force_unchecked then false else coalesce((v_item->>'checked')::boolean, false) end,
          coalesce((v_item->>'comprar')::boolean, false),
          v_item->>'buy_name',
          coalesce((v_item->>'buy_qty')::int, 1)
        )
        returning id into v_new_parent_id;

        for v_child in select * from jsonb_array_elements(coalesce(v_item->'children', '[]'::jsonb))
        loop
          insert into public.lgndcheck_checklist_items
            (user_id, pack, section_title, section_order, item_order, title, note, quantity, link,
             obrigatorio, parent_id, checked, comprar, buy_name, buy_qty)
          values (
            p_user, v_pack->>'pack', v_sec->>'title', coalesce((v_sec->>'order')::int, 0),
            coalesce((v_child->>'order')::int, 0), v_child->>'title', v_child->>'note', v_child->>'quantity',
            v_child->>'link', coalesce((v_child->>'obrigatorio')::boolean, false), v_new_parent_id,
            case when p_force_unchecked then false else coalesce((v_child->>'checked')::boolean, false) end,
            coalesce((v_child->>'comprar')::boolean, false),
            v_child->>'buy_name',
            coalesce((v_child->>'buy_qty')::int, 1)
          );
        end loop;
      end loop;
    end loop;
  end loop;

  return v_avisos;
end;
$$;

-- _lgndcheck_snapshot_check: aceita as 3 chaves novas (por item e por
-- filho) quando presentes, e valida tipo/faixa. Ausência da chave nunca é
-- erro (retrocompatível com presets e com o snapshot base anteriores).
create or replace function public._lgndcheck_snapshot_check(p_data jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_count int;
  v_campos_invalidos boolean;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object'
     or not (p_data ? 'packs') or jsonb_typeof(p_data->'packs') <> 'array' then
    raise exception using errcode = 'P0001', message = 'formato_invalido';
  end if;

  if octet_length(p_data::text) > 200 * 1024 then
    raise exception using errcode = 'P0001', message = 'preset_muito_grande';
  end if;

  select coalesce(sum(
    1 + jsonb_array_length(coalesce(it->'children', '[]'::jsonb))
  ), 0)
  into v_count
  from jsonb_array_elements(p_data->'packs') as pack
  cross join lateral jsonb_array_elements(coalesce(pack->'sections', '[]'::jsonb)) as sec
  cross join lateral jsonb_array_elements(coalesce(sec->'items', '[]'::jsonb)) as it;

  if v_count > 600 then
    raise exception using errcode = 'P0001', message = 'muitos_itens';
  end if;

  select exists(
    select 1
    from jsonb_array_elements(p_data->'packs') as pack
    cross join lateral jsonb_array_elements(coalesce(pack->'sections', '[]'::jsonb)) as sec
    cross join lateral jsonb_array_elements(coalesce(sec->'items', '[]'::jsonb)) as it
    cross join lateral (
      select it as node
      union all
      select ch as node from jsonb_array_elements(coalesce(it->'children', '[]'::jsonb)) as ch
    ) as nodes
    where
      (case when nodes.node ? 'comprar'
            then jsonb_typeof(nodes.node->'comprar') <> 'boolean'
            else false end)
      or
      (case when nodes.node ? 'buy_qty' then
         case when jsonb_typeof(nodes.node->'buy_qty') = 'number'
                   and (nodes.node->>'buy_qty') ~ '^[0-9]+$'
                   and (nodes.node->>'buy_qty')::int between 1 and 999
              then false
              else true
         end
       else false end)
      or
      (case when nodes.node ? 'buy_name'
            then jsonb_typeof(nodes.node->'buy_name') not in ('string', 'null')
            else false end)
  ) into v_campos_invalidos;

  if v_campos_invalidos then
    raise exception using errcode = 'P0001', message = 'campos_compra_invalidos';
  end if;
end;
$$;
