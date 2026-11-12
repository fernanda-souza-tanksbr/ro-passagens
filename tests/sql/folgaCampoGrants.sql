-- Verificacao de grants do pacote de testes de Folga de Campo.
-- PostgreSQL descartavel apenas. Nenhum grant novo e concedido.
\set ON_ERROR_STOP on
DO $$
begin
  if pg_catalog.has_function_privilege('anon','public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
  then raise exception 'CRIACAO_KM_EXPOSTA_ANTES_DA_ATIVACAO'; end if;

  if pg_catalog.has_function_privilege('anon','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
  then raise exception 'CONSULTA_KM_EXPOSTA_ANTES_DA_ATIVACAO'; end if;

  if pg_catalog.has_function_privilege('anon','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
  then raise exception 'CORRECAO_KM_EXPOSTA_ANTES_DA_ATIVACAO'; end if;

  if pg_catalog.has_schema_privilege('anon','ro_private','USAGE')
     or pg_catalog.has_schema_privilege('authenticated','ro_private','USAGE')
  then raise exception 'SCHEMA_PRIVADO_EXPOSTO'; end if;

  if pg_catalog.has_table_privilege('anon','public.ro_folga_alocacoes','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.ro_folga_alocacoes','SELECT')
     or pg_catalog.has_table_privilege('anon','public.ro_folga_distancia_auditoria','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.ro_folga_distancia_auditoria','SELECT')
  then raise exception 'DADOS_KM_EXPOSTOS_DIRETAMENTE'; end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='ro_folga_alocacoes'
      and c.relrowsecurity
  ) then raise exception 'RLS_ALOCACAO_DESLIGADO'; end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='ro_folga_distancia_auditoria'
      and c.relrowsecurity
  ) then raise exception 'RLS_AUDITORIA_DESLIGADO'; end if;
end $$;
select 'FOLGA_PERMISSOES_DB_OK' as resultado;
