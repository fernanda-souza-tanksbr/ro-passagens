-- Verifica concessao minima de permissoes depois de C1 + C2.
-- Somente banco ficticio temporario.
\set ON_ERROR_STOP on
DO $$
begin
 if not exists(select 1 from ro_private.folga_configuracao
   where chave='novo_fluxo_distancia' and ativo) then
  raise exception 'FLUXO_NAO_ATIVADO_POR_C2';end if;
 if not pg_catalog.has_function_privilege('authenticated',
  'public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated',
  'public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated',
  'public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
 then raise exception 'RPCS_NAO_LIBERADAS_PARA_AUTHENTICATED';end if;
 if pg_catalog.has_table_privilege('authenticated','public.ro_folga_alocacoes','SELECT')
 or pg_catalog.has_table_privilege('authenticated','public.ro_folga_distancia_auditoria','SELECT')
 or pg_catalog.has_table_privilege('authenticated','ro_private.folga_configuracao','SELECT')
 then raise exception 'TABELAS_PRIVADAS_INDEVIDAMENTE_EXPOSTAS';end if;
 if pg_catalog.has_function_privilege('anon',
  'public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
 then raise exception 'RPC_EXPOSTA_A_ANON';end if;
end $$;
select 'FOLGA_GRANTS_ATIVACAO_OK' as resultado;
