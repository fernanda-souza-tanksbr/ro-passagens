-- RASCUNHO: NAO EXECUTAR EM PRODUCAO.
-- Atualizacao coordenada dos triggers de Folga de Campo.
-- Requer etapa 01 e revisao da etapa 05: snapshot DEVE existir antes do BEFORE INSERT.
-- Nao aplicar isoladamente.

-- A funcao abaixo e uma especificacao executavel de calculo PURO, sem efeitos
-- colaterais. O trigger legado permanece intacto ate a migracao completa.
create or replace function ro_private.calcular_ciclo_folga(
  p_funcionario_id uuid,
  p_data_ida date,
  p_distancia_km integer
) returns jsonb
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  v_ultima_id uuid;
  v_ultima_data date;
  v_intervalo integer;
  v_faixa text;
  v_transporte text;
  v_proxima date;
begin
  if p_funcionario_id is null or p_data_ida is null then
    raise exception 'FUNCIONARIO_DATA_OBRIGATORIOS';
  end if;
  select faixa,intervalo_dias,transporte
    into v_faixa,v_intervalo,v_transporte
  from ro_private.regime_folga_km(p_distancia_km);
  if v_intervalo is null then raise exception 'DISTANCIA_INVALIDA'; end if;

  select s.id,s.data_ida into v_ultima_id,v_ultima_data
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id
    and s.motivo='folga_campo'
    and s.status='finalizada'
    and s.aprovacao_status in ('aprovada','dispensada')
    and s.data_ida <= (now() at time zone 'America/Sao_Paulo')::date
  order by s.data_ida desc,s.id desc limit 1;

  if v_ultima_data is not null then v_proxima:=v_ultima_data+v_intervalo; end if;
  return pg_catalog.jsonb_build_object(
    'ultima_solicitacao_id',v_ultima_id,
    'ultima_folga_realizada',v_ultima_data,
    'proxima_folga_prevista',v_proxima,
    'intervalo_dias',v_intervalo,
    'regime_faixa',v_faixa,
    'transporte',v_transporte,
    'antecipada',v_proxima is not null and p_data_ida<v_proxima
  );
end;
$$;
revoke all on function ro_private.calcular_ciclo_folga(uuid,date,integer)
from public,anon,authenticated;

-- CONTRATO PARA SUBSTITUIR ro_validar_ciclo_folga_campo:
-- A) Em INSERT de folga, obter km do episodio validado e bloqueado na
--    transacao de criacao; NAO usar km arbitrario enviado pelo cliente.
-- B) Calcular ciclo usando data_ida real da ultima finalizada e aprovada
--    (ou dispensada), sem coalesce(folga_data_prevista_ciclo,data_ida).
-- C) Preencher folga_data_prevista_ciclo e folga_ciclo_anterior_id,
--    exigir justificativa >=10 para antecipacao e preservar bloqueio de compra.
-- D) Em UPDATE de status/aprovacao, preservar snapshot e decisao original;
--    nao recalcular antecipacao a partir do CC vigente atual.
-- E) Se data_ida ou CC da propria solicitacao mudar, definir regra de
--    revalidacao com snapshot da propria solicitacao, sem afetar terceiros.
-- F) Evitar usar OLD em INSERT: trigger atual declara v_aprovada usando OLD;
--    revisar compatibilidade antes de substituir.
--
-- CONTRATO PARA SUBSTITUIR ro_auditar_ciclo_folga_campo:
-- Em INSERT registrar km, faixa, intervalo, ancora real e proxima prevista
-- a partir do snapshot da solicitacao; na finalizacao registrar
-- data_ida real + intervalo snapshot, sem +90 fixo.
--
-- PENDENCIA CRITICA:
-- A RPC 05 grava snapshot DEPOIS da chamada de criacao. Isso nao atende
-- ao trigger BEFORE INSERT. Corrigir a RPC/trigger em conjunto antes de
-- executar qualquer DDL. Nao conceder EXECUTE desta funcao a usuarios.
