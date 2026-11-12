-- RASCUNHO - ETAPA B / FUNCOES COORDENADAS, NAO EXECUTAR NA PRODUCAO.
-- Requer etapa A aplicada, backup verificavel e autorizacao explicita.
-- Recria as funcoes ligadas aos triggers existentes, sem renomear triggers.
-- SEM GRANT EXECUTE: nao habilita a funcionalidade para authenticated.
begin;
do $guard$
begin
  if to_regclass('public.ro_folga_alocacoes') is null
    or to_regclass('ro_private.folga_criacao_contexto') is null
  then raise exception 'ETAPA_A_NAO_APLICADA'; end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.ro_passagem_solicitacoes'::regclass
      and tgname='ro_validar_ciclo_folga_campo' and not tgisinternal
  ) or not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.ro_passagem_solicitacoes'::regclass
      and tgname='ro_auditar_ciclo_folga_campo' and not tgisinternal
  ) then raise exception 'TRIGGERS_LEGADOS_NAO_ENCONTRADOS'; end if;
end
$guard$;

-- ===== ORIGEM: docs/sql/folga-campo-10-trigger-ciclo-coordenado-RASCUNHO.sql =====
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
  -- Atualizacoes de status sem mudanca dos parametros do ciclo preservam
  -- os valores ja registrados, inclusive a aprovacao de antecipacao.
  if tg_op='UPDATE'
     and old.motivo='folga_campo' and new.motivo='folga_campo'
     and new.funcionario_id is not distinct from old.funcionario_id
     and new.obra_id is not distinct from old.obra_id
     and new.data_ida is not distinct from old.data_ida
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



-- ===== ORIGEM: docs/sql/folga-campo-11-auditoria-guard-status-RASCUNHO.sql =====
-- RASCUNHO 11 - CORRECOES DE AUDITORIA, SNAPSHOT E STATUS
-- NAO EXECUTAR EM PRODUCAO. Depende de 01, 04, 08, 09 e 10.
-- As tres funcoes abaixo devem ser ativadas junto com o trigger coordenado.
-- Nao altera o sistema oficial de alocacao.

-- (1) AUDITORIA: separar INSERT e UPDATE para nunca acessar OLD em INSERT.
-- Para o novo fluxo, a proxima previsao deriva da data_ida
-- efetiva e do intervalo congelado; para legado, mantem comportamento atual.
create or replace function public.ro_auditar_ciclo_folga_campo()
returns trigger language plpgsql security definer
set search_path = 'public','pg_temp'
as $$
begin
  -- INSERT nao pode acessar OLD: registro nao atribuido nesta operacao.
  if tg_op='INSERT' then
    if new.motivo='folga_campo' then
      insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por)
      values('ciclo_folga_calculado',new.id,
        pg_catalog.jsonb_build_object(
          'sem_historico',new.folga_ciclo_anterior_id is null,
          'ciclo_anterior_id',new.folga_ciclo_anterior_id,
          'data_prevista',new.folga_data_prevista_ciclo,
          'data_ida',new.data_ida,'antecipada',new.folga_antecipada,
          'justificativa',new.folga_antecipacao_justificativa,
          'distancia_km',new.folga_distancia_km,
          'intervalo_dias',new.folga_intervalo_dias),auth.uid());
    end if;
  elsif tg_op='UPDATE' then
    if new.motivo='folga_campo'
       and old.status is distinct from 'finalizada'
       and new.status='finalizada' then
      insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por)
      values('ciclo_folga_avancado',new.id,
        pg_catalog.jsonb_build_object(
          'ancora',case when new.folga_alocacao_id is null
                        then new.folga_data_prevista_ciclo else new.data_ida end,
          'proxima_prevista',case when new.folga_alocacao_id is null
                            then new.folga_data_prevista_ciclo + 90
                            else new.data_ida + new.folga_intervalo_dias end,
          'intervalo_dias',new.folga_intervalo_dias,
          'aprovacao_status',new.aprovacao_status),auth.uid());
    end if;
  end if;
  return new;
end;
$$;

-- (2) GUARDA INDEPENDENTE: executa em qualquer UPDATE, mesmo quando a
-- coluna alterada nao consta do UPDATE OF do trigger de ciclo.
create or replace function public.ro_guardar_snapshot_folga()
returns trigger language plpgsql security definer
set search_path = 'public','pg_temp'
as $$
begin
  if old.motivo='folga_campo' and old.folga_alocacao_id is not null then
    if new.folga_alocacao_id is distinct from old.folga_alocacao_id
       or new.folga_distancia_km is distinct from old.folga_distancia_km
       or new.folga_regime_faixa is distinct from old.folga_regime_faixa
       or new.folga_intervalo_dias is distinct from old.folga_intervalo_dias
       or new.funcionario_id is distinct from old.funcionario_id
       or new.obra_id is distinct from old.obra_id
       or new.motivo is distinct from old.motivo then
      raise exception 'SNAPSHOT_FOLGA_IMUTAVEL';
    end if;
  end if;
  -- Nao permitir adicionar snapshots manualmente a pedidos legados.
  if old.folga_alocacao_id is null and (
       new.folga_alocacao_id is not null
       or new.folga_distancia_km is not null
       or new.folga_regime_faixa is not null
       or new.folga_intervalo_dias is not null
     ) then
    raise exception 'SNAPSHOT_FOLGA_SOMENTE_NA_CRIACAO';
  end if;
  return new;
end;
$$;
drop trigger if exists ro_guardar_snapshot_folga on public.ro_passagem_solicitacoes;
create trigger ro_guardar_snapshot_folga
before update on public.ro_passagem_solicitacoes
for each row execute function public.ro_guardar_snapshot_folga();

-- (3) STATUS: a funcao de ciclo deve encerrar antecipadamente para UPDATE
-- que altera SOMENTE status, sem mudar as entradas de calculo.
-- IMPORTANTE: inserir este bloco NO INICIO da funcao do rascunho 10,
-- antes de recalcular o ciclo, mas depois de verificar TG_OP='UPDATE'.
--
-- if tg_op='UPDATE'
--    and old.motivo='folga_campo' and new.motivo='folga_campo'
--    and new.funcionario_id is not distinct from old.funcionario_id
--    and new.obra_id is not distinct from old.obra_id
--    and new.data_ida is not distinct from old.data_ida
--    and new.folga_antecipacao_justificativa
--        is not distinct from old.folga_antecipacao_justificativa then
--   -- A guarda independente protege snapshots em qualquer UPDATE.
--   -- Preserva ciclo, justificativa, status de antecipacao e auditoria.
--   -- Excecao: a regra existente para recusa deve continuar.
--   if new.status='recusada' and old.status is distinct from 'recusada'
--      and old.folga_antecipada then
--     new.folga_antecipacao_status:='recusada';
--   end if;
--   return new;
-- end if;
--
-- OBS: este rascunho 11 ainda nao e migracao executavel completa:
-- o bloco (3) precisa ser integrado na funcao do arquivo 10.
-- A ordem dos BEFORE triggers e a cadeia de aprovacoes devem ser
-- revisadas antes de ativar. Nenhuma alteracao no banco foi realizada.



-- ===== ORIGEM: docs/sql/folga-campo-09-rpc-criacao-coordenada-RASCUNHO.sql =====
-- RASCUNHO 09: RPC de criacao coordenada (NAO EXECUTAR ISOLADAMENTE).
-- Depende das estruturas 01, episodio 04, contexto 08 e trigger coordenado
-- que consome ro_private.folga_criacao_contexto ANTES DO INSERT.
-- O trigger coordenado AINDA NAO FOI IMPLEMENTADO.
-- Nao conceder EXECUTE enquanto nao houver trigger e testes de seguranca.
--
-- O PostgreSQL executa toda a chamada de funcao numa unica transacao.
-- Qualquer RAISE EXCEPTION desfaz episodio, auditoria e solicitacao.
create or replace function public.ro_criar_folga_campo_com_distancia(
  p_solicitacao jsonb,
  p_documentos jsonb default '[]'::jsonb,
  p_distancia_declarada_km integer default null,
  p_confirma_retorno boolean default false
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_criado uuid;
  v_funcionario uuid;
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
  if p_solicitacao->>'colaborador_id' is not null
     or p_solicitacao->>'viajante_nome_informado' is not null then
    raise exception 'VIAJANTE_NAO_SUPORTADO_NESTA_ETAPA';
  end if;
  begin
    v_id := (p_solicitacao->>'id')::uuid;
    v_funcionario := (p_solicitacao->>'funcionario_id')::uuid;
    v_obra := (p_solicitacao->>'obra_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'IDENTIFICADOR_INVALIDO';
  end;
  if v_id is null or v_funcionario is null or v_obra is null then
    raise exception 'IDENTIFICADORES_OBRIGATORIOS';
  end if;
  -- Validacao previa equivalente aos filtros canonicos do trigger
  -- ro_validar_solicitacao_visibilidade. A cadeia legada continua sendo
  -- executada e permanece autoridade final sobre todas as demais regras.
  if public.ro_funcionario_disponivel_para_usuario(auth.uid(),v_funcionario) is distinct from true then
    raise exception 'FUNCIONARIO_INDISPONIVEL';
  end if;
  if not exists (
    select 1 from public.ro_catalogo_centros_custo() c
    where c.id=v_obra
  ) then
    raise exception 'CENTRO_CUSTO_INDISPONIVEL';
  end if;
  v_episodio := ro_private.preparar_episodio_folga(
    v_funcionario,v_obra,p_distancia_declarada_km,p_confirma_retorno
  );
  insert into ro_private.folga_criacao_contexto(
    solicitacao_id,funcionario_id,obra_id,alocacao_id,
    distancia_km,regime_faixa,intervalo_dias,criado_por
  ) values (
    v_id,v_funcionario,v_obra,
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
      and s.funcionario_id=v_funcionario and s.obra_id=v_obra
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
$$;
revoke all on function public.ro_criar_folga_campo_com_distancia(
  jsonb,jsonb,integer,boolean
) from public,anon,authenticated;

-- ATENCAO: a RPC acima NAO esta pronta para publicacao.
-- O trigger deve validar contexto privado e proteger contra escrita direta
-- de snapshots por chamadas legadas. Os grants devem ser concedidos somente
-- apos testes transacionais, aprovacao e backup.
-- Verificar que o caminho legado conserva criacao sem distancia.


commit;
