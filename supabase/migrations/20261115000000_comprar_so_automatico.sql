-- A aba Comprar deixa de ter itens manuais próprios (pack 'comprar') e
-- passa a ser só o que o usuário marcar com o carrinho 🛒 em qualquer
-- outro item. Os itens manuais que já existiam ali (ex: "Barra de
-- cereal", "Pilhas", "Manta térmica" no pack comprar) duplicavam o que
-- o usuário já tinha marcado em outro lugar.
--
-- Não toca em lgndcheck_profiles, lgndcheck_presets, lgndcheck_entitlements,
-- lgndcheck_list_backups, lgndcheck_share_rate_limit, nem em nenhuma tabela
-- de outro app.

-- ============================================================
-- 1) APAGA OS ITENS MANUAIS DO PACK 'comprar' DE TODOS OS USUÁRIOS
-- ============================================================

delete from public.lgndcheck_checklist_items where pack = 'comprar';
delete from public.lgndcheck_pack_meta where pack = 'comprar';

-- ============================================================
-- 2) _lgndcheck_restore_items: 'comprar' deixa de ser um pack
--    reconhecido num snapshot (preset antigo, backup antigo ou o
--    snapshot base antigo que ainda tenha itens manuais desse pack).
--    Passa pelo mesmo caminho que qualquer pack desconhecido: é
--    ignorado e devolvido em avisos, em vez de recriar itens manuais
--    que não deveriam mais existir.
-- ============================================================

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
  v_known_packs text[] := array['ataque','cargueira'];
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
