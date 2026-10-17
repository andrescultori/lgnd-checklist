-- Completa a feature de Presets do usuário: as duas únicas funções que
-- faltavam (ambas usam DELETE) depois que tabelas, helpers e as outras 7
-- RPCs já tinham sido aplicadas direto no banco em sessão anterior.
--
-- _lgndcheck_restore_items existia só como um stub vazio (criado durante o
-- diagnóstico de um timeout de ferramenta); esta migration substitui pela
-- versão real. lgndcheck_desfazer_ultima_substituicao ainda não existia.
--
-- Não altera nenhuma outra função, tabela, policy, trigger do Make, nem
-- dados reais.

-- Stub de teste órfão (ver diagnóstico na conversa) — sem uso, sem dependentes.
drop function if exists public._lgndcheck_test_stub2(uuid);

-- Apaga a lista atual do usuário e recria a partir de um snapshot
-- {version,packs:[{pack,sugestao,tamanho,sections:[{title,order,items:[{title,
-- note,quantity,link,obrigatorio,order,checked,children:[...]}]}]}]}.
-- Ignora packs que a versão atual do app não conhece e devolve os nomes
-- ignorados (pra versões futuras com abas editáveis).
-- p_force_unchecked=true zera as marcações (usado por _lgndcheck_presets_apply,
-- que já grava o backup com marcações antes de chamar esta função);
-- p_force_unchecked=false preserva o que veio no snapshot (usado só pelo
-- desfazer, restaurando o backup exatamente como estava).
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
          (user_id, pack, section_title, section_order, item_order, title, note, quantity, link, obrigatorio, checked)
        values (
          p_user, v_pack->>'pack', v_sec->>'title', coalesce((v_sec->>'order')::int, 0),
          coalesce((v_item->>'order')::int, 0), v_item->>'title', v_item->>'note', v_item->>'quantity',
          v_item->>'link', coalesce((v_item->>'obrigatorio')::boolean, false),
          case when p_force_unchecked then false else coalesce((v_item->>'checked')::boolean, false) end
        )
        returning id into v_new_parent_id;

        for v_child in select * from jsonb_array_elements(coalesce(v_item->'children', '[]'::jsonb))
        loop
          insert into public.lgndcheck_checklist_items
            (user_id, pack, section_title, section_order, item_order, title, note, quantity, link, obrigatorio, parent_id, checked)
          values (
            p_user, v_pack->>'pack', v_sec->>'title', coalesce((v_sec->>'order')::int, 0),
            coalesce((v_child->>'order')::int, 0), v_child->>'title', v_child->>'note', v_child->>'quantity',
            v_child->>'link', coalesce((v_child->>'obrigatorio')::boolean, false), v_new_parent_id,
            case when p_force_unchecked then false else coalesce((v_child->>'checked')::boolean, false) end
          );
        end loop;
      end loop;
    end loop;
  end loop;

  return v_avisos;
end;
$$;

-- Restaura o backup mais recente do usuário (com as marcações como estavam)
-- e o apaga, pra não poder desfazer duas vezes.
create or replace function public.lgndcheck_desfazer_ultima_substituicao()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_backup public.lgndcheck_list_backups;
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'nao_autenticado';
  end if;

  select * into v_backup from public.lgndcheck_list_backups where user_id = v_user;
  if not found then
    raise exception using errcode = 'P0002', message = 'sem_backup';
  end if;

  perform public._lgndcheck_restore_items(v_user, v_backup.data, false);
  delete from public.lgndcheck_list_backups where user_id = v_user;

  return jsonb_build_object('ok', true);
end;
$$;

-- Permissões: funções novas nascem com EXECUTE pra PUBLIC por padrão no
-- Postgres, então revogamos explicitamente de anon (sempre) e de
-- authenticated no helper interno (só é chamado de dentro de outra função
-- SECURITY DEFINER, nunca direto via RPC).
revoke execute on function public._lgndcheck_restore_items(uuid, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.lgndcheck_desfazer_ultima_substituicao() from public, anon;
grant execute on function public.lgndcheck_desfazer_ultima_substituicao() to authenticated;
