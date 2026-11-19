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
set search_path=public,pg_temp as $
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
end $;


-- Restaura a regra de notificação anterior, compatível com o helper revertido.
create or replace function public.ro_notificar_retorno_pendente()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $
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
end $;

commit;
