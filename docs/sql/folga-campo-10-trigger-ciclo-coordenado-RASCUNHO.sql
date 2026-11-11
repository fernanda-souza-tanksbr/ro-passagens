-- RASCUNHO 10 - NAO EXECUTAR ISOLADAMENTE OU EM PRODUCAO
-- Substitui a definicao do trigger atual apenas na ativacao coordenada.
-- Requer 01, 04, 08, 09 e revisao de grants e de toda a cadeia legada.
-- O trigger existente ja aponta para public.ro_validar_ciclo_folga_campo().
create or replace function public.ro_validar_ciclo_folga_campo()
returns trigger language plpgsql security definer
set search_path = 'public','pg_temp'
as $$
declare
  v_ciclo jsonb;
  v_proxima date;
  v_anterior uuid;
  v_duplicada uuid;
  v_aprovada boolean := false;
  v_contexto ro_private.folga_criacao_contexto%rowtype;
  v_ultima_data date;
begin
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
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.funcionario_id::text,904)
  );
  v_duplicada := public.ro_funcionario_possui_folga_futura_ativa(
    new.funcionario_id,new.id
  );
  if v_duplicada is not null and
     (tg_op='INSERT' or new.funcionario_id is distinct from old.funcionario_id
      or new.data_ida is distinct from old.data_ida) then
    raise exception 'FOLGA_FUTURA_DUPLICADA:%',v_duplicada;
  end if;

  if tg_op='INSERT' then
    select * into v_contexto
    from ro_private.folga_criacao_contexto
    where solicitacao_id=new.id
      and funcionario_id=new.funcionario_id
      and obra_id=new.obra_id
      and criado_por=auth.uid();

    if found then
      -- Contexto e gravado somente pela RPC privilegiada, nunca por GUC.
      new.folga_alocacao_id := v_contexto.alocacao_id;
      new.folga_distancia_km := v_contexto.distancia_km;
      new.folga_regime_faixa := v_contexto.regime_faixa;
      new.folga_intervalo_dias := v_contexto.intervalo_dias;
    else
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
       or new.obra_id is distinct from old.obra_id then
      raise exception 'ALTERACAO_CC_FUNCIONARIO_REQUER_NOVA_SOLICITACAO';
    end if;
  end if;

  if new.folga_alocacao_id is not null then
    -- Ancora: ultima folga aprovada/dispensada E finalizada.
    select s.id,s.data_ida into v_anterior,v_ultima_data
    from public.ro_passagem_solicitacoes s
    where s.funcionario_id=new.funcionario_id
      and s.id is distinct from new.id
      and s.motivo='folga_campo'
      and s.status='finalizada'
      and s.aprovacao_status in ('aprovada','dispensada')
      and s.data_ida<=pg_catalog.current_date
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
$$;

-- BLOQUEADORES ANTES DA ATIVACAO:
-- 1. O trigger AFTER ro_auditar_ciclo_folga_campo ainda usa +90 fixo.
-- 2. A trigger atual NAO dispara em UPDATE OF obra_id, folga_distancia_km,
--    folga_alocacao_id, folga_regime_faixa ou folga_intervalo_dias.
--    Necessario guard separado de imutabilidade (BEFORE UPDATE) e verificar
--    impacto sobre atualizacoes legitimas.
-- 3. Nao recalcular snapshot nem previsao de pedido historico em UPDATE status.
-- 4. Revisar integridade do contexto (CC, alocacao, regime) e grants.
-- 5. Testar em ambiente isolado e nao ativar ate concluir.
