-- PostgreSQL 17 only; all identifiers and names are fictional.
-- Run against fixture.sql, then apply the exact PR6 SQL, then this file.
create or replace function pg_temp.assert_true(p_ok boolean,p_msg text)
returns void language plpgsql as $$
begin if not coalesce(p_ok,false) then raise exception 'ASSERT_FAILED: %',p_msg;end if;end $$;

create or replace function pg_temp.expect_reject(p_sql text,p_message text)
returns void language plpgsql as $$
declare v_message text;
begin
 begin
  execute p_sql;
  raise exception 'EXPECTED_REJECTION_NOT_RAISED';
 exception when others then
  v_message:=sqlerrm;
  if v_message='EXPECTED_REJECTION_NOT_RAISED' or position(p_message in v_message)=0 then
    raise exception 'EXPECTED "%" GOT "%"',p_message,v_message;
  end if;
 end;
end $$;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-000000000001','admin@example.invalid'),
('10000000-0000-0000-0000-000000000002','ro@example.invalid'),
('10000000-0000-0000-0000-000000000003','outside@example.invalid'),
('10000000-0000-0000-0000-000000000004','inactive@example.invalid');
insert into public.users_profiles(id,full_name) values
('10000000-0000-0000-0000-000000000001','Gestor ficticio'),
('10000000-0000-0000-0000-000000000002','Operador ficticio'),
('10000000-0000-0000-0000-000000000004','Operador inativo ficticio');
insert into public.user_roles(user_id,role) values('10000000-0000-0000-0000-000000000001','gerente');
insert into public.ro_responsaveis(user_id,ativo) values
('10000000-0000-0000-0000-000000000002',true),
('10000000-0000-0000-0000-000000000004',false);
insert into public.obras(id,nome) values('20000000-0000-0000-0000-000000000001','Obra ficticia');
insert into public.funcionarios(id,nome,visivel_obras_control,escopo_passagens) values
('30000000-0000-0000-0000-000000000001','Funcionario operacional',true,'comum'),
('30000000-0000-0000-0000-000000000002','Funcionario nao operacional',false,'restrito_ro');
insert into public.ro_funcionarios_enderecos_privados(id,nome,funcionario_id) values
('40000000-0000-0000-0000-000000000001','Importado sem vinculo',null),
('40000000-0000-0000-0000-000000000002','Importado nao operacional','30000000-0000-0000-0000-000000000002'),
('40000000-0000-0000-0000-000000000003','Importado operacional','30000000-0000-0000-0000-000000000001');

select pg_temp.assert_true(public.ro_motivo_possui_retorno('viagem_administrativa'),
 'administrative return allowed after SQL');
select pg_temp.assert_true(not public.ro_motivo_possui_retorno('desligamento'),'other return reasons unchanged');
select pg_temp.assert_true(
 (select count(*)=2 from pg_trigger where tgrelid='public.ro_passagem_solicitacoes'::regclass
 and tgname in ('ro_validar_passageiro_viagem_administrativa','ro_normalizar_campos_retorno') and not tgisinternal),
 'canonical return and eligibility triggers');
select pg_temp.assert_true(
 exists(select 1 from pg_proc where oid='public.ro_listar_responsaveis_filtro()'::regprocedure and prosecdef),
 'roster RPC is SECURITY DEFINER');
select pg_temp.assert_true(
 not has_function_privilege('anon','public.ro_listar_responsaveis_filtro()','execute')
 and has_function_privilege('authenticated','public.ro_listar_responsaveis_filtro()','execute'),
 'RPC grant restricted to authenticated');

-- Catalog uses private IDs, never operational IDs, for administrative eligibility.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
select pg_temp.assert_true(
 (select count(*)=2 from public.ro_catalogo_colaboradores_viagem()
 where id in ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002')),
 'both eligible imported identities visible');
select pg_temp.assert_true(
 (select count(*)=0 from public.ro_catalogo_colaboradores_viagem()
 where id='40000000-0000-0000-0000-000000000003'),
 'operationally linked imported identity is not returned');
select pg_temp.assert_true(
 (select count(*)=2 from public.ro_listar_responsaveis_filtro()),
 'authorized manager sees active and inactive RO members');

-- Authorized RO sees the complete roster without changing table RLS.
begin;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=2 from public.ro_listar_responsaveis_filtro()),'RO sees team');
select pg_temp.assert_true((select count(*)=1 from public.ro_responsaveis),'direct RLS still scopes RO to self');
rollback;

begin;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.ro_listar_responsaveis_filtro()),'outsider gets no roster');
rollback;

select pg_temp.expect_reject($sql$
 insert into public.ro_passagem_solicitacoes(id,funcionario_id,solicitante_id,origem,destino,motivo,data_ida)
 values('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001','A','B','viagem_administrativa','2026-12-01')
$sql$,'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL');

select pg_temp.expect_reject($sql$
 insert into public.ro_passagem_solicitacoes(id,funcionario_id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida)
 values('50000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','A','B',
 'viagem_administrativa','2026-12-01')
$sql$,'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL');

select pg_temp.expect_reject($sql$
 insert into public.ro_passagem_solicitacoes(id,funcionario_id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida)
 values('50000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','A','B',
 'viagem_administrativa','2026-12-01')
$sql$,'VIAGEM_ADMINISTRATIVA_VINCULO_DIVERGENTE');

insert into public.ro_passagem_solicitacoes
(id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida)
values('50000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001','A','B','viagem_administrativa','2026-12-01');
insert into public.ro_passagem_solicitacoes
(id,funcionario_id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida,
 data_retorno,destino_retorno)
values('50000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000002',
 '40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
 'A','B','viagem_administrativa','2026-12-01','2026-12-05','C');
select pg_temp.assert_true(
 (select data_retorno is null from public.ro_passagem_solicitacoes where id='50000000-0000-0000-0000-000000000004'),
 'one-way remains one-way');
select pg_temp.assert_true(
 (select data_retorno='2026-12-05'::date and destino_retorno='C'
  from public.ro_passagem_solicitacoes where id='50000000-0000-0000-0000-000000000005'),
 'optional return persists');

select pg_temp.expect_reject($sql$
 insert into public.ro_passagem_solicitacoes
 (id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida,data_retorno)
 values('50000000-0000-0000-0000-000000000006',
 '40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 'A','B','viagem_administrativa','2026-12-05','2026-12-01')
$sql$,'RETORNO_ANTERIOR_A_IDA');

select pg_temp.expect_reject($sql$
 insert into public.ro_passagem_solicitacoes
 (id,colaborador_id,solicitante_id,origem,destino,motivo,data_ida,destino_retorno)
 values('50000000-0000-0000-0000-000000000007',
 '40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 'A','B','viagem_administrativa','2026-12-01','C')
$sql$,'DATA_RETORNO_OBRIGATORIA_PARA_TRECHO_RETORNO');

-- Status updates on historical administrative trips must remain possible.
update public.ro_passagem_solicitacoes set status='finalizada'
where id='50000000-0000-0000-0000-000000000099';
select pg_temp.assert_true(
 (select status='finalizada' from public.ro_passagem_solicitacoes where id='50000000-0000-0000-0000-000000000099'),
 'legacy status can change');
select pg_temp.expect_reject($sql$
 update public.ro_passagem_solicitacoes set data_ida='2026-12-10'
 where id='50000000-0000-0000-0000-000000000099'
$sql$,'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL');
select pg_temp.assert_true(
 (select count(*)=0 from public.ro_passagem_notificacoes
 where solicitacao_id='50000000-0000-0000-0000-000000000005'),
 'administrative return does not create unnecessary RO notifications');
select 'PR6_POST_APPLY_TESTS_OK' as evidence;
