-- PREPARADO PARA APLICAÇÃO SUPERVISIONADA. NÃO EXECUTAR AUTOMATICAMENTE.
-- Protege INSERT e alterações de motivo/passageiro; não altera solicitações existentes.
begin;
create or replace function public.ro_validar_passageiro_viagem_administrativa()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_elegivel boolean := false;
begin
  if new.motivo is distinct from 'viagem_administrativa' then return new; end if;
  -- Registros históricos não são revalidados em atualizações operacionais sem alteração de identidade/motivo.
  if tg_op = 'UPDATE' and new.motivo is not distinct from old.motivo
     and new.funcionario_id is not distinct from old.funcionario_id
     and new.colaborador_id is not distinct from old.colaborador_id
     and new.viajante_nome_informado is not distinct from old.viajante_nome_informado then
    return new;
  end if;
  if new.viajante_nome_informado is not null then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  if new.colaborador_id is not null then
    select e.ativo and (f.id is null or (
      coalesce(f.visivel_passagens,false) and not coalesce(f.visivel_obras_control,true)
      and f.escopo_passagens='restrito_ro')) into v_elegivel
    from public.ro_funcionarios_enderecos_privados e
    left join public.funcionarios f on f.id=e.funcionario_id
    where e.id=new.colaborador_id;
  elsif new.funcionario_id is not null then
    select f.ativo and f.deleted_at is null and f.visivel_passagens
      and not f.visivel_obras_control and f.escopo_passagens='restrito_ro'
      into v_elegivel from public.funcionarios f where f.id=new.funcionario_id;
  end if;
  if not coalesce(v_elegivel,false) then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  return new;
end;
$$;
revoke all on function public.ro_validar_passageiro_viagem_administrativa() from public,anon,authenticated;
drop trigger if exists ro_validar_passageiro_viagem_administrativa on public.ro_passagem_solicitacoes;
create trigger ro_validar_passageiro_viagem_administrativa
before insert or update of motivo,funcionario_id,colaborador_id,viajante_nome_informado
on public.ro_passagem_solicitacoes for each row
execute function public.ro_validar_passageiro_viagem_administrativa();
commit;
