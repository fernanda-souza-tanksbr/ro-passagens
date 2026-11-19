BEGIN;
SET LOCAL lock_timeout='3s';
CREATE OR REPLACE FUNCTION public.ro_can_view_internal_document(p_solicitacao uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.ro_desligamento_autorizado(p_solicitacao) and (coalesce(public.ro_is_rh_active(),false) or coalesce(public.ro_can_operate(),false) or coalesce(public.ro_role(),'') in ('gerente','diretor')
    or exists(select 1 from public.ro_passagem_documentos_internos d where d.solicitacao_id=p_solicitacao and d.created_by=auth.uid()));
$function$;
CREATE OR REPLACE FUNCTION public.ro_custos_operacionais_visiveis(p_solicitacao_id uuid)
 RETURNS TABLE(id uuid, tipo text, valor numeric, descricao text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id,c.tipo,c.valor,c.descricao
  from public.ro_passagem_custos c
  join public.ro_passagem_solicitacoes s on s.id=c.solicitacao_id
  where s.id=p_solicitacao_id
    and auth.uid() is not null
    and s.excluida_em is null and public.ro_desligamento_autorizado(s.id)
    and public.ro_is_active_internal_user()
    and c.tipo in('refeicao','uber','outros')
    and c.valor>0
  order by c.created_at,c.id;
$function$;
CREATE OR REPLACE FUNCTION public.ro_listar_minhas_notificacoes()
 RETURNS TABLE(id uuid, solicitacao_id uuid, canal text, destinatario_tipo text, destinatario text, mensagem text, status text, created_at timestamp with time zone, lida_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select n.id,n.solicitacao_id,n.canal,n.destinatario_tipo,n.destinatario,n.mensagem,n.status,n.created_at,l.lida_em
  from public.ro_passagem_notificacoes n left join public.ro_passagem_notificacoes_lidas l on l.notificacao_id=n.id and l.user_id=auth.uid()
  where auth.uid() is not null and public.ro_desligamento_autorizado(n.solicitacao_id) and n.canal='interno' and ((n.destinatario_tipo='solicitante' and n.destinatario=auth.uid()::text)
    or (n.destinatario_tipo='aprovador' and n.destinatario=auth.uid()::text)
    or (n.destinatario_tipo='ro' and n.destinatario is null and exists(select 1 from public.ro_responsaveis r where r.user_id=auth.uid() and r.ativo)))
  order by n.created_at desc limit 100;
$function$;
CREATE OR REPLACE FUNCTION public.ro_nomes_colaboradores_solicitacoes(p_solicitacao_ids uuid[])
 RETURNS TABLE(solicitacao_id uuid, funcionario_nome_exibicao text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.id,coalesce(nullif(btrim(s.viajante_nome_informado),''),nullif(btrim(e.nome),''),nullif(btrim(f.nome),''))
  from public.ro_passagem_solicitacoes s
  left join public.ro_funcionarios_enderecos_privados e on e.id=s.colaborador_id
  left join public.funcionarios f on f.id=s.funcionario_id
  where auth.uid() is not null and public.ro_is_active_internal_user()
    and s.id=any(coalesce(p_solicitacao_ids,'{}'::uuid[])) and public.ro_desligamento_autorizado(s.id)
    and (s.excluida_em is null or public.ro_can_operate())
    and coalesce(nullif(btrim(s.viajante_nome_informado),''),nullif(btrim(e.nome),''),nullif(btrim(f.nome),'')) is not null;
$function$;
CREATE OR REPLACE FUNCTION public.ro_relatorio_centros_custo(p_inicio date DEFAULT NULL::date, p_fim date DEFAULT NULL::date, p_centro_custo_id uuid DEFAULT NULL::uuid, p_sem_centro boolean DEFAULT false, p_status text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text, p_responsavel_ro_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_resultado jsonb;begin
 if not public.ro_can_view_all() then raise exception 'Acesso restrito a diretores, gerentes e equipe RO ativa';end if;
 if p_inicio is not null and p_fim is not null and p_inicio>p_fim then raise exception 'Período inicial não pode ser posterior ao período final';end if;
 with base as(
  select s.* from public.ro_passagem_solicitacoes s
  where s.excluida_em is null and public.ro_desligamento_autorizado(s.id)
   and(p_inicio is null or s.created_at>=p_inicio::timestamptz)
   and(p_fim is null or s.created_at<(p_fim+1)::timestamptz)
   and(p_status is null or s.status=p_status) and(p_motivo is null or s.motivo=p_motivo)
   and(p_responsavel_ro_id is null or s.responsavel_ro_id=p_responsavel_ro_id)
   and((p_centro_custo_id is null and not p_sem_centro)
    or(not p_sem_centro and(s.obra_id=p_centro_custo_id or exists(select 1 from public.ro_passagem_custos cf where cf.solicitacao_id=s.id and coalesce(cf.centro_custo_id,s.obra_id)=p_centro_custo_id)))
    or(p_sem_centro and(s.obra_id is null or exists(select 1 from public.ro_passagem_custos cf where cf.solicitacao_id=s.id and coalesce(cf.centro_custo_id,s.obra_id) is null))))
 ),operacional as(
  select s.obra_id centro_custo_id,count(*)::integer solicitacoes,
   count(*) filter(where s.comprado_em is not null)::integer compradas,
   count(*) filter(where s.status not in('passagem_comprada','finalizada','cancelada'))::integer abertas,
   count(*) filter(where s.status in('em_analise','em_andamento'))::integer aguardando_compra,
   count(*) filter(where s.status not in('passagem_comprada','finalizada','cancelada') and s.data_ida<=current_date+case when s.motivo in('ferias','folga_campo') then 2 else 0 end)::integer atrasadas,
   count(*) filter(where s.houve_imprevisto or exists(select 1 from public.ro_passagem_anexos a where a.solicitacao_id=s.id and(a.complementar or a.imprevisto)))::integer imprevistos
  from base s where(p_centro_custo_id is null and not p_sem_centro) or(not p_sem_centro and s.obra_id=p_centro_custo_id) or(p_sem_centro and s.obra_id is null) group by s.obra_id
 ),financeiro as(
  select coalesce(c.centro_custo_id,s.obra_id) centro_custo_id,coalesce(sum(c.valor),0)::numeric valor_total,
   coalesce(sum(c.valor) filter(where c.descricao ilike 'Passagem complementar:%'),0)::numeric valor_complementar
  from base s join public.ro_passagem_custos c on c.solicitacao_id=s.id
  where(p_centro_custo_id is null and not p_sem_centro) or(not p_sem_centro and coalesce(c.centro_custo_id,s.obra_id)=p_centro_custo_id) or(p_sem_centro and coalesce(c.centro_custo_id,s.obra_id) is null)
  group by coalesce(c.centro_custo_id,s.obra_id)
 ),centros_relatorio as(select centro_custo_id from operacional union select centro_custo_id from financeiro),grupos as(
  select cr.centro_custo_id,coalesce(op.solicitacoes,0) solicitacoes,coalesce(op.compradas,0) compradas,
   coalesce(op.abertas,0) abertas,coalesce(op.aguardando_compra,0) aguardando_compra,coalesce(op.atrasadas,0) atrasadas,
   coalesce(op.imprevistos,0) imprevistos,coalesce(fi.valor_total,0) valor_total,coalesce(fi.valor_complementar,0) valor_complementar
  from centros_relatorio cr left join operacional op on op.centro_custo_id is not distinct from cr.centro_custo_id
  left join financeiro fi on fi.centro_custo_id is not distinct from cr.centro_custo_id)
 select jsonb_build_object(
  'linhas',coalesce((select jsonb_agg(jsonb_build_object('centro_custo_id',g.centro_custo_id,'codigo',o.codigo,'nome',o.nome,'descricao',o.descricao,'solicitacoes',g.solicitacoes,'compradas',g.compradas,'abertas',g.abertas,'aguardando_compra',g.aguardando_compra,'atrasadas',g.atrasadas,'imprevistos',g.imprevistos,'valor_total',g.valor_total,'valor_complementar',g.valor_complementar)) from grupos g left join public.obras o on o.id=g.centro_custo_id),'[]'::jsonb),
  'centros',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'codigo',o.codigo,'nome',o.nome,'descricao',o.descricao) order by lower(coalesce(o.codigo,'')),lower(coalesce(o.nome,o.descricao,''))) from public.obras o),'[]'::jsonb),
  'responsaveis',coalesce((select jsonb_agg(jsonb_build_object('id',ids.id,'nome',coalesce(up.full_name,'Responsável sem identificação')) order by lower(coalesce(up.full_name,''))) from(select distinct responsavel_ro_id id from public.ro_passagem_solicitacoes where responsavel_ro_id is not null and excluida_em is null and public.ro_desligamento_autorizado(id) union select user_id from public.ro_responsaveis where ativo)ids left join public.users_profiles up on up.id=ids.id),'[]'::jsonb),
  'resumo',jsonb_build_object('solicitacoes',(select count(*) from base),'compradas',(select count(*) from base where comprado_em is not null),'abertas',(select count(*) from base where status not in('passagem_comprada','finalizada','cancelada')),
   'imprevistos',(select count(*) from base s where s.houve_imprevisto or exists(select 1 from public.ro_passagem_anexos a where a.solicitacao_id=s.id and(a.complementar or a.imprevisto))),
   'valor_total',(select coalesce(sum(c.valor),0) from base s join public.ro_passagem_custos c on c.solicitacao_id=s.id where(p_centro_custo_id is null and not p_sem_centro) or(not p_sem_centro and coalesce(c.centro_custo_id,s.obra_id)=p_centro_custo_id) or(p_sem_centro and coalesce(c.centro_custo_id,s.obra_id) is null)),
   'valor_complementar',(select coalesce(sum(c.valor),0) from base s join public.ro_passagem_custos c on c.solicitacao_id=s.id where c.descricao ilike 'Passagem complementar:%' and((p_centro_custo_id is null and not p_sem_centro) or(not p_sem_centro and coalesce(c.centro_custo_id,s.obra_id)=p_centro_custo_id) or(p_sem_centro and coalesce(c.centro_custo_id,s.obra_id) is null))))) into v_resultado;
 return v_resultado;
end $function$;
CREATE OR REPLACE FUNCTION public.ro_solicitacao_foi_comprada(p_solicitacao_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists(
    select 1 from public.ro_passagem_solicitacoes s
    where s.id=p_solicitacao_id and public.ro_desligamento_autorizado(s.id) and (
      s.status in ('passagem_comprada','finalizada') or s.comprado_em is not null or s.comprado_por is not null
      or exists(select 1 from public.ro_passagem_custos c where c.solicitacao_id=s.id and c.tipo='passagem' and c.valor>0)
      or exists(select 1 from public.ro_passagem_anexos a where a.solicitacao_id=s.id)
    )
  );
$function$;
CREATE OR REPLACE FUNCTION public.ro_ultimo_pix_viajante(p_colaborador_id uuid DEFAULT NULL::uuid, p_funcionario_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pix text;v_funcionario_explicito uuid;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA';end if;
  if p_colaborador_id is null and p_funcionario_id is null then raise exception 'IDENTIDADE_EXPLICITA_OBRIGATORIA';end if;
  if p_colaborador_id is not null then
    select e.funcionario_id into v_funcionario_explicito from public.ro_funcionarios_enderecos_privados e where e.id=p_colaborador_id and e.ativo;
    if not found then raise exception 'COLABORADOR_INDISPONIVEL';end if;
    if p_funcionario_id is not null and v_funcionario_explicito is distinct from p_funcionario_id then raise exception 'IDENTIDADE_INCONSISTENTE';end if;
    select btrim(s.pix_viajante) into v_pix from public.ro_passagem_solicitacoes s where s.colaborador_id=p_colaborador_id and public.ro_desligamento_autorizado(s.id) and s.pix_viajante is not null and btrim(s.pix_viajante)<>'' order by s.created_at desc,s.id desc limit 1;
    if v_pix is not null then return v_pix;end if;
    p_funcionario_id:=v_funcionario_explicito;
  end if;
  if p_funcionario_id is not null then
    if not exists(select 1 from public.funcionarios f where f.id=p_funcionario_id and f.ativo and f.deleted_at is null and f.visivel_passagens) then raise exception 'FUNCIONARIO_INDISPONIVEL';end if;
    select btrim(s.pix_viajante) into v_pix from public.ro_passagem_solicitacoes s where s.funcionario_id=p_funcionario_id and public.ro_desligamento_autorizado(s.id) and s.pix_viajante is not null and btrim(s.pix_viajante)<>'' order by s.created_at desc,s.id desc limit 1;
  end if;
  return v_pix;
end $function$;
COMMIT;
