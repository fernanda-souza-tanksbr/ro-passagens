-- RASCUNHO: REVERSAO PONTUAL APENAS DA ETAPA A, ANTES DE B/C1/C2.
-- NAO EXECUTAR SEM AUTORIZACAO E PREFLIGHT DE PRODUCAO.
-- Nao restaura backup integral; remove somente objetos vazios criados por A.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
do $guard$
begin
 if to_regnamespace('ro_private') is null
    or to_regclass('public.ro_folga_alocacoes') is null
    or to_regclass('public.ro_folga_distancia_auditoria') is null
    or to_regclass('ro_private.folga_configuracao') is null
    or to_regclass('ro_private.folga_criacao_contexto') is null
 then raise exception 'REVERSAO_A_ESTRUTURA_INCOMPLETA'; end if;

 if to_regprocedure('public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)') is not null
    or to_regprocedure('public.ro_guardar_snapshot_folga()') is not null
    or exists (
      select 1 from pg_catalog.pg_trigger
      where tgrelid='public.ro_passagem_solicitacoes'::regclass
        and tgname='ro_guardar_snapshot_folga' and not tgisinternal
    )
 then raise exception 'REVERSAO_A_PROIBIDA_APOS_ETAPA_B'; end if;

 if exists(select 1 from public.ro_folga_alocacoes)
    or exists(select 1 from public.ro_folga_distancia_auditoria)
    or exists(select 1 from ro_private.folga_criacao_contexto)
    or exists (
       select 1 from public.ro_passagem_solicitacoes
       where folga_alocacao_id is not null or folga_distancia_km is not null
          or folga_regime_faixa is not null or folga_intervalo_dias is not null
    )
 then raise exception 'REVERSAO_A_PROIBIDA_COM_DADOS'; end if;

 if not exists (
   select 1 from ro_private.folga_configuracao
   where chave='novo_fluxo_distancia' and ativo=false
 ) or (select count(*) from ro_private.folga_configuracao)<>1
 then raise exception 'REVERSAO_A_GATE_NAO_DESLIGADO'; end if;
end;
$guard$;

-- Remover endpoints primeiro, evitando dependencias com o schema privado.
drop function public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid);
drop function public.ro_corrigir_distancia_folga(uuid,integer,text);

drop function ro_private.corrigir_distancia_folga(uuid,integer,text);
drop function ro_private.pode_corrigir_distancia_folga(uuid);
drop function ro_private.preparar_episodio_folga(uuid,uuid,integer,boolean,uuid);
drop function ro_private.regime_folga_km(integer);

drop table ro_private.folga_criacao_contexto;
drop table ro_private.folga_configuracao;
drop schema ro_private restrict;

-- A FK para ro_folga_alocacoes e removida junto com a coluna.
alter table public.ro_passagem_solicitacoes
  drop column folga_alocacao_id,
  drop column folga_distancia_km,
  drop column folga_regime_faixa,
  drop column folga_intervalo_dias;

drop table public.ro_folga_distancia_auditoria;
drop table public.ro_folga_alocacoes;
commit;
