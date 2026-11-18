-- Exact function definitions retrieved read-only from Portal TanksBR Supabase; fixture only.
CREATE OR REPLACE FUNCTION public.ro_proteger_recusa_terminal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_origem public.ro_passagem_solicitacoes%rowtype;
  v_rpc boolean :=
    coalesce(current_setting('ro.recusa_rpc', true), '') = '1'
    or coalesce(current_setting('ro.aprovacao_rpc', true), '') = '1';
begin
  if tg_op = 'INSERT' then
    if new.status = 'recusada'
       or new.recusada_em is not null
       or new.recusada_por is not null
       or new.motivo_recusa is not null
    then
      raise exception 'RECUSA_SOMENTE_PELA_RPC';
    end if;
  else
    if old.status = 'recusada' and not (coalesce(current_setting('ro.exclusao_rpc',true),'')='1' and old.excluida_em is null and new.excluida_em is not null and new.excluida_por=auth.uid() and nullif(btrim(new.motivo_exclusao),'') is not null and (to_jsonb(new)-array['excluida_em','excluida_por','motivo_exclusao','updated_at']::text[])=(to_jsonb(old)-array['excluida_em','excluida_por','motivo_exclusao','updated_at']::text[])) then
      raise exception 'SOLICITACAO_RECUSADA_IMUTAVEL';
    end if;

    if (
      new.status = 'recusada'
      or new.recusada_em is distinct from old.recusada_em
      or new.recusada_por is distinct from old.recusada_por
      or new.motivo_recusa is distinct from old.motivo_recusa
    ) and not v_rpc and not (coalesce(current_setting('ro.exclusao_rpc',true),'')='1' and old.status='recusada' and new.status=old.status and old.excluida_em is null and new.excluida_em is not null and new.excluida_por=auth.uid() and nullif(btrim(new.motivo_exclusao),'') is not null and (to_jsonb(new)-array['excluida_em','excluida_por','motivo_exclusao','updated_at']::text[])=(to_jsonb(old)-array['excluida_em','excluida_por','motivo_exclusao','updated_at']::text[])) then
      raise exception 'RECUSA_SOMENTE_PELA_RPC';
    end if;
  end if;

  if new.solicitacao_origem_id is not null
     and (
       tg_op = 'INSERT'
       or new.solicitacao_origem_id is distinct from old.solicitacao_origem_id
     )
  then
    select *
    into v_origem
    from public.ro_passagem_solicitacoes
    where id = new.solicitacao_origem_id;

    if not found
       or v_origem.status <> 'recusada'
       or v_origem.solicitante_id is distinct from auth.uid()
       or new.solicitante_id is distinct from auth.uid()
    then
      raise exception 'SOLICITACAO_ORIGEM_INVALIDA';
    end if;
  end if;

  return new;
end
$function$
;
CREATE OR REPLACE FUNCTION public.ro_guardar_snapshot_folga()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if old.motivo='folga_campo' and old.folga_alocacao_id is not null then
    if new.folga_alocacao_id is distinct from old.folga_alocacao_id
       or new.folga_distancia_km is distinct from old.folga_distancia_km
       or new.folga_regime_faixa is distinct from old.folga_regime_faixa
       or new.folga_intervalo_dias is distinct from old.folga_intervalo_dias
       or new.funcionario_id is distinct from old.funcionario_id
       or new.colaborador_id is distinct from old.colaborador_id
       or new.obra_id is distinct from old.obra_id
       or new.motivo is distinct from old.motivo then
      raise exception 'SNAPSHOT_FOLGA_IMUTAVEL';
    end if;
  end if;
  -- Nao permitir adicionar snapshots manualmente a pedidos legados.
  if old.folga_alocacao_id is null and (
       new.folga_alocacao_id is not null
       or new.folga_distancia_km is not null
       or new.folga_regime_faixa is not null
       or new.folga_intervalo_dias is not null
     ) then
    raise exception 'SNAPSHOT_FOLGA_SOMENTE_NA_CRIACAO';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.ro_validar_transicao_operacional()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.status='solicitada' and new.status='passagem_comprada' then
    raise exception 'Marque a solicitação como Em andamento antes de executar ações operacionais.';
  end if;
  return new;
end $function$
;
CREATE TRIGGER ro_guardar_snapshot_folga BEFORE UPDATE ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.ro_guardar_snapshot_folga();
CREATE TRIGGER ro_validar_transicao_operacional BEFORE UPDATE ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.ro_validar_transicao_operacional();
CREATE TRIGGER ro_proteger_recusa_terminal BEFORE INSERT OR UPDATE ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.ro_proteger_recusa_terminal();
