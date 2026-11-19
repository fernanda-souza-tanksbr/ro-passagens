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
commit;
