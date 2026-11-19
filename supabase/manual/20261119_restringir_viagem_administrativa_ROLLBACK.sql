-- Executar somente sob autorização supervisionada.
begin;
drop trigger if exists ro_validar_passageiro_viagem_administrativa on public.ro_passagem_solicitacoes;
drop function if exists public.ro_validar_passageiro_viagem_administrativa();
commit;
