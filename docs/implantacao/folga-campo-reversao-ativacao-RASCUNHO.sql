-- RASCUNHO DE REVERSAO SEM PERDA DE HISTORICO.
-- NAO EXECUTAR NA PRODUCAO SEM AUTORIZACAO.
-- Primeiro retornar interface ao deploy antigo (ou UI desativada).
-- Este roteiro nao restaura os corpos de funcoes antigas: preserva
-- snapshots e episodios, mas libera novamente criacao antiga de Folga.
begin;
update ro_private.folga_configuracao
set ativo=false,atualizado_em=now()
where chave='novo_fluxo_distancia';
revoke execute on function public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)
 from authenticated;
revoke execute on function public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)
 from authenticated;
revoke execute on function public.ro_corrigir_distancia_folga(uuid,integer,text)
 from authenticated;
commit;
-- Nunca apagar tabelas/colunas/auditorias de distancia neste rollback.
