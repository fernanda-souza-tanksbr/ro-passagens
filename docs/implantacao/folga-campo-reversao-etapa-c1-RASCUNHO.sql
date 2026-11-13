-- REVERSAO C1 ANTES DE C2: SOMENTE GRANTS E FUNCOES NOVAS C1.
-- Nao remove nem altera tabelas/dados da Etapa A ou B.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $c1_rollback$
begin
  if to_regprocedure('ro_private.autorizar_acesso_folga(uuid)') is null
  then raise exception 'REVERSAO_C1_HELPER_AUSENTE';end if;
  if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia') is distinct from false
  then raise exception 'REVERSAO_C1_PROIBIDA_COM_FLUXO_ATIVO';end if;
  if exists(select 1 from public.ro_folga_alocacoes)
     or exists(select 1 from ro_private.folga_criacao_contexto)
     or exists(select 1 from public.ro_folga_distancia_auditoria)
  then raise exception 'REVERSAO_C1_DADOS_NOVOS_EXISTENTES';end if;
  if position('ro_private.autorizar_acesso_folga' in pg_get_functiondef('public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)'::regprocedure))=0
  then raise exception 'REVERSAO_C1_RPC_ALTERADA';end if;
end;
$c1_rollback$;

revoke execute on function public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean) from authenticated;
revoke execute on function public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid) from authenticated;
revoke execute on function public.ro_corrigir_distancia_folga(uuid,integer,text) from authenticated;

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
CREATE OR REPLACE FUNCTION public.ro_consultar_contexto_distancia_folga(p_funcionario_id uuid, p_obra_id uuid, p_colaborador_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_funcionario uuid:=p_funcionario_id;
  v_canonico_colaborador uuid;
  v_vinculo uuid;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_km integer;
  v_estado text;
  v_ultima date;
  v_futura uuid;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if p_obra_id is null or (p_funcionario_id is null and p_colaborador_id is null) then
    raise exception 'IDENTIDADE_CC_OBRIGATORIOS';
  end if;
  if p_colaborador_id is not null then
    select e.funcionario_id into v_vinculo
    from public.ro_funcionarios_enderecos_privados e
    where e.id=p_colaborador_id and e.ativo;
    if not found then raise exception 'COLABORADOR_INATIVO_OU_INEXISTENTE'; end if;
    if p_funcionario_id is not null and p_funcionario_id is distinct from v_vinculo then
      raise exception 'VINCULO_FUNCIONARIO_INCONSISTENTE';
    end if;
    v_funcionario:=v_vinculo;
    if v_funcionario is null then v_canonico_colaborador:=p_colaborador_id; end if;
  elsif public.ro_funcionario_disponivel_para_usuario(auth.uid(),v_funcionario) is distinct from true then
    raise exception 'FUNCIONARIO_INDISPONIVEL';
  end if;
  if not exists (
    select 1 from public.ro_catalogo_centros_custo() c where c.id=p_obra_id
  ) then raise exception 'CENTRO_CUSTO_INDISPONIVEL'; end if;
  select * into v_atual from public.ro_folga_alocacoes
  where funcionario_id is not distinct from v_funcionario
    and colaborador_id is not distinct from v_canonico_colaborador
    and encerrada_em is null
  order by iniciada_em desc limit 1;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    v_estado:='reutilizar';v_km:=v_atual.distancia_km;
  else
    select * into v_anterior from public.ro_folga_alocacoes
    where funcionario_id is not distinct from v_funcionario
      and colaborador_id is not distinct from v_canonico_colaborador
      and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;
    if v_anterior.id is not null then
      v_estado:='confirmar';v_km:=v_anterior.distancia_km;
    else
      v_estado:='informar';v_km:=null;
    end if;
  end if;

  select s.data_ida into v_ultima
  from public.ro_passagem_solicitacoes s
  where ((v_funcionario is not null and s.funcionario_id=v_funcionario)
       or (v_funcionario is null and s.colaborador_id=v_canonico_colaborador))
    and s.motivo='folga_campo'
    and s.status='finalizada'
    and s.aprovacao_status in ('aprovada','dispensada')
    and s.data_ida <= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
  order by s.data_ida desc,s.id desc limit 1;

  if v_funcionario is not null then
    v_futura:=public.ro_funcionario_possui_folga_futura_ativa(v_funcionario,null);
  else
    select s.id into v_futura from public.ro_passagem_solicitacoes s
    where s.colaborador_id=v_canonico_colaborador and s.motivo='folga_campo'
      and s.excluida_em is null
      and s.data_ida >= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
      and s.status in ('solicitada','em_andamento','passagem_comprada')
      and s.aprovacao_status is distinct from 'reprovada'
    order by s.data_ida,s.created_at limit 1;
  end if;
  return pg_catalog.jsonb_build_object(
    'funcionario_id',v_funcionario,'colaborador_id',p_colaborador_id,
    'obra_id',p_obra_id,
    'distancia_km',v_km,'retorno_ao_cc',v_estado='confirmar',
    'estado',v_estado,'ultima_folga_data_ida',v_ultima,
    'proxima_folga_prevista',case when v_km is not null and v_ultima is not null
      then v_ultima+(select intervalo_dias from ro_private.regime_folga_km(v_km))
      else null end,
    'solicitacao_futura_existente_id',v_futura
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.ro_corrigir_distancia_folga(p_alocacao_id uuid, p_nova_distancia_km integer, p_justificativa text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  -- A funcao privada exige coordenador/gerente ou RO ativo globalmente,
  -- justificativa e lock por funcionario; nunca toca snapshots historicos.
  return ro_private.corrigir_distancia_folga(
    p_alocacao_id,p_nova_distancia_km,p_justificativa
  );
end;
$function$
;

drop function ro_private.autorizar_acesso_folga(uuid);
commit;
