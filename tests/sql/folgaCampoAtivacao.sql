-- O mecanismo de ativacao fica DESLIGADO por padrao.
-- Teste ficticio apenas em PostgreSQL temporario do GitHub Actions.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

insert into public.ro_funcionarios_enderecos_privados(id,funcionario_id,ativo)
values ('00000000-0000-0000-0000-000000000704',null,true),
       ('00000000-0000-0000-0000-000000000705',null,true),
       ('00000000-0000-0000-0000-000000000706',null,true);

DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000741';
begin
 if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia') then
   raise exception 'FLUXO_LIGADO_PREMATURAMENTE';end if;
 perform public.ro_criar_solicitacao_com_aprovador(
  jsonb_build_object('id',v_id,
    'colaborador_id','00000000-0000-0000-0000-000000000704',
    'obra_id','00000000-0000-0000-0000-000000000201',
    'motivo','folga_campo','data_ida','2027-02-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'), '[]'::jsonb);
 if (select folga_alocacao_id from public.ro_passagem_solicitacoes where id=v_id) is not null
 then raise exception 'LEGADO_RECEBEU_SNAPSHOT_INDEVIDO';end if;
end $$;

update ro_private.folga_configuracao set ativo=true,atualizado_em=now()
where chave='novo_fluxo_distancia';

DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000742';v_erro text;
begin
 begin
  perform public.ro_criar_solicitacao_com_aprovador(
   jsonb_build_object('id',v_id,
    'colaborador_id','00000000-0000-0000-0000-000000000705',
    'obra_id','00000000-0000-0000-0000-000000000202',
    'motivo','folga_campo','data_ida','2027-03-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'), '[]'::jsonb);
  raise exception 'LEGADO_ACEITOU_FOLGA_SEM_DISTANCIA';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like '%FOLGA_CAMPO_DISTANCIA_OBRIGATORIA_NOVO_FLUXO%' then
    raise exception 'ERRO_LEGADO_INESPERADO: %',v_erro;end if;
 end;
 if exists(select 1 from public.ro_passagem_solicitacoes where id=v_id)
 then raise exception 'LEGADO_REJEITADO_DEIXOU_REGISTRO';end if;
end $$;

DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000743';
begin
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id',v_id,
    'colaborador_id','00000000-0000-0000-0000-000000000705',
    'obra_id','00000000-0000-0000-0000-000000000202',
    'motivo','folga_campo','data_ida','2027-03-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb,601,false);
 if (select folga_distancia_km from public.ro_passagem_solicitacoes where id=v_id)<>601
 then raise exception 'NOVO_FLUXO_PRIVADO_FALHOU_COM_REGRA_ATIVA';end if;
 -- Outros motivos continuam acessiveis pela RPC legada.
 perform public.ro_criar_solicitacao_com_aprovador(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000744',
    'colaborador_id','00000000-0000-0000-0000-000000000706',
    'obra_id','00000000-0000-0000-0000-000000000201',
    'motivo','ferias','data_ida','2027-02-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb);
 if not exists(select 1 from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000744' and motivo='ferias')
 then raise exception 'OUTROS_MOTIVOS_BLOQUEADOS_INDEVIDAMENTE';end if;
end $$;

-- Simula reversao da ativacao e confirma retorno do fluxo legado sem DDL.
update ro_private.folga_configuracao set ativo=false,atualizado_em=now()
where chave='novo_fluxo_distancia';

select 'FOLGA_ATIVACAO_CONTROLADA_OK' as resultado;
