-- SOMENTE PREPARAÇÃO. Revisar backup e aplicar SUPERVISIONADAMENTE após homologação.
-- Projeto alvo: Portal TanksBR. Não aplicar por CI nem por Preview.
-- O catálogo RO usa ro_funcionarios_enderecos_privados.id (colaborador_id).
-- ro_funcionarios_enderecos_privados.funcionario_id é o vínculo canônico com Obras Control.
begin;

-- O backend normaliza, persiste e apresenta campos de retorno consultando esta função;
-- alterá-la é necessário além de src/retornoRules.ts.
create or replace function public.ro_motivo_possui_retorno(p_motivo text)
returns boolean language sql immutable parallel safe
set search_path=public,pg_temp as $$
  select coalesce(p_motivo in ('ferias','folga_campo','recesso','viagem_administrativa'),false);
$$;

-- Nenhuma tabela de solicitação é atualizada em massa: o gatilho aplica-se
-- apenas a novas solicitações e mudanças relevantes de identidade, motivo ou datas.
create or replace function public.ro_validar_passageiro_viagem_administrativa()
returns trigger language plpgsql security definer
set search_path = '' as $$
declare
  v_ativo boolean;
  v_vinculo_operacional boolean;
  v_funcionario_vinculado uuid;
begin
  if new.motivo is distinct from 'viagem_administrativa' then return new; end if;

  -- Operações RO de status, compras e aprovações não revalidam dados históricos.
  if tg_op = 'UPDATE'
    and new.motivo is not distinct from old.motivo
    and new.funcionario_id is not distinct from old.funcionario_id
    and new.colaborador_id is not distinct from old.colaborador_id
    and new.viajante_nome_informado is not distinct from old.viajante_nome_informado
    and new.data_ida is not distinct from old.data_ida
    and new.data_retorno is not distinct from old.data_retorno
    and new.destino_retorno is not distinct from old.destino_retorno
    and new.centro_custo_retorno_id is not distinct from old.centro_custo_retorno_id
    and new.retorno_indefinido is not distinct from old.retorno_indefinido
  then return new; end if;

  -- Sem nome avulso nem apenas funcionario_id. O passageiro deve constar
  -- no cadastro privado RO e possuir vínculo não operacional ou nenhum vínculo.
  if new.colaborador_id is null or new.viajante_nome_informado is not null then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  select e.ativo, e.funcionario_id
  into v_ativo, v_funcionario_vinculado
  from public.ro_funcionarios_enderecos_privados e
  where e.id=new.colaborador_id;
  if not coalesce(v_ativo,false) then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  if new.funcionario_id is distinct from v_funcionario_vinculado then
    raise exception 'VIAGEM_ADMINISTRATIVA_VINCULO_DIVERGENTE';
  end if;

  -- O vínculo só é permitido quando não pertence ao cadastro operacional.
  if v_funcionario_vinculado is not null then
    select coalesce(f.visivel_obras_control,true)
    into v_vinculo_operacional
    from public.funcionarios f where f.id=v_funcionario_vinculado;
    if coalesce(v_vinculo_operacional,true) then
      raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
    end if;
  end if;

  if new.data_retorno is not null and new.data_retorno < new.data_ida then
    raise exception 'RETORNO_ANTERIOR_A_IDA';
  end if;
  if new.data_retorno is null and
     (new.destino_retorno is not null or new.centro_custo_retorno_id is not null) then
    raise exception 'DATA_RETORNO_OBRIGATORIA_PARA_TRECHO_RETORNO';
  end if;
  return new;
end;
$$;

revoke all on function public.ro_validar_passageiro_viagem_administrativa()
from public,anon,authenticated;
drop trigger if exists ro_validar_passageiro_viagem_administrativa
on public.ro_passagem_solicitacoes;
create trigger ro_validar_passageiro_viagem_administrativa
before insert or update of motivo,funcionario_id,colaborador_id,viajante_nome_informado,
data_ida,data_retorno,destino_retorno,centro_custo_retorno_id,retorno_indefinido
on public.ro_passagem_solicitacoes for each row
execute function public.ro_validar_passageiro_viagem_administrativa();


-- Refazer solicitação recusada deve usar o ID privado original, não apenas
-- funcionario_id: a identidade privada pode não ter vínculo operacional.
-- Escopo de segurança original permanece: somente o próprio solicitante
-- pode refazer uma solicitação recusada.
create or replace function public.ro_obter_dados_para_refazer_solicitacao(p_solicitacao_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'NAO_AUTENTICADO'; end if;
  select jsonb_build_object(
    'solicitacao_origem_id',s.id,'funcionario_id',s.funcionario_id,
    'colaborador_id',s.colaborador_id,'obra_id',s.obra_id,
    'origem',s.origem,'destino',s.destino,'motivo',s.motivo,
    'desligamento_subtipo',s.desligamento_subtipo,'data_ida',s.data_ida,
    'data_retorno',case when public.ro_motivo_possui_retorno(s.motivo) then s.data_retorno end,
    'destino_retorno',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.destino_retorno end,
    'centro_custo_retorno_id',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.centro_custo_retorno_id end,
    'retorno_indefinido',case when public.ro_motivo_possui_retorno(s.motivo) then s.retorno_indefinido else false end,
    'centro_custo_destino_id',s.centro_custo_destino_id,
    'observacoes_solicitante',s.observacoes_solicitante)
  into v_result from public.ro_passagem_solicitacoes s
  where s.id=p_solicitacao_id and s.solicitante_id=auth.uid() and s.status='recusada';
  if v_result is null then raise exception 'PREFILL_NAO_AUTORIZADO'; end if;
  return v_result;
end $$;


-- Viagem Administrativa não exige centro de custo de retorno.
-- Preserva exatamente a notificação anterior nos demais motivos.
create or replace function public.ro_notificar_retorno_pendente()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_nome text; v_limite date; v_ro record; v_msg text;
begin
  if new.motivo = 'viagem_administrativa' then return new; end if;
  if public.ro_motivo_possui_retorno(new.motivo) and new.data_retorno is not null and (new.centro_custo_retorno_id is null or new.retorno_indefinido) then
    select nome into v_nome from public.funcionarios where id=new.funcionario_id;
    v_limite:=new.data_retorno-10;
    v_msg:=format('Solicitação de retorno pendente para %s. A solicitação deve ser definida até %s, considerando retorno previsto em %s.',v_nome,to_char(v_limite,'DD/MM/YYYY'),to_char(new.data_retorno,'DD/MM/YYYY'));
    insert into public.ro_passagem_notificacoes(solicitacao_id,canal,destinatario_tipo,destinatario,mensagem) values(new.id,'interno','solicitante',new.solicitante_id::text,v_msg);
    for v_ro in select user_id from public.ro_responsaveis where ativo loop
      insert into public.ro_passagem_notificacoes(solicitacao_id,canal,destinatario_tipo,destinatario,mensagem) values(new.id,'interno','ro',v_ro.user_id::text,v_msg);
    end loop;
  end if;
  return new;
end $$;

-- Cadastro importado RO: preservar IDs privados e marcar vínculos não-operacionais.
CREATE OR REPLACE FUNCTION public.ro_catalogo_colaboradores_viagem()
 RETURNS TABLE(id uuid, nome text, funcionario_id uuid, ativo boolean, visivel_obras_control boolean, visivel_passagens boolean, escopo_passagens text, obra_id uuid, obra_nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select f.id,
         f.nome,
         f.id,
         true,
         f.visivel_obras_control,
         f.visivel_passagens,
         f.escopo_passagens,
         atual.obra_id,
         o.nome
  from public.funcionarios f
  left join lateral(
    select a.obra_id
    from public.alocacoes a
    where a.funcionario_id=f.id
    order by a.data desc
    limit 1
  ) atual on f.visivel_obras_control
  left join public.obras o on o.id=atual.obra_id
  where public.ro_funcionario_disponivel_para_usuario(auth.uid(),f.id)

  union all

  select e.id,
         e.nome,
         e.funcionario_id,
         true,
         false,
         true,
         'restrito_ro'::text,
         null::uuid,
         null::text
  from public.ro_funcionarios_enderecos_privados e
  where auth.uid() is not null
    and e.ativo
    and (e.funcionario_id is null or exists (
      select 1 from public.funcionarios f
      where f.id=e.funcionario_id and f.visivel_obras_control = false
    ))

  order by 2;
$function$;


-- A RLS existente em ro_responsaveis deixa cada operador ver somente
-- a si mesmo. Esta RPC retorna o elenco completo sem alterar GRANTs de tabelas.
create or replace function public.ro_listar_responsaveis_filtro()
returns table(user_id uuid, ativo boolean, nome text)
language sql stable security definer set search_path='' as $
  select r.user_id, r.ativo,
    coalesce(nullif(btrim(up.full_name),''), u.email::text, 'Responsável RO') as nome
  from public.ro_responsaveis r
  left join auth.users u on u.id=r.user_id
  left join public.users_profiles up on up.id=r.user_id
  where auth.uid() is not null
    and (public.ro_is_operador_ativo(auth.uid()) or public.ro_is_admin(auth.uid()))
  order by 3, 1;
$;
revoke all on function public.ro_listar_responsaveis_filtro() from public,anon;
grant execute on function public.ro_listar_responsaveis_filtro() to authenticated;

commit;
