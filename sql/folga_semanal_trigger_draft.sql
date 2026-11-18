-- RASCUNHO PARA HOMOLOGACAO ISOLADA; NAO APLICAR EM PRODUCAO.
-- Capturar definicao original e comparar identidade canonica antes da aprovacao.
CREATE OR REPLACE FUNCTION public.ro_validar_ciclo_folga_campo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ciclo jsonb;
  v_proxima date;
  v_anterior uuid;
  v_duplicada uuid;
  v_aprovada boolean := false;
  v_contexto ro_private.folga_criacao_contexto%rowtype;
  v_ultima_data date;
  v_identidade_funcionario uuid;
  v_identidade_chave text;
begin
  -- Atualizacoes de status sem mudanca dos parametros do ciclo preservam
  -- os valores ja registrados, inclusive a aprovacao de antecipacao.
  if tg_op='UPDATE'
     and old.motivo='folga_campo' and new.motivo='folga_campo'
     and new.funcionario_id is not distinct from old.funcionario_id
     and new.colaborador_id is not distinct from old.colaborador_id
     and new.obra_id is not distinct from old.obra_id
     and new.data_ida is not distinct from old.data_ida
     and new.data_retorno is not distinct from old.data_retorno
     and new.retorno_indefinido is not distinct from old.retorno_indefinido
     and new.folga_antecipacao_justificativa
         is not distinct from old.folga_antecipacao_justificativa then
    new.folga_data_prevista_ciclo:=old.folga_data_prevista_ciclo;
    new.folga_ciclo_anterior_id:=old.folga_ciclo_anterior_id;
    new.folga_antecipada:=old.folga_antecipada;
    if new.status='recusada' and old.status is distinct from 'recusada'
       and old.folga_antecipada then
      new.folga_antecipacao_status:='recusada';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    v_aprovada := old.folga_antecipacao_status = 'aprovada';
  end if;
  if new.motivo is distinct from 'folga_campo' then
    new.folga_data_prevista_ciclo:=null;
    new.folga_ciclo_anterior_id:=null;
    new.folga_antecipada:=false;
    new.folga_antecipacao_justificativa:=null;
    new.folga_antecipacao_status:=null;
    new.folga_antecipacao_analisada_por:=null;
    new.folga_antecipacao_analisada_em:=null;
    return new;
  end if;
  -- Identidade canonica: um cadastro privado pode apontar para funcionario tradicional.
  -- O mesmo valor e usado no advisory lock e na busca de conflitos.
  select p.funcionario_id into v_identidade_funcionario
  from public.ro_funcionarios_enderecos_privados p
  where p.id = new.colaborador_id;
  v_identidade_funcionario := coalesce(new.funcionario_id,v_identidade_funcionario);
  v_identidade_chave := case when v_identidade_funcionario is not null
    then 'funcionario:'||v_identidade_funcionario::text
    else 'privado:'||new.colaborador_id::text end;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_identidade_chave,904)
  );

  if tg_op='INSERT' then
    select * into v_contexto
    from ro_private.folga_criacao_contexto
    where solicitacao_id=new.id
      and ((funcionario_id is not null and funcionario_id=new.funcionario_id)
        or (colaborador_id is not null and colaborador_id=new.colaborador_id))
      and obra_id=new.obra_id
      and criado_por=auth.uid();

    if found then
      -- Contexto e gravado somente pela RPC privilegiada, nunca por GUC.
      new.folga_alocacao_id := v_contexto.alocacao_id;
      new.folga_distancia_km := v_contexto.distancia_km;
      new.folga_regime_faixa := v_contexto.regime_faixa;
      new.folga_intervalo_dias := v_contexto.intervalo_dias;
    else
      -- Antes da ativacao, preserva a funcao antiga para todas as Folgas.
      -- Apos a ativacao, BLOQUEIA qualquer Folga nova sem contexto de km,
      -- inclusive por chamada direta a RPC legada, sem afetar outros motivos.
      if exists(
        select 1 from ro_private.folga_configuracao cfg
        where cfg.chave='novo_fluxo_distancia' and cfg.ativo
      ) then
        raise exception 'FOLGA_CAMPO_DISTANCIA_OBRIGATORIA_NOVO_FLUXO';
      end if;
      -- Caminho legado nao pode falsificar snapshots.
      new.folga_alocacao_id := null;
      new.folga_distancia_km := null;
      new.folga_regime_faixa := null;
      new.folga_intervalo_dias := null;
    end if;
  elsif old.folga_alocacao_id is not null then
    -- Snapshot do pedido ja criado e imutavel.
    new.folga_alocacao_id := old.folga_alocacao_id;
    new.folga_distancia_km := old.folga_distancia_km;
    new.folga_regime_faixa := old.folga_regime_faixa;
    new.folga_intervalo_dias := old.folga_intervalo_dias;
    if new.funcionario_id is distinct from old.funcionario_id
       or new.colaborador_id is distinct from old.colaborador_id
       or new.obra_id is distinct from old.obra_id then
      raise exception 'ALTERACAO_CC_FUNCIONARIO_REQUER_NOVA_SOLICITACAO';
    end if;
  end if;

  -- A verificacao acontece apos obter o snapshot validado da RPC.
  if new.folga_intervalo_dias = 7 then
    select s.id into v_duplicada
    from public.ro_passagem_solicitacoes s
    left join public.ro_funcionarios_enderecos_privados sp on sp.id=s.colaborador_id
    where s.id is distinct from new.id and s.motivo='folga_campo'
      and s.excluida_em is null
      and s.status in ('solicitada','em_andamento','passagem_comprada')
      and s.aprovacao_status is distinct from 'reprovada'
      and (case when v_identidade_funcionario is not null then
        coalesce(s.funcionario_id,sp.funcionario_id)=v_identidade_funcionario
        else s.colaborador_id=new.colaborador_id end)
      and new.data_ida <= case when s.retorno_indefinido or s.data_retorno is null then s.data_ida else greatest(s.data_ida,s.data_retorno) end
      and s.data_ida <= case when new.retorno_indefinido or new.data_retorno is null then new.data_ida else greatest(new.data_ida,new.data_retorno) end
    order by s.data_ida,s.created_at limit 1;
  else
    if new.funcionario_id is not null then
      v_duplicada := public.ro_funcionario_possui_folga_futura_ativa(
        new.funcionario_id,new.id
      );
    elsif new.colaborador_id is not null then
      select s.id into v_duplicada
      from public.ro_passagem_solicitacoes s
      where s.colaborador_id=new.colaborador_id
        and s.id is distinct from new.id
        and s.motivo='folga_campo'
        and s.excluida_em is null
        and s.data_ida >= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
        and s.status in ('solicitada','em_andamento','passagem_comprada')
        and s.aprovacao_status is distinct from 'reprovada'
      order by s.data_ida,s.created_at limit 1;
    end if;
  
  end if;
  if v_duplicada is not null and
     (tg_op='INSERT' or new.funcionario_id is distinct from old.funcionario_id
      or new.colaborador_id is distinct from old.colaborador_id
      or new.data_ida is distinct from old.data_ida
      or new.data_retorno is distinct from old.data_retorno
      or new.retorno_indefinido is distinct from old.retorno_indefinido) then
    raise exception 'FOLGA_FUTURA_DUPLICADA:%',v_duplicada;
  end if;

  if new.folga_alocacao_id is not null then
    -- Ancora: ultima folga aprovada/dispensada E finalizada.
    select s.id,s.data_ida into v_anterior,v_ultima_data
    from public.ro_passagem_solicitacoes s
    where ((new.funcionario_id is not null and s.funcionario_id=new.funcionario_id)
      or (new.funcionario_id is null and s.colaborador_id=new.colaborador_id))
      and s.id is distinct from new.id
      and s.motivo='folga_campo'
      and s.status='finalizada'
      and s.aprovacao_status in ('aprovada','dispensada')
      and s.data_ida <= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
    order by s.data_ida desc,s.id desc
    limit 1;
    v_proxima := case when v_ultima_data is not null
      then v_ultima_data + new.folga_intervalo_dias else null end;
  else
    -- Compatibilidade exata do calculo legado enquanto desativado.
    v_ciclo:=public.ro_obter_ciclo_folga_funcionario(new.funcionario_id);
    v_proxima:=nullif(v_ciclo->>'proxima_folga_prevista','')::date;
    v_anterior:=nullif(v_ciclo->>'ultima_solicitacao_id','')::uuid;
  end if;

  new.folga_data_prevista_ciclo:=coalesce(v_proxima,new.data_ida);
  new.folga_ciclo_anterior_id:=v_anterior;
  if v_proxima is not null and new.data_ida<v_proxima then
    new.folga_antecipada:=true;
    if length(trim(coalesce(new.folga_antecipacao_justificativa,'')))<10 then
      raise exception 'JUSTIFICATIVA_ANTECIPACAO_OBRIGATORIA';
    end if;
    if tg_op='INSERT' or new.funcionario_id is distinct from old.funcionario_id
       or new.colaborador_id is distinct from old.colaborador_id
       or new.data_ida is distinct from old.data_ida
       or new.folga_antecipacao_justificativa is distinct from old.folga_antecipacao_justificativa then
      new.folga_antecipacao_status:='pendente';
      new.folga_antecipacao_analisada_por:=null;
      new.folga_antecipacao_analisada_em:=null;
      if tg_op='UPDATE' and v_aprovada then
        insert into public.ro_auditoria_interna(
          evento,solicitacao_id,detalhes,criado_por
        ) values (
          'aprovacao_antecipacao_invalidada',new.id,
          pg_catalog.jsonb_build_object('data_ida',new.data_ida),auth.uid()
        );
      end if;
    end if;
  else
    new.folga_antecipada:=false;
    new.folga_antecipacao_justificativa:=null;
    new.folga_antecipacao_status:='nao_aplicavel';
    new.folga_antecipacao_analisada_por:=null;
    new.folga_antecipacao_analisada_em:=null;
  end if;
  if new.status='recusada' and new.folga_antecipada then
    new.folga_antecipacao_status:='recusada';
  end if;
  return new;
end;
$function$
;
