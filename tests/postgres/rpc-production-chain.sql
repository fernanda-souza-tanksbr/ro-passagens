-- Captured exclusively through pg_get_functiondef (read-only). These are real functions,
-- not permissive stubs. Dependencies must be satisfied before execution.

-- public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)
CREATE OR REPLACE FUNCTION public.ro_criar_folga_campo_com_distancia(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb, p_distancia_declarada_km integer DEFAULT NULL::integer, p_confirma_retorno boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_criado uuid;
  v_funcionario uuid;
  v_colaborador uuid;
  v_canonico_colaborador uuid;
  v_vinculo uuid;
  v_obra uuid;
  v_episodio jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  if p_solicitacao is null or pg_catalog.jsonb_typeof(p_solicitacao) <> 'object'
     or p_solicitacao->>'motivo' is distinct from 'folga_campo' then
    raise exception 'MOTIVO_FOLGA_CAMPO_OBRIGATORIO';
  end if;
  if nullif(p_solicitacao->>'viajante_nome_informado','') is not null then
    raise exception 'VIAJANTE_MANUAL_REQUER_IDENTIDADE_PERSISTIDA';
  end if;
  begin
    v_id := (p_solicitacao->>'id')::uuid;
    v_funcionario := nullif(p_solicitacao->>'funcionario_id','')::uuid;
    v_colaborador := nullif(p_solicitacao->>'colaborador_id','')::uuid;
    v_obra := (p_solicitacao->>'obra_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'IDENTIFICADOR_INVALIDO';
  end;
  if v_id is null or v_obra is null
     or (v_funcionario is null and v_colaborador is null) then
    raise exception 'IDENTIFICADORES_OBRIGATORIOS';
  end if;
  -- Bloqueia o fluxo de KM antes da ativacao e verifica acesso a cadastro privado.
  perform ro_private.autorizar_acesso_folga(v_colaborador);
  -- O cadastro privado e validado pela propria tabela, como no trigger legado.
  -- Quando existe vinculo ao cadastro geral, usa esse funcionario como
  -- identidade canonica (evita separar historicos de uma mesma pessoa).
  -- Sem vinculo, a chave canonica e o colaborador privado.
  if v_colaborador is not null then
    select e.funcionario_id into v_vinculo
    from public.ro_funcionarios_enderecos_privados e
    where e.id=v_colaborador and e.ativo;
    if not found then raise exception 'COLABORADOR_INATIVO_OU_INEXISTENTE'; end if;
    if v_funcionario is not null and v_funcionario is distinct from v_vinculo then
      raise exception 'VINCULO_FUNCIONARIO_INCONSISTENTE';
    end if;
    v_funcionario:=v_vinculo;
    if v_funcionario is null then v_canonico_colaborador:=v_colaborador; end if;
  elsif public.ro_funcionario_disponivel_para_usuario(auth.uid(),v_funcionario) is distinct from true then
    raise exception 'FUNCIONARIO_INDISPONIVEL';
  end if;
  if not exists (
    select 1 from public.ro_catalogo_centros_custo() c
    where c.id=v_obra
  ) then
    raise exception 'CENTRO_CUSTO_INDISPONIVEL';
  end if;
  v_episodio := ro_private.preparar_episodio_folga(
    v_funcionario,v_obra,p_distancia_declarada_km,p_confirma_retorno,
    v_canonico_colaborador
  );
  insert into ro_private.folga_criacao_contexto(
    solicitacao_id,funcionario_id,colaborador_id,obra_id,alocacao_id,
    distancia_km,regime_faixa,intervalo_dias,criado_por
  ) values (
    v_id,v_funcionario,v_canonico_colaborador,v_obra,
    (v_episodio->>'alocacao_id')::uuid,
    (v_episodio->>'distancia_km')::integer,
    v_episodio->>'regime_faixa',
    (v_episodio->>'intervalo_dias')::integer,
    auth.uid()
  );
  -- Preserva validacoes, aprovador, historico e notificacao existentes.
  v_criado := public.ro_criar_solicitacao_com_aprovador(
    p_solicitacao,p_documentos
  );
  if v_criado is distinct from v_id then
    raise exception 'ID_CRIACAO_DIVERGENTE';
  end if;
  -- O BEFORE INSERT deve ter preenchido os snapshots com base no contexto.
  if not exists (
    select 1 from public.ro_passagem_solicitacoes s
    where s.id=v_id
      and s.funcionario_id is not distinct from v_funcionario
      and s.colaborador_id is not distinct from v_colaborador
      and s.obra_id=v_obra
      and s.folga_alocacao_id=(v_episodio->>'alocacao_id')::uuid
      and s.folga_distancia_km=(v_episodio->>'distancia_km')::integer
      and s.folga_intervalo_dias=(v_episodio->>'intervalo_dias')::integer
  ) then
    raise exception 'SNAPSHOT_FOLGA_NAO_APLICADO';
  end if;
  delete from ro_private.folga_criacao_contexto
  where solicitacao_id=v_id and criado_por=auth.uid();
  return v_id;
end;
$function$
;

-- ro_private.preparar_episodio_folga(uuid,uuid,integer,boolean,uuid)
CREATE OR REPLACE FUNCTION ro_private.preparar_episodio_folga(p_funcionario_id uuid, p_obra_id uuid, p_distancia_declarada_km integer, p_confirma_retorno boolean, p_colaborador_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_novo_id uuid;
  v_km integer;
  v_faixa text;
  v_intervalo integer;
  v_transporte text;
  v_acao text;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if pg_catalog.num_nonnulls(p_funcionario_id,p_colaborador_id)<>1
     or p_obra_id is null then
    raise exception 'IDENTIDADE_CC_OBRIGATORIOS';
  end if;
  -- A RPC chamadora deve confirmar autorizacao para criar em nome do funcionario.
  -- Este lock deve ser compartilhado com a validacao de ciclo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(coalesce(p_funcionario_id::text,'privado:'||p_colaborador_id::text), 904)
  );
  select * into v_atual
  from public.ro_folga_alocacoes
  where funcionario_id is not distinct from p_funcionario_id
    and colaborador_id is not distinct from p_colaborador_id and encerrada_em is null
  for update;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    if p_distancia_declarada_km is not null
       and p_distancia_declarada_km <> v_atual.distancia_km then
      raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
    end if;
    v_km:=v_atual.distancia_km;
    v_novo_id:=v_atual.id;
    v_acao:=null;
  else
    select * into v_anterior
    from public.ro_folga_alocacoes
    where funcionario_id is not distinct from p_funcionario_id
      and colaborador_id is not distinct from p_colaborador_id and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;

    if v_anterior.id is not null then
      if p_confirma_retorno is distinct from true then
        raise exception 'CONFIRMACAO_RETORNO_OBRIGATORIA';
      end if;
      if p_distancia_declarada_km is not null
         and p_distancia_declarada_km <> v_anterior.distancia_km then
        raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
      end if;
      v_km:=v_anterior.distancia_km;
      v_acao:='confirmacao';
    else
      if p_distancia_declarada_km is null or p_distancia_declarada_km < 0 then
        raise exception 'DISTANCIA_OBRIGATORIA_OU_INVALIDA';
      end if;
      v_km:=p_distancia_declarada_km;
      v_acao:='declaracao';
    end if;

    if v_atual.id is not null then
      update public.ro_folga_alocacoes
      set encerrada_em=pg_catalog.now()
      where id=v_atual.id;
    end if;
    insert into public.ro_folga_alocacoes(
      funcionario_id,colaborador_id,obra_id,distancia_km,confirmada_em,confirmada_por,origem_alocacao_id
    ) values (
      p_funcionario_id,p_colaborador_id,p_obra_id,v_km,pg_catalog.now(),auth.uid(),v_anterior.id
    ) returning id into v_novo_id;
    insert into public.ro_folga_distancia_auditoria(
      alocacao_id,distancia_anterior_km,distancia_nova_km,
      acao,realizado_por
    ) values (
      v_novo_id,v_anterior.distancia_km,v_km,v_acao,auth.uid()
    );
  end if;

  select faixa,intervalo_dias,transporte
  into v_faixa,v_intervalo,v_transporte
  from ro_private.regime_folga_km(v_km);

  return pg_catalog.jsonb_build_object(
    'alocacao_id',v_novo_id,'obra_id',p_obra_id,
    'funcionario_id',p_funcionario_id,'colaborador_id',p_colaborador_id,
    'distancia_km',v_km,'regime_faixa',v_faixa,
    'intervalo_dias',v_intervalo,'transporte',v_transporte
  );
end;
$function$
;

-- ro_private.autorizar_acesso_folga(uuid)
CREATE OR REPLACE FUNCTION ro_private.autorizar_acesso_folga(p_colaborador_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id=v_user and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= pg_catalog.now())
  ) then
    raise exception 'USUARIO_INATIVO_OU_BLOQUEADO';
  end if;
  if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia')
       is distinct from true then
    raise exception 'FOLGA_CAMPO_KM_AINDA_DESATIVADO';
  end if;
  if p_colaborador_id is not null
     and public.ro_can_view_private_addresses(v_user) is distinct from true then
    raise exception 'COLABORADOR_PRIVADO_ACESSO_NEGADO';
  end if;
end;
$function$
;

-- ro_private.regime_folga_km(integer)
CREATE OR REPLACE FUNCTION ro_private.regime_folga_km(p_km integer)
 RETURNS TABLE(faixa text, intervalo_dias integer, transporte text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select
    case when p_km <= 200 then 'ate_200'
         when p_km <= 600 then '201_600'
         when p_km <= 800 then '601_800'
         when p_km <= 1500 then '801_1500'
         else 'acima_1500' end,
    case when p_km <= 200 then 7
         when p_km <= 600 then 14
         when p_km <= 800 then 45
         else 90 end,
    case when p_km <= 600 then 'onibus'
         when p_km <= 1500 then 'onibus_ou_aviao'
         else 'aviao' end
  where p_km is not null and p_km >= 0;
$function$
;

-- public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.ro_criar_solicitacao_com_aprovador(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_aprovador uuid:=nullif(p_solicitacao->>'aprovador_id','')::uuid;
  v_auto boolean:=false;
  v_dispensa_perfil boolean;
  v_dispensa_desligamento_urgente boolean:=
    p_solicitacao->>'motivo'='desligamento'
    and p_solicitacao->>'desligamento_subtipo'
        in('pedido_demissao','justa_causa');
  v_dispensa boolean;
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;

  v_dispensa_perfil:=public.ro_approval_exempt(auth.uid());
  v_dispensa:=v_dispensa_perfil or v_dispensa_desligamento_urgente;

  if v_dispensa then
    v_aprovador:=null;
  else
    if v_aprovador is null then
      raise exception 'APROVADOR_OBRIGATORIO';
    end if;

    if not public.ro_is_approval_candidate(v_aprovador) then
      raise exception 'APROVADOR_INVALIDO';
    end if;

    v_auto:=v_aprovador=auth.uid() and (auth.uid() = 'c8513a17-0c7c-4a46-a632-b6725652daa9'::uuid or exists(
      select 1
      from public.user_roles r
      where r.user_id=auth.uid()
        and r.role::text='coordenador'
    ));

    if v_aprovador=auth.uid() and not v_auto then
      raise exception 'AUTOAPROVACAO_NAO_PERMITIDA';
    end if;
  end if;

  perform set_config('ro.approval_creation','1',true);

  v_id:=public.ro_criar_solicitacao_colaborador_validada(
    p_solicitacao-'aprovador_id',
    p_documentos
  );

  perform set_config('ro.aprovacao_rpc','1',true);

  update public.ro_passagem_solicitacoes
  set
    aprovador_id=v_aprovador,
    aprovacao_status=
      case
        when v_dispensa then 'dispensada'
        when v_auto then 'aprovada'
        else 'pendente'
      end,
    aprovado_em=
      case
        when v_dispensa or v_auto then now()
      end
  where id=v_id;

  insert into public.ro_passagem_historico(
    solicitacao_id,
    status_anterior,
    status_novo,
    descricao,
    criado_por
  )
  values(
    v_id,
    'solicitada',
    'solicitada',
    case
      when v_dispensa_desligamento_urgente then
        'Aprovação dispensada por regra de desligamento urgente.'
      when v_dispensa_perfil then
        'Aprovação dispensada por regra de perfil (RH, RO, Gerência ou Diretoria).'
      when v_auto then
        'Autoaprovação pelo aprovador responsável autorizado.'
      else
        'Solicitação aguardando aprovação do aprovador responsável.'
    end,
    auth.uid()
  );

  if v_dispensa or v_auto then
    perform public.ro_notificar_equipe_solicitacao_liberada(v_id);
  end if;

  return v_id;
end $function$
;

-- public.ro_criar_solicitacao_colaborador_validada(jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.ro_criar_solicitacao_colaborador_validada(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nome text:=nullif(btrim(regexp_replace(coalesce(p_solicitacao->>'viajante_nome_informado',''),E'\\s+',' ','g')),'');
begin
  if v_nome is not null and not coalesce(public.ro_is_rh_active(auth.uid()),false) then
    raise exception 'VIAJANTE_MANUAL_APENAS_RH';
  end if;
  perform set_config('ro.viajante_nome_informado',coalesce(v_nome,''),true);
  return public.ro_criar_solicitacao_colaborador_validada_pre_rh_manual(
    p_solicitacao-'viajante_nome_informado'-'viajante_modo',p_documentos
  );
end $function$
;

-- public.ro_criar_solicitacao_colaborador_validada_pre_rh_manual(jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.ro_criar_solicitacao_colaborador_validada_pre_rh_manual(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
declare v_id uuid;v_pix text:=btrim(coalesce(p_solicitacao->>'pix_viajante',''));v_hospedagem boolean:=coalesce((p_solicitacao->>'necessita_hospedagem')::boolean,false);v_checkin date:=nullif(p_solicitacao->>'hospedagem_checkin','')::date;v_checkout date:=nullif(p_solicitacao->>'hospedagem_checkout','')::date;
begin
 if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA';end if;
 if v_pix='' then raise exception 'PIX_VIAJANTE_OBRIGATORIO';end if;
 if v_hospedagem and (v_checkin is null or v_checkout is null) then raise exception 'DATAS_HOSPEDAGEM_OBRIGATORIAS';end if;
 if v_hospedagem and v_checkout<v_checkin then raise exception 'CHECKOUT_ANTERIOR_AO_CHECKIN';end if;
 v_id:=public.ro_criar_solicitacao_colaborador_validada_pre_operacional(p_solicitacao,p_documentos);
 update public.ro_passagem_solicitacoes set pix_viajante=v_pix,necessita_hospedagem=v_hospedagem,hospedagem_checkin=case when v_hospedagem then v_checkin end,hospedagem_checkout=case when v_hospedagem then v_checkout end,ida_a_partir_horario=nullif(p_solicitacao->>'ida_a_partir_horario','')::time where id=v_id;
 return v_id;
end $function$
;

-- public.ro_criar_solicitacao_colaborador_validada_pre_operacional(jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.ro_criar_solicitacao_colaborador_validada_pre_operacional(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_colaborador uuid :=
    nullif(p_solicitacao->>'colaborador_id', '')::uuid;

  v_funcionario uuid :=
    nullif(p_solicitacao->>'funcionario_id', '')::uuid;

  v_id uuid :=
    coalesce(
      nullif(p_solicitacao->>'id', '')::uuid,
      gen_random_uuid()
    );

  v_motivo text :=
    nullif(p_solicitacao->>'motivo', '');

  v_doc jsonb;
  v_obj storage.objects%ROWTYPE;
BEGIN

  -- Mantém o comportamento atual para funcionário normal.
  IF v_colaborador IS NULL THEN
    RETURN public.ro_criar_solicitacao_validada(
      p_solicitacao,
      p_documentos
    );
  END IF;

  -- Mantém a validação do cadastro privado e obtém
  -- eventual vínculo com funcionário do Obras.
  SELECT e.funcionario_id
  INTO v_funcionario
  FROM public.ro_funcionarios_enderecos_privados e
  WHERE e.id = v_colaborador
    AND e.ativo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COLABORADOR_INATIVO_OU_INEXISTENTE';
  END IF;


  -- ==========================================================
  -- DOCUMENTOS INTERNOS
  -- Mesmo processamento existente no fluxo normal.
  -- ==========================================================

  FOR v_doc IN
    SELECT value
    FROM jsonb_array_elements(
      coalesce(p_documentos, '[]'::jsonb)
    )
  LOOP

    SELECT o.*
    INTO v_obj
    FROM storage.objects o
    WHERE o.bucket_id = 'ro-documentos-internos'
      AND o.name = v_doc->>'storage_path'
      AND o.owner_id::text = auth.uid()::text;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'DOCUMENTO_NAO_ENCONTRADO_OU_SEM_PERMISSAO';
    END IF;

    IF (v_doc->>'storage_path') NOT LIKE
       v_id::text || '/' || (v_doc->>'categoria') || '/%'
    THEN
      RAISE EXCEPTION 'CAMINHO_DOCUMENTO_INVALIDO';
    END IF;

    IF coalesce(v_obj.metadata->>'mimetype', '')
         <> 'application/pdf'
       OR lower(storage.extension(v_obj.name)) <> 'pdf'
    THEN
      RAISE EXCEPTION 'DOCUMENTO_NAO_PDF';
    END IF;

    IF coalesce(
         (v_obj.metadata->>'size')::bigint,
         0
       ) <= 0
       OR (v_obj.metadata->>'size')::bigint > 10485760
    THEN
      RAISE EXCEPTION 'DOCUMENTO_TAMANHO_INVALIDO';
    END IF;

    INSERT INTO public.ro_passagem_documentos_internos (
      id,
      solicitacao_id,
      categoria,
      storage_path,
      arquivo_nome,
      mime_type,
      tamanho_bytes,
      created_by
    )
    VALUES (
      gen_random_uuid(),
      v_id,
      v_doc->>'categoria',
      v_doc->>'storage_path',
      v_doc->>'arquivo_nome',
      'application/pdf',
      (v_obj.metadata->>'size')::bigint,
      auth.uid()
    );

  END LOOP;


  -- ==========================================================
  -- INSERT PRIVADO ORIGINAL
  -- Preserva colaborador_id, funcionário vinculado e regras atuais.
  -- ==========================================================

  INSERT INTO public.ro_passagem_solicitacoes (
    id,
    colaborador_id,
    funcionario_id,
    obra_id,
    solicitante_id,
    origem,
    destino,
    motivo,
    data_ida,
    data_retorno,
    destino_retorno,
    centro_custo_retorno_id,
    retorno_indefinido,
    centro_custo_destino_id,
    desligamento_subtipo,
    justificativa_excecao_prazo,
    observacoes_solicitante,
    solicitacao_origem_id,
    folga_antecipacao_justificativa,
    destino_residencial_origem,
    destino_residencial_justificativa
  )
  VALUES (
    v_id,
    v_colaborador,
    v_funcionario,
    nullif(p_solicitacao->>'obra_id', '')::uuid,
    auth.uid(),
    p_solicitacao->>'origem',
    p_solicitacao->>'destino',
    v_motivo,
    nullif(p_solicitacao->>'data_ida', '')::date,
    nullif(p_solicitacao->>'data_retorno', '')::date,
    nullif(trim(p_solicitacao->>'destino_retorno'), ''),
    nullif(p_solicitacao->>'centro_custo_retorno_id', '')::uuid,
    coalesce(
      (p_solicitacao->>'retorno_indefinido')::boolean,
      false
    ),
    nullif(p_solicitacao->>'centro_custo_destino_id', '')::uuid,
    nullif(p_solicitacao->>'desligamento_subtipo', ''),
    nullif(
      trim(p_solicitacao->>'justificativa_excecao_prazo'),
      ''
    ),
    nullif(p_solicitacao->>'observacoes_solicitante', ''),
    nullif(p_solicitacao->>'solicitacao_origem_id', '')::uuid,
    nullif(
      trim(p_solicitacao->>'folga_antecipacao_justificativa'),
      ''
    ),
    CASE
      WHEN coalesce(
        (p_solicitacao->>'usar_destino_excepcional')::boolean,
        false
      )
        THEN 'excepcional'
      WHEN v_motivo IN ('ferias', 'folga_campo', 'recesso')
        THEN 'rh'
    END,
    nullif(
      trim(p_solicitacao->>'destino_residencial_justificativa'),
      ''
    )
  );


  -- Auditoria específica já existente do colaborador privado.
  INSERT INTO public.ro_auditoria_interna (
    evento,
    solicitacao_id,
    detalhes,
    criado_por
  )
  VALUES (
    'solicitacao_colaborador_privado_criada',
    v_id,
    jsonb_build_object(
      'colaborador_id',
      v_colaborador,
      'vinculado_obras',
      v_funcionario IS NOT NULL
    ),
    auth.uid()
  );


  -- Mesma auditoria documental existente no fluxo normal.
  INSERT INTO public.ro_auditoria_interna (
    evento,
    solicitacao_id,
    detalhes,
    criado_por
  )
  SELECT
    'documento_interno_anexado',
    v_id,
    jsonb_build_object(
      'categoria',
      d.categoria
    ),
    auth.uid()
  FROM public.ro_passagem_documentos_internos d
  WHERE d.solicitacao_id = v_id;


  RETURN v_id;
END;
$function$
;

-- public.ro_criar_solicitacao_validada(jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.ro_criar_solicitacao_validada(p_solicitacao jsonb, p_documentos jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
declare v_id uuid;v_pix text:=btrim(coalesce(p_solicitacao->>'pix_viajante',''));v_hospedagem boolean:=coalesce((p_solicitacao->>'necessita_hospedagem')::boolean,false);v_checkin date:=nullif(p_solicitacao->>'hospedagem_checkin','')::date;v_checkout date:=nullif(p_solicitacao->>'hospedagem_checkout','')::date;
begin
 if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA';end if;
 if v_pix='' then raise exception 'PIX_VIAJANTE_OBRIGATORIO';end if;
 if v_hospedagem and (v_checkin is null or v_checkout is null) then raise exception 'DATAS_HOSPEDAGEM_OBRIGATORIAS';end if;
 if v_hospedagem and v_checkout<v_checkin then raise exception 'CHECKOUT_ANTERIOR_AO_CHECKIN';end if;
 v_id:=public.ro_criar_solicitacao_validada_pre_operacional(p_solicitacao,p_documentos);
 update public.ro_passagem_solicitacoes set pix_viajante=v_pix,necessita_hospedagem=v_hospedagem,hospedagem_checkin=case when v_hospedagem then v_checkin end,hospedagem_checkout=case when v_hospedagem then v_checkout end,ida_a_partir_horario=nullif(p_solicitacao->>'ida_a_partir_horario','')::time where id=v_id;
 return v_id;
end $function$
;
