-- Real production helper definitions, read-only captured; synthetic tables are in rpc-fixture.sql.
CREATE OR REPLACE FUNCTION public.ro_can_operate(p_user uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.ro_responsaveis
    where user_id = p_user
      and ativo
  );
$function$
;
CREATE OR REPLACE FUNCTION public.ro_can_view_private_addresses(p_user uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
  select public.ro_can_manage_private_addresses(p_user) or coalesce(public.ro_is_operador_ativo(p_user),false);
$function$
;
CREATE OR REPLACE FUNCTION public.ro_catalogo_centros_custo()
 RETURNS TABLE(id uuid, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select o.id,o.nome
  from public.obras o
  where auth.uid() is not null
    and o.visivel_passagens
    and o.escopo_passagens in ('comum','restrito_ro')
    and (
      o.escopo_passagens='comum'
      or public.ro_can_view_all()
      or public.ro_is_rh_active(auth.uid())
      or exists (
        select 1 from public.user_roles ur
        where ur.user_id = auth.uid()
          and ur.role::text = 'coordenador'
      )
      or (
        auth.uid() = '3b00961b-274f-4804-a059-2fab22a00118'::uuid
        and o.id = '6fe66889-3b18-4c8f-af27-d2348f7de7a3'::uuid
      )
    )
  order by o.nome;
$function$
;
CREATE OR REPLACE FUNCTION public.ro_funcionario_disponivel_para_usuario(p_user_id uuid, p_funcionario_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_user_id is not null
    and p_funcionario_id is not null
    and exists(
      select 1
      from public.funcionarios f
      where f.id=p_funcionario_id
        and f.ativo
        and f.deleted_at is null
        and f.visivel_passagens
        and f.escopo_passagens in ('comum','restrito_ro')
    );
$function$
;
CREATE OR REPLACE FUNCTION public.ro_is_rh_active(p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists(select 1 from public.ro_rh_responsaveis r where r.user_id=p_user_id and r.ativo);
$function$
;
CREATE OR REPLACE FUNCTION public.ro_motivo_possui_retorno(p_motivo text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_motivo in ('ferias','folga_campo','recesso'),false);
$function$
;
CREATE OR REPLACE FUNCTION public.ro_notificar_equipe_solicitacao_liberada(p_solicitacao_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_nome text; v_sol public.ro_passagem_solicitacoes%rowtype; v_ro record;
begin
  select * into v_sol from public.ro_passagem_solicitacoes where id=p_solicitacao_id;
  if not found or v_sol.aprovacao_status not in('aprovada','dispensada') then raise exception 'SOLICITACAO_NAO_LIBERADA_PARA_O_RO'; end if;
  select coalesce(nullif(btrim(v_sol.viajante_nome_informado),''),nullif(btrim(e.nome),''),nullif(btrim(f.nome),'')) into v_nome
  from (select 1) x left join public.ro_funcionarios_enderecos_privados e on e.id=v_sol.colaborador_id left join public.funcionarios f on f.id=v_sol.funcionario_id;
  for v_ro in select r.user_id from public.ro_responsaveis r where r.ativo loop
    insert into public.ro_passagem_notificacoes(solicitacao_id,canal,destinatario_tipo,destinatario,mensagem)
    values(v_sol.id,'interno','ro',v_ro.user_id::text,format('Nova solicitação de passagem liberada para %s, motivo %s, origem %s, destino %s.',coalesce(v_nome,'Viajante não identificado'),v_sol.motivo,v_sol.origem,v_sol.destino));
  end loop;
end $function$
;
