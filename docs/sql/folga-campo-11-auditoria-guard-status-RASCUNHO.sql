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
