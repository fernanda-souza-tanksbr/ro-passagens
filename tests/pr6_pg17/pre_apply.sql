-- Existing administrative request created before application of the PR6 SQL.
-- A historical operational traveler must remain untouched by applying the new trigger.
insert into auth.users(id,email) values
('10000000-0000-0000-0000-000000000001','admin@example.invalid');
insert into public.funcionarios(id,nome,visivel_obras_control,escopo_passagens)
values('30000000-0000-0000-0000-000000000001','Historico operacional ficticio',true,'comum');
insert into public.ro_passagem_solicitacoes
(id,funcionario_id,solicitante_id,origem,destino,motivo,data_ida)
values('50000000-0000-0000-0000-000000000099',
 '30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 'Historico A','Historico B','viagem_administrativa','2026-11-01');
