-- Homologacao ficticia da Folga de Campo de colaboradores privados.
-- Executar somente em PostgreSQL descartavel APOS aprovacao, duplicidade e concorrencia.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

-- Sem vinculo: cria episodio privado e consulta por colaborador.
DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype; v_c jsonb;
begin
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000711',
    'colaborador_id','00000000-0000-0000-0000-000000000701',
    'obra_id','00000000-0000-0000-0000-000000000201',
    'motivo','folga_campo','data_ida','2026-05-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb,250,false);
 select * into strict v_s from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000711';
 if v_s.funcionario_id is not null or
    v_s.colaborador_id is distinct from '00000000-0000-0000-0000-000000000701'::uuid
    or v_s.folga_distancia_km<>250 or v_s.folga_intervalo_dias<>14
 then raise exception 'FOLGA_PRIVADA_SEM_VINCULO_INCONSISTENTE'; end if;
 if not exists(select 1 from public.ro_folga_alocacoes a
   where a.id=v_s.folga_alocacao_id
    and a.funcionario_id is null
    and a.colaborador_id='00000000-0000-0000-0000-000000000701')
 then raise exception 'EPISODIO_PRIVADO_NAO_LOCALIZADO';end if;
 v_c:=public.ro_consultar_contexto_distancia_folga(
  null,'00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000701');
 if v_c->>'estado'<>'reutilizar' or (v_c->>'distancia_km')::integer<>250
 then raise exception 'CONTEXTO_PRIVADO_INCORRETO: %',v_c;end if;
 update public.ro_passagem_solicitacoes set status='finalizada'
 where id='00000000-0000-0000-0000-000000000711';
end $$;

-- Novo CC, primeira distancia de 601km, sem alterar historico.
DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype;v_c jsonb;
begin
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000712',
    'colaborador_id','00000000-0000-0000-0000-000000000701',
    'obra_id','00000000-0000-0000-0000-000000000202',
    'motivo','folga_campo','data_ida','2027-04-15',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb,601,false);
 select * into strict v_s from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000712';
 if v_s.folga_distancia_km<>601 or v_s.folga_intervalo_dias<>45 or
    v_s.folga_ciclo_anterior_id is distinct from '00000000-0000-0000-0000-000000000711'::uuid
 then raise exception 'CICLO_PRIVADO_SEM_VINCULO_INCORRETO';end if;
 if (select folga_distancia_km from public.ro_passagem_solicitacoes
    where id='00000000-0000-0000-0000-000000000711')<>250
 then raise exception 'HISTORICO_PRIVADO_FOI_ALTERADO';end if;
 v_c:=public.ro_consultar_contexto_distancia_folga(
  null,'00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000701');
 if v_c->>'estado'<>'confirmar' or (v_c->>'distancia_km')::integer<>250
 then raise exception 'RETORNO_PRIVADO_SEM_CONFIRMACAO: %',v_c;end if;
end $$;

-- Duplicidade privada futura deve bloquear e reverter troca de CC.
DO $$
declare n_a int;n_p int;v_erro text;
begin
 select count(*) into n_a from public.ro_folga_alocacoes
 where colaborador_id='00000000-0000-0000-0000-000000000701';
 select count(*) into n_p from public.ro_passagem_solicitacoes
 where colaborador_id='00000000-0000-0000-0000-000000000701';
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000713',
   'colaborador_id','00000000-0000-0000-0000-000000000701',
   'obra_id','00000000-0000-0000-0000-000000000201',
   'motivo','folga_campo','data_ida','2027-05-15',
   'aprovador_id','00000000-0000-0000-0000-000000000001'),
   '[]'::jsonb,null,true);
  raise exception 'DUPLICIDADE_PRIVADA_NAO_BLOQUEADA';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like 'FOLGA_FUTURA_DUPLICADA:%' then
    raise exception 'ERRO_DUPLICIDADE_PRIVADA_INESPERADO: %',v_erro;
  end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes
   where colaborador_id='00000000-0000-0000-0000-000000000701')<>n_a
   or (select count(*) from public.ro_passagem_solicitacoes
   where colaborador_id='00000000-0000-0000-0000-000000000701')<>n_p
 then raise exception 'ROLLBACK_DUPLICIDADE_PRIVADA_FALHOU';end if;
end $$;

-- Com vinculo: solicita como privado, ancora no historico comum.
DO $$
declare v_s public.ro_passagem_solicitacoes%rowtype;v_c jsonb;
begin
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000721',
    'funcionario_id','00000000-0000-0000-0000-000000000105',
    'obra_id','00000000-0000-0000-0000-000000000201',
    'motivo','folga_campo','data_ida','2026-04-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb,200,false);
 update public.ro_passagem_solicitacoes set status='finalizada'
 where id='00000000-0000-0000-0000-000000000721';
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000722',
    'colaborador_id','00000000-0000-0000-0000-000000000702',
    'obra_id','00000000-0000-0000-0000-000000000202',
    'motivo','folga_campo','data_ida','2027-06-01',
    'aprovador_id','00000000-0000-0000-0000-000000000001'),
  '[]'::jsonb,601,false);
 select * into strict v_s from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000722';
 if v_s.funcionario_id is distinct from '00000000-0000-0000-0000-000000000105'::uuid
    or v_s.colaborador_id is distinct from '00000000-0000-0000-0000-000000000702'::uuid
    or v_s.folga_ciclo_anterior_id is distinct from '00000000-0000-0000-0000-000000000721'::uuid
    or v_s.folga_distancia_km<>601 or v_s.folga_intervalo_dias<>45
 then raise exception 'PRIVADO_VINCULADO_HISTORICO_MISTO_INCORRETO';end if;
 if not exists(
  select 1 from public.ro_folga_alocacoes a
  where a.id=v_s.folga_alocacao_id and a.funcionario_id='00000000-0000-0000-0000-000000000105'
  and a.colaborador_id is null
 ) then raise exception 'EPISODIO_VINCULADO_NAO_CANONICO';end if;
 v_c:=public.ro_consultar_contexto_distancia_folga(
  null,'00000000-0000-0000-0000-000000000202',
  '00000000-0000-0000-0000-000000000702');
 if (v_c->>'funcionario_id')::uuid is distinct from '00000000-0000-0000-0000-000000000105'::uuid
 or (v_c->>'distancia_km')::integer<>601
 then raise exception 'CONTEXTO_VINCULADO_INCONSISTENTE: %',v_c;end if;
end $$;

-- Colaborador inativo nao pode produzir episodio mesmo com km.
DO $$
declare n_a int;v_erro text;
begin
 select count(*) into n_a from public.ro_folga_alocacoes;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000731',
   'colaborador_id','00000000-0000-0000-0000-000000000703',
   'obra_id','00000000-0000-0000-0000-000000000201',
   'motivo','folga_campo','data_ida','2027-07-01',
   'aprovador_id','00000000-0000-0000-0000-000000000001'),
   '[]'::jsonb,200,false);
  raise exception 'COLABORADOR_INATIVO_ACEITO';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like 'COLABORADOR_INATIVO_OU_INEXISTENTE%' then
    raise exception 'ERRO_INATIVO_INESPERADO: %',v_erro;end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>n_a
 then raise exception 'EPISODIO_DE_COLABORADOR_INATIVO_CRIADO';end if;
end $$;


-- Retorno privado exige confirmacao mesmo antes de considerar duplicidade.
DO $
declare v_erro text; v_s public.ro_passagem_solicitacoes%rowtype;v_episodio uuid;
begin
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000715',
     'colaborador_id','00000000-0000-0000-0000-000000000701',
     'obra_id','00000000-0000-0000-0000-000000000201',
     'motivo','folga_campo','data_ida','2027-07-01',
     'aprovador_id','00000000-0000-0000-0000-000000000001'),
   '[]'::jsonb,null,false);
  raise exception 'RETORNO_PRIVADO_SEM_CONFIRMACAO_ACEITO';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like '%CONFIRMACAO_RETORNO_OBRIGATORIA%' then
    raise exception 'ERRO_RETORNO_PRIVADO_INESPERADO: %',v_erro;end if;
 end;
 -- A segunda Folga futura e reprovada pela RPC simulada.
 perform pg_catalog.set_config('ro.aprovacao_rpc','1',true);
 update public.ro_passagem_solicitacoes set aprovacao_status='reprovada'
 where id='00000000-0000-0000-0000-000000000712';
 perform pg_catalog.set_config('ro.aprovacao_rpc','',true);
 perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000714',
     'colaborador_id','00000000-0000-0000-0000-000000000701',
     'obra_id','00000000-0000-0000-0000-000000000201',
     'motivo','folga_campo','data_ida','2027-07-01',
     'aprovador_id','00000000-0000-0000-0000-000000000001'),
   '[]'::jsonb,null,true);
 select * into strict v_s from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000714';
 if v_s.folga_distancia_km<>250 or v_s.folga_intervalo_dias<>14
 then raise exception 'RETORNO_PRIVADO_CONFIRMADO_INCORRETO';end if;
 v_episodio:=v_s.folga_alocacao_id;
 -- A correcao global por coordenador afeta episodio vigente, nao snapshots.
 perform public.ro_corrigir_distancia_folga(
   v_episodio,260,'Correcao justificada da distancia privada');
 if (select distancia_km from public.ro_folga_alocacoes where id=v_episodio)<>260
 or (select folga_distancia_km from public.ro_passagem_solicitacoes
     where id='00000000-0000-0000-0000-000000000714')<>250
 or (select folga_distancia_km from public.ro_passagem_solicitacoes
     where id='00000000-0000-0000-0000-000000000711')<>250
 then raise exception 'CORRECAO_PRIVADA_ALTEROU_HISTORICO';end if;
 if not exists (
  select 1 from public.ro_folga_distancia_auditoria a
  where a.alocacao_id=v_episodio and a.acao='correcao'
    and a.distancia_anterior_km=250 and a.distancia_nova_km=260
 ) then raise exception 'CORRECAO_PRIVADA_SEM_AUDITORIA';end if;
end $;

-- Evita associar um colaborador vinculado ao funcionario de outra pessoa.
DO $
declare v_erro text;
begin
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000723',
     'colaborador_id','00000000-0000-0000-0000-000000000702',
     'funcionario_id','00000000-0000-0000-0000-000000000101',
     'obra_id','00000000-0000-0000-0000-000000000203',
     'motivo','folga_campo','data_ida','2027-06-01',
     'aprovador_id','00000000-0000-0000-0000-000000000001'),
    '[]'::jsonb,400,false);
  raise exception 'VINCULO_DE_OUTRO_FUNCIONARIO_ACEITO';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like '%VINCULO_FUNCIONARIO_INCONSISTENTE%' then
    raise exception 'ERRO_SPOOF_VINCULO_INESPERADO: %',v_erro;end if;
 end;
end $;

select 'FOLGA_PRIVADOS_COM_E_SEM_VINCULO_OK' as resultado;
