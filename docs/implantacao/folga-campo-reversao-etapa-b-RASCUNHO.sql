-- REVERSAO DA ETAPA B, APENAS ANTES DE C1/C2/ATIVACAO E SEM SNAPSHOTS.
-- Definicoes legadas recuperadas por SELECT diretamente do Supabase em 12/11/2026.
-- Sem exclusao de solicitações, tabelas, registros ou estruturas da Etapa A.
-- NAO EXECUTAR EM PRODUCAO SEM AUTORIZACAO EXPRESSA.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

do $guard$
begin
  if to_regnamespace('ro_private') is null
    or to_regclass('ro_private.folga_configuracao') is null
    or to_regprocedure('public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)') is null
    or to_regprocedure('public.ro_guardar_snapshot_folga()') is null
  then raise exception 'REVERSAO_B_CONTEXTO_INCOMPATIVEL'; end if;

  if (select ativo from ro_private.folga_configuracao
      where chave='novo_fluxo_distancia') is distinct from false
  then raise exception 'REVERSAO_B_REGRA_ATIVA';end if;

  if exists (
    select 1 from public.ro_passagem_solicitacoes
    where folga_alocacao_id is not null
      or folga_distancia_km is not null
      or folga_regime_faixa is not null
      or folga_intervalo_dias is not null
  ) or exists (select 1 from public.ro_folga_alocacoes)
  then raise exception 'REVERSAO_B_POSSUI_DADOS_NOVO_FLUXO';end if;
end
$guard$;

drop trigger ro_guardar_snapshot_folga on public.ro_passagem_solicitacoes;
drop function public.ro_guardar_snapshot_folga();
drop function public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean);

-- Restauro transacional das duas definicoes anteriores à Etapa B.
CREATE OR REPLACE FUNCTION public.ro_validar_ciclo_folga_campo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ciclo jsonb; v_proxima date; v_anterior uuid; v_duplicada uuid; v_aprovada boolean:=false;
begin
  if tg_op = 'UPDATE' then v_aprovada := old.folga_antecipacao_status = 'aprovada'; end if;
  if new.motivo is distinct from 'folga_campo' then new.folga_data_prevista_ciclo:=null;new.folga_ciclo_anterior_id:=null;new.folga_antecipada:=false;new.folga_antecipacao_justificativa:=null;new.folga_antecipacao_status:=null;new.folga_antecipacao_analisada_por:=null;new.folga_antecipacao_analisada_em:=null;return new;end if;
  perform pg_advisory_xact_lock(hashtextextended(new.funcionario_id::text,904));
  v_duplicada:=public.ro_funcionario_possui_folga_futura_ativa(new.funcionario_id,new.id);
  if v_duplicada is not null and (tg_op='INSERT' or new.funcionario_id is distinct from old.funcionario_id or new.data_ida is distinct from old.data_ida) then raise exception 'FOLGA_FUTURA_DUPLICADA:%',v_duplicada;end if;
  v_ciclo:=public.ro_obter_ciclo_folga_funcionario(new.funcionario_id);v_proxima:=nullif(v_ciclo->>'proxima_folga_prevista','')::date;v_anterior:=nullif(v_ciclo->>'ultima_solicitacao_id','')::uuid;
  new.folga_data_prevista_ciclo:=coalesce(v_proxima,new.data_ida);new.folga_ciclo_anterior_id:=v_anterior;
  if v_proxima is not null and new.data_ida<v_proxima then
    new.folga_antecipada:=true;
    if length(trim(coalesce(new.folga_antecipacao_justificativa,'')))<10 then raise exception 'JUSTIFICATIVA_ANTECIPACAO_OBRIGATORIA';end if;
    if tg_op='INSERT' or new.funcionario_id is distinct from old.funcionario_id or new.data_ida is distinct from old.data_ida or new.folga_antecipacao_justificativa is distinct from old.folga_antecipacao_justificativa then new.folga_antecipacao_status:='pendente';new.folga_antecipacao_analisada_por:=null;new.folga_antecipacao_analisada_em:=null;if tg_op='UPDATE' and v_aprovada then insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por) values('aprovacao_antecipacao_invalidada',new.id,jsonb_build_object('data_ida',new.data_ida),auth.uid());end if;end if;
  else new.folga_antecipada:=false;new.folga_antecipacao_justificativa:=null;new.folga_antecipacao_status:='nao_aplicavel';new.folga_antecipacao_analisada_por:=null;new.folga_antecipacao_analisada_em:=null;end if;
  if new.status='recusada' and new.folga_antecipada then new.folga_antecipacao_status:='recusada';end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.ro_auditar_ciclo_folga_campo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin if new.motivo='folga_campo' and tg_op='INSERT' then insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por) values('ciclo_folga_calculado',new.id,jsonb_build_object('sem_historico',new.folga_ciclo_anterior_id is null,'ciclo_anterior_id',new.folga_ciclo_anterior_id,'data_prevista',new.folga_data_prevista_ciclo,'data_ida',new.data_ida,'antecipada',new.folga_antecipada,'justificativa',new.folga_antecipacao_justificativa),auth.uid());elsif new.motivo='folga_campo' and old.status is distinct from 'finalizada' and new.status='finalizada' then insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por) values('ciclo_folga_avancado',new.id,jsonb_build_object('ancora',new.folga_data_prevista_ciclo,'proxima_prevista',new.folga_data_prevista_ciclo+90),auth.uid());end if;return new;end $function$;

commit;
