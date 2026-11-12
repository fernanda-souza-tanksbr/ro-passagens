-- Testes de regresao da etapa B com funcoes legadas REAIS extraidas por SELECT.
-- PostgreSQL 17 descartavel. Gate permanece false; nada em producao.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype; v_id uuid;
begin
 if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia') is distinct from false
 then raise exception 'B_GATE_ATIVO'; end if;

 v_id:='00000000-0000-0000-0000-000000000801';
 insert into public.ro_passagem_solicitacoes(id,funcionario_id,obra_id,motivo,data_ida,aprovacao_status)
 values(v_id,'00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000201','ferias','2027-04-01','aprovada');
 select * into strict v_s from public.ro_passagem_solicitacoes where id=v_id;
 if v_s.folga_alocacao_id is not null or v_s.folga_antecipada is distinct from false
 then raise exception 'B_MOTIVO_FERIAS_AFETADO';end if;

 v_id:='00000000-0000-0000-0000-000000000802';
 insert into public.ro_passagem_solicitacoes(id,funcionario_id,obra_id,motivo,data_ida,aprovacao_status)
 values(v_id,'00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000201','folga_campo','2027-04-01','aprovada');
 select * into strict v_s from public.ro_passagem_solicitacoes where id=v_id;
 if v_s.folga_alocacao_id is not null or v_s.folga_antecipada is distinct from false
 then raise exception 'B_FOLGA_LEGADA_ALTERADA';end if;
 if not exists (select 1 from public.ro_auditoria_interna where solicitacao_id=v_id and evento='ciclo_folga_calculado')
 then raise exception 'B_AUDITORIA_FOLGA_NAO_GERADA';end if;

 update public.ro_passagem_solicitacoes set status='finalizada' where id=v_id;
 if not exists (select 1 from public.ro_auditoria_interna where solicitacao_id=v_id and evento='ciclo_folga_avancado')
 then raise exception 'B_AUDITORIA_FINALIZACAO_NAO_GERADA';end if;
end $$;

DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000803'; v_s public.ro_passagem_solicitacoes%rowtype; v_err text;
begin
 perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id',v_id,'funcionario_id','00000000-0000-0000-0000-000000000105',
   'obra_id','00000000-0000-0000-0000-000000000202','motivo','folga_campo',
   'data_ida','2027-05-01'),
   '[]'::jsonb,601,false);
 select * into strict v_s from public.ro_passagem_solicitacoes where id=v_id;
 if v_s.folga_distancia_km<>601 or v_s.folga_intervalo_dias<>45
 then raise exception 'B_FOLGA_KM_NAO_ASSOCIADA';end if;
 if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia')
 then raise exception 'B_GATE_LIGADO';end if;

 -- O bloqueio original de compra continua operante para antecipacao pendente.
 perform pg_catalog.set_config('ro.folga_aprovacao_rpc','1',true);
 update public.ro_passagem_solicitacoes
 set folga_antecipacao_status='pendente',folga_antecipada=true
 where id=v_id;
 perform pg_catalog.set_config('ro.folga_aprovacao_rpc','',true);
 if (select folga_antecipacao_status from public.ro_passagem_solicitacoes where id=v_id) is distinct from 'pendente'
 then raise exception 'B_FALHA_CONFIGURAR_PENDENCIA_DE_TESTE'; end if;
 begin
   update public.ro_passagem_solicitacoes set status='passagem_comprada' where id=v_id;
   raise exception 'B_COMPRA_NAO_BLOQUEADA';
 exception when others then
   get stacked diagnostics v_err=message_text;
   if v_err not like '%ANTECIPACAO_FOLGA_PENDENTE%' then
     raise exception 'B_COMPRA_ERRO_INESPERADO:%',v_err;
   end if;
 end;

 -- Snapshot de distancia nao pode ser alterado por UPDATE direto.
 begin
   update public.ro_passagem_solicitacoes set folga_distancia_km=999 where id=v_id;
   raise exception 'B_SNAPSHOT_PODE_SER_FALSIFICADO';
 exception when others then
   get stacked diagnostics v_err=message_text;
   if v_err not like '%SNAPSHOT_FOLGA_IMUTAVEL%' then
     raise exception 'B_SNAPSHOT_ERRO_INESPERADO:%',v_err;
   end if;
 end;
end $$;

select 'FOLGA_ETAPA_B_LEGADO_REAL_REGRESSAO_OK' as resultado;
