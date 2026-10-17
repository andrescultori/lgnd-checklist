-- Feature "Presets do usuário": salvar a lista atual como preset, restaurar
-- (preset próprio, preset compartilhado ou lista básica), desfazer a última
-- restauração, e compartilhar um preset por código/link.
--
-- Mantém o padrão já usado neste app dentro do projeto Supabase compartilhado:
-- tudo em `public`, prefixo `lgndcheck_`, RLS ligado, privilégios de `anon`
-- revogados, escrita só via RPC SECURITY DEFINER. Não toca em
-- lgndcheck_profiles, portfolio_*, nem onica_*.

-- ============================================================
-- TABELAS
-- ============================================================

create table public.lgndcheck_presets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lgndcheck_profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  data jsonb not null,
  share_code text unique,
  shared_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index lgndcheck_presets_user_id_idx on public.lgndcheck_presets(user_id);
comment on table public.lgndcheck_presets is 'Presets de checklist salvos pelo usuário (snapshot sem marcações). Escrita só via RPC.';

create table public.lgndcheck_entitlements (
  user_id uuid primary key references public.lgndcheck_profiles(id) on delete cascade,
  max_presets int not null default 1
);
comment on table public.lgndcheck_entitlements is 'Limite de presets por usuário. Sem linha = limite padrão (1). Escrita só por service_role.';

create table public.lgndcheck_list_backups (
  user_id uuid primary key references public.lgndcheck_profiles(id) on delete cascade,
  reason text not null check (reason in ('reset_base','apply_preset','apply_shared')),
  data jsonb not null,
  created_at timestamptz not null default now()
);
comment on table public.lgndcheck_list_backups is 'Backup automático (com marcações) da lista do usuário antes de um restaurar. Um por usuário, o mais recente. Escrita só via RPC.';

create table public.lgndcheck_share_rate_limit (
  user_id uuid primary key references public.lgndcheck_profiles(id) on delete cascade,
  window_start timestamptz not null default now(),
  attempts int not null default 0
);
comment on table public.lgndcheck_share_rate_limit is 'Contador de tentativas de uso de código de compartilhamento (10/min). Só acessada internamente pelas RPCs.';

-- ============================================================
-- RLS + GRANTS NAS TABELAS
-- ============================================================

alter table public.lgndcheck_presets enable row level security;
alter table public.lgndcheck_entitlements enable row level security;
alter table public.lgndcheck_list_backups enable row level security;
alter table public.lgndcheck_share_rate_limit enable row level security;

revoke all on public.lgndcheck_presets from anon, authenticated;
revoke all on public.lgndcheck_entitlements from anon, authenticated;
revoke all on public.lgndcheck_list_backups from anon, authenticated;
revoke all on public.lgndcheck_share_rate_limit from anon, authenticated;

grant select on public.lgndcheck_presets to authenticated;
grant select on public.lgndcheck_entitlements to authenticated;
grant select on public.lgndcheck_list_backups to authenticated;
-- lgndcheck_share_rate_limit: nenhum grant — só as funções SECURITY DEFINER tocam nela.

create policy "Usuário vê os próprios presets" on public.lgndcheck_presets
  for select using (user_id = (select auth.uid()));

create policy "Usuário vê o próprio limite" on public.lgndcheck_entitlements
  for select using (user_id = (select auth.uid()));

create policy "Usuário vê o próprio backup" on public.lgndcheck_list_backups
  for select using (user_id = (select auth.uid()));

-- Nenhuma policy de insert/update/delete pra authenticated em nenhuma das 4
-- tabelas: toda escrita passa pelas funções abaixo (SECURITY DEFINER).

-- ============================================================
-- VALIDAÇÃO DE SNAPSHOT (tamanho e contagem de itens)
-- ============================================================

create or replace function public._lgndcheck_snapshot_check(p_data jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_count int;
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
end;
$$;

create or replace function public._lgndcheck_presets_validate_trg()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform public._lgndcheck_snapshot_check(new.data);
  return new;
end;
$$;

create trigger lgndcheck_presets_validate
  before insert or update of data on public.lgndcheck_presets
  for each row execute function public._lgndcheck_presets_validate_trg();

-- ============================================================
-- SNAPSHOT: montar (a partir das tabelas reais) e restaurar
-- ============================================================

-- Monta {version:1, packs:[{pack, sugestao, tamanho, sections:[{title, order,
-- items:[{title, note, quantity, link, obrigatorio, order, checked?, children:[...]}]}]}]}
-- a partir da lista atual do usuário. p_include_checked=false é usado para
-- presets (nunca guardam marcação); true é usado só pra montar o backup.
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
              'link', v_child.link, 'order', v_child.item_order
            ) || case when p_include_checked
                   then jsonb_build_object('checked', v_child.checked)
                   else '{}'::jsonb end
          );
        end loop;

        v_item_obj := jsonb_build_object(
          'title', v_item.title, 'note', v_item.note, 'quantity', v_item.quantity,
          'link', v_item.link, 'obrigatorio', v_item.obrigatorio, 'order', v_item.item_order,
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

-- Apaga a lista atual do usuário e recria a partir de um snapshot
-- {version,packs:[...]}. Ignora packs que a versão atual do app não conhece
-- e devolve os nomes ignorados (pra versões futuras com abas editáveis).
-- p_force_unchecked=true zera as marcações; false preserva o que veio no
-- snapshot (usado só pelo desfazer, restaurando o backup como estava).
create or replace function public._lgndcheck_restore_items(p_user uuid, p_snapshot jsonb, p_force_unchecked boolean)
returns text[]
language plpgsql
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
            (user_id, pack, section_title, section_order, item_order, title, note, quantity, link, parent_id, checked)
          values (
            p_user, v_pack->>'pack', v_sec->>'title', coalesce((v_sec->>'order')::int, 0),
            coalesce((v_child->>'order')::int, 0), v_child->>'title', v_child->>'note', v_child->>'quantity',
            v_child->>'link', v_new_parent_id,
            case when p_force_unchecked then false else coalesce((v_child->>'checked')::boolean, false) end
          );
        end loop;
      end loop;
    end loop;
  end loop;

  return v_avisos;
end;
$$;

-- Grava o backup (com marcações) e aplica o snapshot (sem marcações).
-- Usada por aplicar_preset, aplicar_preset_compartilhado e resetar_para_base.
create or replace function public._lgndcheck_presets_apply(p_user uuid, p_snapshot jsonb, p_reason text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_backup jsonb;
  v_avisos text[];
begin
  perform public._lgndcheck_snapshot_check(p_snapshot);

  v_backup := public._lgndcheck_build_snapshot(p_user, true);
  insert into public.lgndcheck_list_backups (user_id, reason, data, created_at)
  values (p_user, p_reason, v_backup, now())
  on conflict (user_id) do update
    set reason = excluded.reason, data = excluded.data, created_at = excluded.created_at;

  v_avisos := public._lgndcheck_restore_items(p_user, p_snapshot, true);

  return jsonb_build_object('ok', true, 'avisos', to_jsonb(v_avisos));
end;
$$;

-- ============================================================
-- CÓDIGO DE COMPARTILHAMENTO E RATE LIMIT
-- ============================================================

create or replace function public._lgndcheck_generate_share_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; -- Crockford base32 (32 símbolos)
  v_code text := '';
  v_bytes bytea;
  i int;
begin
  v_bytes := extensions.gen_random_bytes(10);
  for i in 0..9 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- 10 tentativas por minuto por usuário, compartilhado entre
-- ver_preset_compartilhado, aplicar_preset_compartilhado e salvar_preset_compartilhado.
create or replace function public._lgndcheck_check_rate_limit(p_user uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_attempts int;
begin
  insert into public.lgndcheck_share_rate_limit (user_id, window_start, attempts)
  values (p_user, now(), 1)
  on conflict (user_id) do update set
    window_start = case when public.lgndcheck_share_rate_limit.window_start < now() - interval '1 minute'
                         then now() else public.lgndcheck_share_rate_limit.window_start end,
    attempts = case when public.lgndcheck_share_rate_limit.window_start < now() - interval '1 minute'
                     then 1 else public.lgndcheck_share_rate_limit.attempts + 1 end
  returning attempts into v_attempts;

  if v_attempts > 10 then
    raise exception using errcode = 'P0001', message = 'muitas_tentativas';
  end if;
end;
$$;

-- ============================================================
-- RPCs PÚBLICAS
-- ============================================================

create or replace function public.lgndcheck_salvar_preset_da_lista_atual(p_nome text, p_id_para_substituir uuid default null)
returns public.lgndcheck_presets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_max int;
  v_count int;
  v_snapshot jsonb;
  v_row public.lgndcheck_presets;
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;
  if p_nome is null or char_length(trim(p_nome)) < 1 or char_length(trim(p_nome)) > 40 then
    raise exception using errcode = 'P0001', message = 'nome_invalido';
  end if;

  v_snapshot := public._lgndcheck_build_snapshot(v_user, false);

  if p_id_para_substituir is not null then
    update public.lgndcheck_presets
    set name = trim(p_nome), data = v_snapshot, updated_at = now()
    where id = p_id_para_substituir and user_id = v_user
    returning * into v_row;
    if not found then
      raise exception using errcode = 'P0002', message = 'preset_nao_encontrado';
    end if;
    return v_row;
  end if;

  select coalesce((select max_presets from public.lgndcheck_entitlements where user_id = v_user), 1) into v_max;
  select count(*) into v_count from public.lgndcheck_presets where user_id = v_user;
  if v_count >= v_max then
    raise exception using errcode = 'P0001', message = 'limite_de_presets';
  end if;

  insert into public.lgndcheck_presets (user_id, name, data)
  values (v_user, trim(p_nome), v_snapshot)
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.lgndcheck_aplicar_preset(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_data jsonb;
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;

  select data into v_data from public.lgndcheck_presets where id = p_id and user_id = v_user;
  if v_data is null then
    raise exception using errcode = 'P0002', message = 'preset_nao_encontrado';
  end if;

  return public._lgndcheck_presets_apply(v_user, v_data, 'apply_preset');
end;
$$;

create or replace function public.lgndcheck_resetar_para_base(p_snapshot_base jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;
  return public._lgndcheck_presets_apply(v_user, p_snapshot_base, 'reset_base');
end;
$$;

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
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;

  select * into v_backup from public.lgndcheck_list_backups where user_id = v_user;
  if not found then
    raise exception using errcode = 'P0002', message = 'sem_backup';
  end if;

  perform public._lgndcheck_restore_items(v_user, v_backup.data, false);
  delete from public.lgndcheck_list_backups where user_id = v_user;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.lgndcheck_compartilhar_preset(p_id uuid, p_ativar boolean)
returns public.lgndcheck_presets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_row public.lgndcheck_presets;
  v_code text;
  v_tries int := 0;
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;

  select * into v_row from public.lgndcheck_presets where id = p_id and user_id = v_user;
  if not found then
    raise exception using errcode = 'P0002', message = 'preset_nao_encontrado';
  end if;

  if not p_ativar then
    update public.lgndcheck_presets
    set share_code = null, shared_at = null, updated_at = now()
    where id = p_id
    returning * into v_row;
    return v_row;
  end if;

  if v_row.share_code is not null then
    return v_row;
  end if;

  loop
    v_tries := v_tries + 1;
    v_code := public._lgndcheck_generate_share_code();
    begin
      update public.lgndcheck_presets
      set share_code = v_code, shared_at = now(), updated_at = now()
      where id = p_id
      returning * into v_row;
      exit;
    exception when unique_violation then
      if v_tries >= 5 then
        raise exception using errcode = 'P0001', message = 'erro_ao_gerar_codigo';
      end if;
    end;
  end loop;

  return v_row;
end;
$$;

create or replace function public.lgndcheck_ver_preset_compartilhado(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_name text;
  v_data jsonb;
  v_owner_full_name text;
  v_primeiro_nome text;
  v_pack jsonb;
  v_sec jsonb;
  v_item jsonb;
  v_contagem jsonb := '[]'::jsonb;
  v_previa jsonb := '[]'::jsonb;
  v_count int;
  v_titulos text[];
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;
  perform public._lgndcheck_check_rate_limit(v_user);

  select p.name, p.data, prof.nome_completo
  into v_name, v_data, v_owner_full_name
  from public.lgndcheck_presets p
  join public.lgndcheck_profiles prof on prof.id = p.user_id
  where p.share_code = p_codigo;

  if v_name is null then
    raise exception using errcode = 'P0002', message = 'codigo_invalido';
  end if;

  v_primeiro_nome := split_part(trim(v_owner_full_name), ' ', 1);

  for v_pack in select * from jsonb_array_elements(coalesce(v_data->'packs', '[]'::jsonb))
  loop
    v_count := 0;
    v_titulos := '{}';
    for v_sec in select * from jsonb_array_elements(coalesce(v_pack->'sections', '[]'::jsonb))
    loop
      for v_item in select * from jsonb_array_elements(coalesce(v_sec->'items', '[]'::jsonb))
      loop
        v_count := v_count + 1 + jsonb_array_length(coalesce(v_item->'children', '[]'::jsonb));
        if array_length(v_titulos, 1) is null or array_length(v_titulos, 1) < 5 then
          v_titulos := v_titulos || (v_item->>'title');
        end if;
      end loop;
    end loop;
    v_contagem := v_contagem || jsonb_build_array(jsonb_build_object('pack', v_pack->>'pack', 'qtd', v_count));
    v_previa := v_previa || jsonb_build_array(jsonb_build_object('pack', v_pack->>'pack', 'titulos', to_jsonb(v_titulos)));
  end loop;

  return jsonb_build_object(
    'nome', v_name,
    'compartilhado_por', v_primeiro_nome,
    'contagem', v_contagem,
    'previa', v_previa
  );
end;
$$;

create or replace function public.lgndcheck_aplicar_preset_compartilhado(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_data jsonb;
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;
  perform public._lgndcheck_check_rate_limit(v_user);

  select data into v_data from public.lgndcheck_presets where share_code = p_codigo;
  if v_data is null then
    raise exception using errcode = 'P0002', message = 'codigo_invalido';
  end if;

  return public._lgndcheck_presets_apply(v_user, v_data, 'apply_shared');
end;
$$;

create or replace function public.lgndcheck_salvar_preset_compartilhado(p_codigo text, p_id_para_substituir uuid default null)
returns public.lgndcheck_presets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_name text;
  v_data jsonb;
  v_max int;
  v_count int;
  v_row public.lgndcheck_presets;
begin
  if v_user is null then raise exception using errcode = '28000', message = 'nao_autenticado'; end if;
  perform public._lgndcheck_check_rate_limit(v_user);

  select name, data into v_name, v_data
  from public.lgndcheck_presets
  where share_code = p_codigo;

  if v_name is null then
    raise exception using errcode = 'P0002', message = 'codigo_invalido';
  end if;

  if p_id_para_substituir is not null then
    update public.lgndcheck_presets
    set name = v_name, data = v_data, updated_at = now()
    where id = p_id_para_substituir and user_id = v_user
    returning * into v_row;
    if not found then
      raise exception using errcode = 'P0002', message = 'preset_nao_encontrado';
    end if;
    return v_row;
  end if;

  select coalesce((select max_presets from public.lgndcheck_entitlements where user_id = v_user), 1) into v_max;
  select count(*) into v_count from public.lgndcheck_presets where user_id = v_user;
  if v_count >= v_max then
    raise exception using errcode = 'P0001', message = 'limite_de_presets';
  end if;

  insert into public.lgndcheck_presets (user_id, name, data)
  values (v_user, v_name, v_data)
  returning * into v_row;

  return v_row;
end;
$$;

-- ============================================================
-- GRANTS NAS FUNÇÕES
-- ============================================================

revoke execute on function public._lgndcheck_snapshot_check(jsonb) from public;
revoke execute on function public._lgndcheck_presets_validate_trg() from public;
revoke execute on function public._lgndcheck_build_snapshot(uuid, boolean) from public;
revoke execute on function public._lgndcheck_restore_items(uuid, jsonb, boolean) from public;
revoke execute on function public._lgndcheck_presets_apply(uuid, jsonb, text) from public;
revoke execute on function public._lgndcheck_generate_share_code() from public;
revoke execute on function public._lgndcheck_check_rate_limit(uuid) from public;

revoke execute on function public.lgndcheck_salvar_preset_da_lista_atual(text, uuid) from public;
revoke execute on function public.lgndcheck_aplicar_preset(uuid) from public;
revoke execute on function public.lgndcheck_resetar_para_base(jsonb) from public;
revoke execute on function public.lgndcheck_desfazer_ultima_substituicao() from public;
revoke execute on function public.lgndcheck_compartilhar_preset(uuid, boolean) from public;
revoke execute on function public.lgndcheck_ver_preset_compartilhado(text) from public;
revoke execute on function public.lgndcheck_aplicar_preset_compartilhado(text) from public;
revoke execute on function public.lgndcheck_salvar_preset_compartilhado(text, uuid) from public;

grant execute on function public.lgndcheck_salvar_preset_da_lista_atual(text, uuid) to authenticated;
grant execute on function public.lgndcheck_aplicar_preset(uuid) to authenticated;
grant execute on function public.lgndcheck_resetar_para_base(jsonb) to authenticated;
grant execute on function public.lgndcheck_desfazer_ultima_substituicao() to authenticated;
grant execute on function public.lgndcheck_compartilhar_preset(uuid, boolean) to authenticated;
grant execute on function public.lgndcheck_ver_preset_compartilhado(text) to authenticated;
grant execute on function public.lgndcheck_aplicar_preset_compartilhado(text) to authenticated;
grant execute on function public.lgndcheck_salvar_preset_compartilhado(text, uuid) to authenticated;
