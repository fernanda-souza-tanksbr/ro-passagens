-- RASCUNHO TECNICO - NAO EXECUTAR NO SUPABASE DE PRODUCAO
-- Dependencia: docs/sql/folga-campo-01-estruturas-RASCUNHO.sql
-- Somente consulta; sem SECURITY DEFINER e sem liberacao de EXECUTE.
-- A RPC publica autenticada sera criada apenas apos revisar modelo de identidade e autorizacoes.

create or replace function ro_private.contexto_folga_campo(
  p_funcionario_id uuid,
  p_obra_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_ultima public.ro_passagem_solicitacoes%rowtype;
  v_intervalo integer;
  v_transporte text;
  v_faixa text;
begin
  if p_funcionario_id is null or p_obra_id is null then
    raise exception 'FUNCIONARIO_CC_OBRIGATORIOS';
  end if;
  select * into v_atual from public.ro_folga_alocacoes
    where funcionario_id=p_funcionario_id and encerrada_em is null
    order by iniciada_em desc limit 1;
  if v_atual.id is null or v_atual.obra_id is distinct from p_obra_id then
    select * into v_anterior from public.ro_folga_alocacoes
      where funcionario_id=p_funcionario_id and obra_id=p_obra_id
      order by iniciada_em desc limit 1;
  end if;
  select * into v_ultima from public.ro_passagem_solicitacoes s
    where s.funcionario_id=p_funcionario_id
      and s.motivo='folga_campo'
      and s.status='finalizada'
      and s.aprovacao_status in ('aprovada','dispensada')
      and s.data_ida <= (now() at time zone 'America/Sao_Paulo')::date
    order by s.data_ida desc,s.id desc limit 1;
  if v_atual.obra_id=p_obra_id then
    select faixa,intervalo_dias,transporte into v_faixa,v_intervalo,v_transporte
      from ro_private.regime_folga_km(v_atual.distancia_km);
  elsif v_anterior.id is not null then
    select faixa,intervalo_dias,transporte into v_faixa,v_intervalo,v_transporte
      from ro_private.regime_folga_km(v_anterior.distancia_km);
  end if;
  return jsonb_build_object(
    'obra_id',p_obra_id,
    'distancia_km',case when v_atual.obra_id=p_obra_id then v_atual.distancia_km else v_anterior.distancia_km end,
    'estado',case when v_atual.obra_id=p_obra_id then 'reutilizar' when v_anterior.id is not null then 'confirmar' else 'informar' end,
    'regime_faixa',v_faixa,'intervalo_dias',v_intervalo,'transporte',v_transporte,
    'ultima_folga_realizada',v_ultima.data_ida,
    'ultima_solicitacao_id',v_ultima.id,
    'proxima_folga_prevista',case when v_intervalo is not null and v_ultima.id is not null then v_ultima.data_ida+v_intervalo end
  );
end;
$$;
revoke all on function ro_private.contexto_folga_campo(uuid,uuid) from public,anon,authenticated;

-- PENDENCIAS DE SEGURANCA ANTES DE EXPOR RPC:
-- 1. Determinar como funcionario_id se relaciona a auth.uid(), incluindo criacao por RO/RH.
-- 2. Resolver episodio de alocacao sem presumir que nova selecao de CC equivale a transferencia real.
-- 3. Confirmar que correcoes so sao permitidas aos papeis existentes autorizados, por validacao no banco.
-- 4. Corrigir consulta para retornar estado "informar" se nao houver episodio vigente confiavel.
-- 5. Nao executar este arquivo isoladamente: nao substitui triggers ou RPCs de criacao.
