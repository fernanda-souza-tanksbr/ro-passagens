-- DEFINICOES REAIS - EXTRAIDAS SOMENTE POR SELECT DO SUPABASE PRODUCAO
-- 12/11/2026. SOMENTE PARA BANCO DESCARTAVEL DE HOMOLOGACAO.
-- NUNCA APLICAR ESTE ARQUIVO AO SUPABASE PRODUCAO.
\set ON_ERROR_STOP on

-- ro_auditar_ciclo_folga_campo | md5 fonte pg_get_functiondef: 589eb30a46581641c8bedf80e3d5e50e
CREATE OR REPLACE FUNCTION public.ro_auditar_ciclo_folga_campo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin if new.motivo='folga_campo' and tg_op='INSERT' then insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por) values('ciclo_folga_calculado',new.id,jsonb_build_object('sem_historico',new.folga_ciclo_anterior_id is null,'ciclo_anterior_id',new.folga_ciclo_anterior_id,'data_prevista',new.folga_data_prevista_ciclo,'data_ida',new.data_ida,'antecipada',new.folga_antecipada,'justificativa',new.folga_antecipacao_justificativa),auth.uid());elsif new.motivo='folga_campo' and old.status is distinct from 'finalizada' and new.status='finalizada' then insert into public.ro_auditoria_interna(evento,solicitacao_id,detalhes,criado_por) values('ciclo_folga_avancado',new.id,jsonb_build_object('ancora',new.folga_data_prevista_ciclo,'proxima_prevista',new.folga_data_prevista_ciclo+90),auth.uid());end if;return new;end $function$;

-- ro_bloquear_compra_antecipacao_pendente | md5 fonte pg_get_functiondef: 292878f70182f054624ac4fc584adef0
CREATE OR REPLACE FUNCTION public.ro_bloquear_compra_antecipacao_pendente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text;v_id uuid;
begin
 if tg_table_name='ro_passagem_solicitacoes' then if old.folga_antecipacao_status='pendente' and (new.status='passagem_comprada' or new.comprado_em is not null or new.comprado_por is not null) then raise exception 'ANTECIPACAO_FOLGA_PENDENTE';end if;return new;end if;
 v_id:=coalesce(new.solicitacao_id,old.solicitacao_id);select folga_antecipacao_status into v_status from public.ro_passagem_solicitacoes where id=v_id;if v_status='pendente' then raise exception 'ANTECIPACAO_FOLGA_PENDENTE';end if;return case when tg_op='DELETE' then old else new end;
end $function$;

-- ro_funcionario_possui_folga_futura_ativa | md5 fonte pg_get_functiondef: 578eefc12bc46adcb7eb28b43f1be794
CREATE OR REPLACE FUNCTION public.ro_funcionario_possui_folga_futura_ativa(p_funcionario_id uuid, p_ignorar_solicitacao_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select s.id
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id
    and s.motivo='folga_campo'
    and s.id is distinct from p_ignorar_solicitacao_id
    and s.excluida_em is null
    and s.data_ida >= (now() at time zone 'America/Sao_Paulo')::date
    and s.status in ('solicitada','em_andamento','passagem_comprada')
    and s.aprovacao_status is distinct from 'reprovada'
  order by s.data_ida,s.created_at
  limit 1;
$function$;

-- ro_obter_ciclo_folga_funcionario | md5 fonte pg_get_functiondef: f2ee6d5e75b95ad35f77c2011e9b41fc
CREATE OR REPLACE FUNCTION public.ro_obter_ciclo_folga_funcionario(p_funcionario_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ultima public.ro_passagem_solicitacoes%rowtype;
  v_futura public.ro_passagem_solicitacoes%rowtype;
  v_proxima date;
begin
  if auth.uid() is null then
    raise exception 'NAO_AUTENTICADO';
  end if;

  select *
  into v_ultima
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id
    and s.motivo='folga_campo'
    and s.status='finalizada'
    and s.data_ida <= (now() at time zone 'America/Sao_Paulo')::date
  order by
    coalesce(s.folga_data_prevista_ciclo,s.data_ida) desc,
    s.data_ida desc
  limit 1;

  if found then
    v_proxima :=
      coalesce(
        v_ultima.folga_data_prevista_ciclo,
        v_ultima.data_ida
      ) + 90;
  end if;

  select *
  into v_futura
  from public.ro_passagem_solicitacoes s
  where s.id =
    public.ro_funcionario_possui_folga_futura_ativa(
      p_funcionario_id,
      null
    );

  return jsonb_build_object(
    'possui_historico',
    v_ultima.id is not null,

    'ultima_solicitacao_id',
    v_ultima.id,

    'ultima_folga_realizada',
    v_ultima.data_ida,

    'ultima_data_prevista_ciclo',
    v_ultima.folga_data_prevista_ciclo,

    'proxima_folga_prevista',
    v_proxima,

    'data_limite_recomendada',
    v_proxima-15,

    'solicitacao_futura_existente_id',
    v_futura.id,

    'solicitacao_futura_data',
    v_futura.data_ida,

    'solicitacao_futura_status',
    v_futura.status,

    'solicitacao_futura_aprovacao_status',
    v_futura.aprovacao_status
  );
end $function$;

-- ro_proteger_aprovacao_antecipacao | md5 fonte pg_get_functiondef: cb419a99aebee95e32daf81036527a1b
CREATE OR REPLACE FUNCTION public.ro_proteger_aprovacao_antecipacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin if (new.folga_antecipacao_status is distinct from old.folga_antecipacao_status or new.folga_antecipacao_analisada_por is distinct from old.folga_antecipacao_analisada_por or new.folga_antecipacao_analisada_em is distinct from old.folga_antecipacao_analisada_em) and coalesce(current_setting('ro.folga_aprovacao_rpc',true),'')<>'1' and not (old.status is distinct from new.status or old.funcionario_id is distinct from new.funcionario_id or old.motivo is distinct from new.motivo or old.data_ida is distinct from new.data_ida or old.folga_antecipacao_justificativa is distinct from new.folga_antecipacao_justificativa) then raise exception 'APROVACAO_ANTECIPACAO_SOMENTE_PELA_RPC';end if;return new;end $function$;

-- ro_validar_ciclo_folga_campo | md5 fonte pg_get_functiondef: 49a68dd1572810e5a18a996cd901df9e
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

-- Gatilho original ro_auditar_ciclo_folga_campo
CREATE TRIGGER ro_auditar_ciclo_folga_campo AFTER INSERT OR UPDATE OF status ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION ro_auditar_ciclo_folga_campo();

-- Gatilho original ro_bloquear_compra_folga_pendente
CREATE TRIGGER ro_bloquear_compra_folga_pendente BEFORE UPDATE ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION ro_bloquear_compra_antecipacao_pendente();

-- Gatilho original ro_proteger_aprovacao_antecipacao
CREATE TRIGGER ro_proteger_aprovacao_antecipacao BEFORE UPDATE ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION ro_proteger_aprovacao_antecipacao();

-- Gatilho original ro_validar_ciclo_folga_campo
CREATE TRIGGER ro_validar_ciclo_folga_campo BEFORE INSERT OR UPDATE OF funcionario_id, motivo, data_ida, status, folga_antecipacao_justificativa ON public.ro_passagem_solicitacoes FOR EACH ROW EXECUTE FUNCTION ro_validar_ciclo_folga_campo();
