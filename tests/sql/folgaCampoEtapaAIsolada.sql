-- Teste exclusivo da Etapa A em banco PostgreSQL 17 descartavel.
-- Nao instala a Etapa B. Exige fixture e migration A previamente aplicadas.
\set ON_ERROR_STOP on
DO $$
declare
  v_flag boolean;
  v_triggers integer;
begin
  if to_regclass('public.ro_folga_alocacoes') is null
    or to_regclass('public.ro_folga_distancia_auditoria') is null
    or to_regclass('ro_private.folga_criacao_contexto') is null
    or to_regclass('ro_private.folga_configuracao') is null
  then raise exception 'A_TABELAS_INCOMPLETAS'; end if;

  select ativo into v_flag
  from ro_private.folga_configuracao
  where chave='novo_fluxo_distancia';
  if v_flag is distinct from false then
    raise exception 'A_GATE_INDEVIDAMENTE_ATIVO';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid='public.ro_folga_alocacoes'::regclass and c.relrowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid='public.ro_folga_distancia_auditoria'::regclass and c.relrowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid='ro_private.folga_configuracao'::regclass and c.relrowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid='ro_private.folga_criacao_contexto'::regclass and c.relrowsecurity
  ) then raise exception 'A_RLS_AUSENTE'; end if;

  if pg_catalog.has_schema_privilege('anon','ro_private','USAGE')
    or pg_catalog.has_schema_privilege('authenticated','ro_private','USAGE')
    or pg_catalog.has_table_privilege('authenticated','public.ro_folga_alocacoes','SELECT')
    or pg_catalog.has_table_privilege('authenticated','public.ro_folga_distancia_auditoria','SELECT')
    or pg_catalog.has_function_privilege('anon','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
    or pg_catalog.has_function_privilege('authenticated','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
    or pg_catalog.has_function_privilege('anon','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
    or pg_catalog.has_function_privilege('authenticated','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
  then raise exception 'A_PERMISSAO_EXPOSTA'; end if;

  if to_regprocedure('public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)') is not null
    or to_regprocedure('public.ro_guardar_snapshot_folga()') is not null
  then raise exception 'A_INSTALOU_COMPONENTE_DA_ETAPA_B'; end if;

  select count(*) into v_triggers from pg_catalog.pg_trigger
  where tgrelid='public.ro_passagem_solicitacoes'::regclass and not tgisinternal;
  if v_triggers<>0 then raise exception 'A_MODIFICOU_TRIGGER_LEGADO'; end if;

  if (select count(*) from public.ro_folga_alocacoes) <> 0
    or (select count(*) from public.ro_folga_distancia_auditoria) <> 0
  then raise exception 'A_PREENCHEU_TABELAS_NOVAS'; end if;

  if (select count(*) from information_schema.columns where table_schema='public'
    and table_name='ro_passagem_solicitacoes'
    and column_name in ('folga_alocacao_id','folga_distancia_km','folga_regime_faixa','folga_intervalo_dias'))<>4
  then raise exception 'A_COLUNAS_INCOMPLETAS'; end if;

  if (select intervalo_dias from ro_private.regime_folga_km(200))<>7
    or (select intervalo_dias from ro_private.regime_folga_km(201))<>14
    or (select intervalo_dias from ro_private.regime_folga_km(601))<>45
    or (select intervalo_dias from ro_private.regime_folga_km(1501))<>90
  then raise exception 'A_FAIXAS_INCORRETAS'; end if;
end $$;
select 'FOLGA_ETAPA_A_ISOLADA_OK' as resultado;
