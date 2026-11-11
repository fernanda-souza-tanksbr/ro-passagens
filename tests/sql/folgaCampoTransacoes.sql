-- Testes reais em PostgreSQL descartavel. Nunca conectar ao Supabase real.
\set ON_ERROR_STOP on
DO $$
declare v_id uuid := '00000000-0000-0000-0000-000000000301';
declare v_s public.ro_passagem_solicitacoes%rowtype;
begin
 perform public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object('id',v_id,'funcionario_id','00000000-0000-0000-0000-000000000101',
 'obra_id','00000000-0000-0000-0000-000000000201','motivo','folga_campo','data_ida','2026-10-01'),
 '[]'::jsonb,200,false);
 select * into strict v_s from public.ro_passagem_solicitacoes where id=v_id;
 if v_s.folga_distancia_km<>200 or v_s.folga_intervalo_dias<>7 or v_s.folga_alocacao_id is null
 then raise exception 'FALHA_CRIACAO_INICIAL'; end if;
 if (select count(*) from public.ro_folga_alocacoes)<>1 then raise exception 'EPISODIO_NAO_CRIADO'; end if;
 if (select count(*) from ro_private.folga_criacao_contexto)<>0 then raise exception 'CONTEXTO_NAO_LIMPO'; end if;
end $$;

DO $$
declare n_aloc int; n_sol int; n_aud int; v_erro text;
begin
 select count(*) into n_aloc from public.ro_folga_alocacoes;
 select count(*) into n_sol from public.ro_passagem_solicitacoes;
 select count(*) into n_aud from public.ro_folga_distancia_auditoria;
 begin
   perform public.ro_criar_folga_campo_com_distancia(
     jsonb_build_object('id','00000000-0000-0000-0000-000000000302','funcionario_id','00000000-0000-0000-0000-000000000101',
     'obra_id','00000000-0000-0000-0000-000000000202','motivo','folga_campo','data_ida','2026-10-25'),
     '[]'::jsonb,null,false);
   raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%DISTANCIA_OBRIGATORIA_OU_INVALIDA%' then raise exception 'ERRO_INESPERADO %',v_erro; end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>n_aloc
 or (select count(*) from public.ro_passagem_solicitacoes)<>n_sol
 or (select count(*) from public.ro_folga_distancia_auditoria)<>n_aud
 then raise exception 'ROLLBACK_DISTANCIA_FALHOU'; end if;
end $$;

DO $$
declare n_aloc int; n_sol int; n_aud int; v_erro text;
begin
 select count(*) into n_aloc from public.ro_folga_alocacoes;
 select count(*) into n_sol from public.ro_passagem_solicitacoes;
 select count(*) into n_aud from public.ro_folga_distancia_auditoria;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000303','funcionario_id','00000000-0000-0000-0000-000000000101',
   'obra_id','00000000-0000-0000-0000-000000000202','motivo','folga_campo','data_ida','2026-10-25','test_fail',true),
   '[]'::jsonb,601,false);
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%FALHA_FORCADA_APOS_INSERCAO%' then raise exception 'ERRO_INESPERADO %',v_erro; end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>n_aloc
 or (select count(*) from public.ro_passagem_solicitacoes)<>n_sol
 or (select count(*) from public.ro_folga_distancia_auditoria)<>n_aud
 or (select count(*) from ro_private.folga_criacao_contexto)<>0
 then raise exception 'ROLLBACK_POS_INSERT_FALHOU'; end if;
end $$;

DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype;
begin
 perform public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object('id','00000000-0000-0000-0000-000000000304','funcionario_id','00000000-0000-0000-0000-000000000101',
 'obra_id','00000000-0000-0000-0000-000000000201','motivo','folga_campo','data_ida','2026-11-01'),
 '[]'::jsonb,null,false);
 select * into strict v_s from public.ro_passagem_solicitacoes where id='00000000-0000-0000-0000-000000000304';
 if v_s.folga_distancia_km<>200 or (select count(*) from public.ro_folga_alocacoes)<>1
 then raise exception 'REUSO_EPISODIO_FALHOU'; end if;
end $$;

DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype;
begin
 perform public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object('id','00000000-0000-0000-0000-000000000305','funcionario_id','00000000-0000-0000-0000-000000000101',
 'obra_id','00000000-0000-0000-0000-000000000202','motivo','folga_campo','data_ida','2026-11-30'),
 '[]'::jsonb,601,false);
 select * into strict v_s from public.ro_passagem_solicitacoes where id='00000000-0000-0000-0000-000000000305';
 if v_s.folga_distancia_km<>601 or v_s.folga_intervalo_dias<>45
 or (select count(*) from public.ro_folga_alocacoes where encerrada_em is null)<>1
 then raise exception 'TROCA_CC_FALHOU';end if;
end $$;

DO $$
declare n int; v_erro text;
begin
 select count(*) into n from public.ro_folga_alocacoes;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000306','funcionario_id','00000000-0000-0000-0000-000000000101',
  'obra_id','00000000-0000-0000-0000-000000000201','motivo','folga_campo','data_ida','2026-12-20'),
  '[]'::jsonb,null,false);
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%CONFIRMACAO_RETORNO_OBRIGATORIA%' then raise exception 'ERRO_INESPERADO %',v_erro;end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>n then raise exception 'RETORNO_SEM_CONFIRMACAO_GRAVADO';end if;
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000307','funcionario_id','00000000-0000-0000-0000-000000000101',
  'obra_id','00000000-0000-0000-0000-000000000201','motivo','folga_campo','data_ida','2026-12-20'),
  '[]'::jsonb,null,true);
 if (select folga_distancia_km from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000307')<>200
 or (select count(*) from public.ro_folga_alocacoes)<>n+1
 then raise exception 'RETORNO_CONFIRMADO_FALHOU';end if;
end $$;

DO $$
declare antes public.ro_passagem_solicitacoes%rowtype; depois public.ro_passagem_solicitacoes%rowtype; v_erro text;
begin
 select * into strict antes from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000307';
 update public.ro_passagem_solicitacoes set status='finalizada'
 where id='00000000-0000-0000-0000-000000000307';
 select * into strict depois from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000307';
 if depois.folga_distancia_km is distinct from antes.folga_distancia_km
 or depois.folga_data_prevista_ciclo is distinct from antes.folga_data_prevista_ciclo
 then raise exception 'STATUS_RECALCULOU_SNAPSHOT';end if;
 begin
  update public.ro_passagem_solicitacoes set folga_distancia_km=999
  where id='00000000-0000-0000-0000-000000000307';
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like '%SNAPSHOT_FOLGA_IMUTAVEL%' then raise exception 'ERRO_INESPERADO %',v_erro;end if;
 end;
end $$;

DO $$
declare v_interval integer; v_transporte text; v_km integer; v_dias integer;
begin
 for v_km,v_dias in select * from (values (200,7),(201,14),(600,14),(601,45),(800,45),(801,90),(1500,90),(1501,90)) as t(km,dias) loop
  select intervalo_dias,transporte into v_interval,v_transporte from ro_private.regime_folga_km(v_km);
  if v_interval is distinct from v_dias then raise exception 'FAIXA_INVALIDA %',v_km;end if;
  if v_km>1500 and v_transporte<>'aviao' then raise exception 'TRANSPORTE_INVALIDO';end if;
 end loop;
end $$;
select 'FOLGA_SQL_FIXTURE_OK' as resultado;
