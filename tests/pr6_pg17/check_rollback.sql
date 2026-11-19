-- Must be run AFTER protected rollback was rejected with new return data,
-- followed by deleting ONLY the fictional new-return record and applying rollback.
do $$
begin
 if public.ro_motivo_possui_retorno('viagem_administrativa') then
   raise exception 'ROLLBACK_FAILED: helper still accepts administrative return';
 end if;
 if to_regprocedure('public.ro_listar_responsaveis_filtro()') is not null then
   raise exception 'ROLLBACK_FAILED: scoped RO roster RPC was not removed';
 end if;
 if exists(select 1 from pg_trigger where tgname='ro_validar_passageiro_viagem_administrativa'
   and tgrelid='public.ro_passagem_solicitacoes'::regclass and not tgisinternal) then
   raise exception 'ROLLBACK_FAILED: eligibility trigger still exists';
 end if;
 if not exists(select 1 from public.ro_passagem_solicitacoes
   where id='50000000-0000-0000-0000-000000000099'
    and status='finalizada' and motivo='viagem_administrativa') then
   raise exception 'ROLLBACK_FAILED: historical records were not preserved';
 end if;
 if not exists(select 1 from public.ro_passagem_solicitacoes
   where id='50000000-0000-0000-0000-000000000004'
    and data_retorno is null and motivo='viagem_administrativa') then
   raise exception 'ROLLBACK_FAILED: one-way admin trip was not preserved';
 end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
do $$
declare n integer;
begin
 select count(*) into n from public.ro_catalogo_colaboradores_viagem()
 where id='40000000-0000-0000-0000-000000000002';
 if n<>0 then raise exception 'ROLLBACK_FAILED: catalog still includes linked private passenger'; end if;
end $$;
select 'PR6_ROLLBACK_TESTS_OK' as evidence;
