-- RASCUNHO OPERACIONAL - NAO EXECUTAR SEM AUTORIZACAO EXPLICITA.
-- C2: apos conferir UI publicada com novo fluxo, torna KM obrigatorio
-- inclusive para solicitacoes diretas via RPC legada. Outros motivos
-- permanecem no fluxo anterior.
begin;
do $guard$
begin
 if to_regclass('ro_private.folga_configuracao') is null then
  raise exception 'ETAPA_A_NAO_APLICADA';end if;
 if not pg_catalog.has_function_privilege('authenticated',
   'public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated',
   'public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
 then raise exception 'PERMISSOES_C1_PENDENTES';end if;
 if not exists(select 1 from ro_private.folga_configuracao
   where chave='novo_fluxo_distancia' and not ativo)
 then raise exception 'CONFIGURACAO_INESPERADA';end if;
end
$guard$;
update ro_private.folga_configuracao
set ativo=true,atualizado_em=now()
where chave='novo_fluxo_distancia' and not ativo;
commit;
-- Revalidar imediatamente criacao de Folga, aprovacoes e outros motivos.
