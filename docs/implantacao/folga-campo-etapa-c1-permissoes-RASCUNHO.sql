-- RASCUNHO OPERACIONAL - NAO EXECUTAR NO SUPABASE SEM AUTORIZACAO.
-- C1: habilita acesso apenas as RPCs publicas, sem ativar obrigatoriedade.
-- Fazer apenas apos backup, testes de compatibilidade e etapas A+B conferidas.
begin;
do $guard$
begin
 if to_regprocedure('public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)') is null
 or to_regprocedure('public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)') is null
 or to_regprocedure('public.ro_corrigir_distancia_folga(uuid,integer,text)') is null
 or to_regclass('ro_private.folga_configuracao') is null
 then raise exception 'PREFLIGHT_FOLGA_C1_NAO_ATENDIDO';end if;
 if exists(select 1 from ro_private.folga_configuracao
   where chave='novo_fluxo_distancia' and ativo)
 then raise exception 'FLUXO_JA_ATIVO';end if;
end
$guard$;
grant execute on function public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean) to authenticated;
grant execute on function public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid) to authenticated;
grant execute on function public.ro_corrigir_distancia_folga(uuid,integer,text) to authenticated;
commit;
-- Nao mudar a flag neste passo. Somente depois de validar UI publicada.
