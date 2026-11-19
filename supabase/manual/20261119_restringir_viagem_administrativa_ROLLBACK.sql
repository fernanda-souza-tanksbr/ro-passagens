-- ROLLBACK SUPERVISIONADO. Não executar automaticamente.
-- Interromper antes se existirem solicitações administrativas novas com retorno:
-- reverter a função helper apagaria o reconhecimento do retorno desses registros.
begin;
drop trigger if exists ro_validar_passageiro_viagem_administrativa
on public.ro_passagem_solicitacoes;
drop function if exists public.ro_validar_passageiro_viagem_administrativa();

do $$
begin
  if exists (
    select 1 from public.ro_passagem_solicitacoes s
    where s.motivo='viagem_administrativa' and
      (s.data_retorno is not null or s.destino_retorno is not null
      or s.centro_custo_retorno_id is not null or s.retorno_indefinido)
  ) then
    raise exception 'ROLLBACK_RETORNO_BLOQUEADO: dados novos existentes; preservar o helper ou planejar migração sem perda de dados';
  end if;
end $$;

create or replace function public.ro_motivo_possui_retorno(p_motivo text)
returns boolean language sql immutable parallel safe
set search_path=public,pg_temp as $$
  select coalesce(p_motivo in ('ferias','folga_campo','recesso'),false);
$$;

-- Restaura exatamente o contrato anterior do prefill (sem colaborador_id).
create or replace function public.ro_obter_dados_para_refazer_solicitacao(p_solicitacao_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'NAO_AUTENTICADO'; end if;
  select jsonb_build_object(
    'solicitacao_origem_id',s.id,'funcionario_id',s.funcionario_id,'obra_id',s.obra_id,
    'origem',s.origem,'destino',s.destino,'motivo',s.motivo,'desligamento_subtipo',s.desligamento_subtipo,
    'data_ida',s.data_ida,
    'data_retorno',case when public.ro_motivo_possui_retorno(s.motivo) then s.data_retorno end,
    'destino_retorno',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.destino_retorno end,
    'centro_custo_retorno_id',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.centro_custo_retorno_id end,
    'retorno_indefinido',case when public.ro_motivo_possui_retorno(s.motivo) then s.retorno_indefinido else false end,
    'centro_custo_destino_id',s.centro_custo_destino_id,'observacoes_solicitante',s.observacoes_solicitante)
  into v_result from public.ro_passagem_solicitacoes s
  where s.id=p_solicitacao_id and s.solicitante_id=auth.uid() and s.status='recusada';
  if v_result is null then raise exception 'PREFILL_NAO_AUTORIZADO'; end if;
  return v_result;
end $$;


-- Restaura a regra de notificação anterior, compatível com o helper revertido.
create or replace function public.ro_notificar_retorno_pendente()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_nome text; v_limite date; v_ro record; v_msg text;
begin
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
         null::uuid,
         true,
         false,
         true,
         'restrito_ro'::text,
         null::uuid,
         null::text
  from public.ro_funcionarios_enderecos_privados e
  where auth.uid() is not null
    and e.ativo
    and e.funcionario_id is null

  order by 2;
$function$;

-- Remove somente a RPC adicionada no PR #6, sem alterar políticas de RLS.
drop function if exists public.ro_listar_responsaveis_filtro();

commit;
