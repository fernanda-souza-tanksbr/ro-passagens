-- SOMENTE TESTES ANTIGOS: mocks depois de validar guard da etapa B
-- A homologacao alternativa validar-folga-etapa-b-real-pg17.yml mantem as
-- funcoes REAIS em execucao, sem esses mocks.
\set ON_ERROR_STOP on
create or replace function public.ro_funcionario_possui_folga_futura_ativa(
 p_funcionario_id uuid, p_ignorar_solicitacao_id uuid default null
) returns uuid language sql stable as $$
 select null::uuid;
$$;
create or replace function public.ro_obter_ciclo_folga_funcionario(
 p_funcionario_id uuid
) returns jsonb language sql stable as $$
 select pg_catalog.jsonb_build_object('proxima_folga_prevista',null,'ultima_solicitacao_id',null);
$$;
select 'FOLGA_MOCKS_SOMENTE_REGRESSAO_EXISTENTE' as resultado;
