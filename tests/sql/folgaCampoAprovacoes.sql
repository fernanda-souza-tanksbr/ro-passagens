-- Integracao de aprovacao em PostgreSQL descartavel.
-- Este arquivo NAO replica toda a RPC de producao: simula somente
-- validacao de aprovador, UPDATE apos INSERT, historico e falha posterior.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

alter table public.ro_passagem_solicitacoes
 add column aprovador_id uuid,
 add column aprovado_em timestamptz,
 add column reprovado_em timestamptz,
 add column motivo_reprovacao_aprovador text;

create table public.ro_passagem_historico (
 id bigint generated always as identity primary key,
 solicitacao_id uuid references public.ro_passagem_solicitacoes(id),
 descricao text not null
);

-- Esses helpers sao apenas fixtures, nao substitutos das regras corporativas.
create function public.ro_approval_exempt(p_user uuid)
returns boolean language sql stable as $$
  select exists(select 1 from public.ro_responsaveis r where r.user_id=p_user and r.ativo)
$$;
create function public.ro_is_approval_candidate(p_user uuid)
returns boolean language sql stable as $$
  select exists(select 1 from public.user_roles r where r.user_id=p_user and r.role='coordenador')
$$;

create function public.ro_proteger_campos_aprovacao_teste()
returns trigger language plpgsql as $$
begin
  if (new.aprovador_id,new.aprovacao_status,new.aprovado_em)
     is distinct from
     (old.aprovador_id,old.aprovacao_status,old.aprovado_em)
     and coalesce(pg_catalog.current_setting('ro.aprovacao_rpc',true),'')<>'1'
  then raise exception 'CAMPOS_APROVACAO_SOMENTE_POR_RPC'; end if;
  return new;
end;
$$;
create trigger ro_proteger_campos_aprovacao
before update on public.ro_passagem_solicitacoes
for each row execute function public.ro_proteger_campos_aprovacao_teste();

-- Este stub replica a SEQUENCIA da RPC real, nao todo seu SQL.
create or replace function public.ro_criar_solicitacao_com_aprovador(
 p_solicitacao jsonb,p_documentos jsonb default '[]'::jsonb
) returns uuid language plpgsql as $$
declare
 v_id uuid;
 v_aprovador uuid := nullif(p_solicitacao->>'aprovador_id','')::uuid;
 v_dispensa boolean := public.ro_approval_exempt(auth.uid());
 v_auto boolean := false;
begin
 if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
 if not v_dispensa then
  if v_aprovador is null then raise exception 'APROVADOR_OBRIGATORIO'; end if;
  if not public.ro_is_approval_candidate(v_aprovador) then
   raise exception 'APROVADOR_INVALIDO';
  end if;
  v_auto := v_aprovador=auth.uid() and exists (
    select 1 from public.user_roles r
    where r.user_id=auth.uid() and r.role='coordenador'
  );
  if v_aprovador=auth.uid() and not v_auto then
   raise exception 'AUTOAPROVACAO_NAO_PERMITIDA';
  end if;
 else v_aprovador:=null;
 end if;

 -- Mesmo limite transacional: insere primeiro, aprova depois.
 insert into public.ro_passagem_solicitacoes (
  id,funcionario_id,obra_id,motivo,data_ida,status,
  aprovacao_status,folga_antecipacao_justificativa
 ) values (
  (p_solicitacao->>'id')::uuid,
  (p_solicitacao->>'funcionario_id')::uuid,
  (p_solicitacao->>'obra_id')::uuid,
  p_solicitacao->>'motivo',(p_solicitacao->>'data_ida')::date,
  'solicitada','pendente',p_solicitacao->>'folga_antecipacao_justificativa'
 ) returning id into v_id;

 perform pg_catalog.set_config('ro.aprovacao_rpc','1',true);
 update public.ro_passagem_solicitacoes
 set aprovador_id=v_aprovador,
     aprovacao_status=case when v_dispensa then 'dispensada'
                           when v_auto then 'aprovada'
                           else 'pendente' end,
     aprovado_em=case when v_dispensa or v_auto then pg_catalog.now() end
 where id=v_id;
 perform pg_catalog.set_config('ro.aprovacao_rpc','',true);

 insert into public.ro_passagem_historico(solicitacao_id,descricao)
 values (v_id,'Fluxo de aprovacao ficticio concluido');

 if coalesce((p_solicitacao->>'test_fail_after_approval')::boolean,false) then
  raise exception 'FALHA_FORCADA_APOS_APROVACAO';
 end if;
 return v_id;
end;
$$;

DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000401'; v_km integer;
begin
 -- Usuario ficticio principal ja possui role de coordenador nos testes anteriores.
 perform public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object(
  'id',v_id,'funcionario_id','00000000-0000-0000-0000-000000000101',
  'obra_id','00000000-0000-0000-0000-000000000201',
  'motivo','folga_campo','data_ida','2027-02-01',
  'aprovador_id','00000000-0000-0000-0000-000000000001'
 ),'[]'::jsonb,null,false);
 if (select aprovacao_status from public.ro_passagem_solicitacoes where id=v_id)<>'aprovada'
 then raise exception 'AUTOAPROVACAO_INCORRETA';end if;
 if (select count(*) from public.ro_passagem_historico where solicitacao_id=v_id)<>1
 then raise exception 'HISTORICO_APROVACAO_AUSENTE';end if;
 select folga_distancia_km into v_km from public.ro_passagem_solicitacoes where id=v_id;
 update public.ro_passagem_solicitacoes
 set status='finalizada' where id=v_id;
 if (select folga_distancia_km from public.ro_passagem_solicitacoes where id=v_id)
    is distinct from v_km
 then raise exception 'APROVACAO_OU_STATUS_ALTEROU_KM';end if;
end $$;

DO $$
declare v_a int;v_s int;v_h int;v_err text;
begin
 select count(*) into v_a from public.ro_folga_alocacoes;
 select count(*) into v_s from public.ro_passagem_solicitacoes;
 select count(*) into v_h from public.ro_passagem_historico;
 begin
  -- Troca de CC prepara episodio, mas erro de aprovador deve reverter tudo.
  perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000402',
   'funcionario_id','00000000-0000-0000-0000-000000000101',
   'obra_id','00000000-0000-0000-0000-000000000203',
   'motivo','folga_campo','data_ida','2027-02-20',
   'aprovador_id','00000000-0000-0000-0000-000000000999'),
  '[]'::jsonb,900,false);
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
  get stacked diagnostics v_err=message_text;
  if v_err not like '%APROVADOR_INVALIDO%' then raise exception 'ERRO_INESPERADO %',v_err;end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>v_a or
    (select count(*) from public.ro_passagem_solicitacoes)<>v_s or
    (select count(*) from public.ro_passagem_historico)<>v_h
 then raise exception 'ROLLBACK_APROVADOR_INVALIDO_INCOMPLETO';end if;
end $$;

DO $$
declare v_a int;v_s int;v_h int;v_err text;
begin
 select count(*) into v_a from public.ro_folga_alocacoes;
 select count(*) into v_s from public.ro_passagem_solicitacoes;
 select count(*) into v_h from public.ro_passagem_historico;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000403',
   'funcionario_id','00000000-0000-0000-0000-000000000101',
   'obra_id','00000000-0000-0000-0000-000000000203',
   'motivo','folga_campo','data_ida','2027-02-20',
   'aprovador_id','00000000-0000-0000-0000-000000000001',
   'test_fail_after_approval',true),
  '[]'::jsonb,900,false);
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
  get stacked diagnostics v_err=message_text;
  if v_err not like '%FALHA_FORCADA_APOS_APROVACAO%' then
   raise exception 'ERRO_INESPERADO %',v_err;
  end if;
 end;
 if (select count(*) from public.ro_folga_alocacoes)<>v_a or
    (select count(*) from public.ro_passagem_solicitacoes)<>v_s or
    (select count(*) from public.ro_passagem_historico)<>v_h or
    (select count(*) from ro_private.folga_criacao_contexto)<>0
 then raise exception 'ROLLBACK_POS_APROVACAO_INCOMPLETO';end if;
end $$;
-- Aprovacao pendente por coordenador diferente do solicitante:
-- verificar que o UPDATE do aprovador nao modifica snapshot nem ciclo.
DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000404';
  v_snapshot integer; v_previsao date; v_erro text;
begin
 insert into public.user_roles(user_id,role)
 values ('00000000-0000-0000-0000-000000000002','coordenador');
 perform public.ro_criar_folga_campo_com_distancia(
  jsonb_build_object('id',v_id,
   'funcionario_id','00000000-0000-0000-0000-000000000101',
   'obra_id','00000000-0000-0000-0000-000000000201',
   'motivo','folga_campo','data_ida','2027-03-05',
   'aprovador_id','00000000-0000-0000-0000-000000000002'),
  '[]'::jsonb,null,false);
 select folga_distancia_km,folga_data_prevista_ciclo
 into v_snapshot,v_previsao
 from public.ro_passagem_solicitacoes where id=v_id;
 if (select aprovacao_status from public.ro_passagem_solicitacoes where id=v_id)<>'pendente'
 then raise exception 'APROVACAO_NAO_PENDENTE';end if;
 -- Simula a RPC de decisao que, em producao, e a unica autorizada a atualizar.
 perform pg_catalog.set_config('ro.aprovacao_rpc','1',true);
 update public.ro_passagem_solicitacoes set aprovacao_status='reprovada'
 where id=v_id;
 perform pg_catalog.set_config('ro.aprovacao_rpc','',true);
 if (select folga_distancia_km from public.ro_passagem_solicitacoes where id=v_id)
    is distinct from v_snapshot
 or (select folga_data_prevista_ciclo from public.ro_passagem_solicitacoes where id=v_id)
    is distinct from v_previsao
 then raise exception 'REPROVACAO_ALTEROU_CICLO_OU_SNAPSHOT';end if;
 -- Alteracao direta da aprovacao sem a RPC continua bloqueada.
 begin
  update public.ro_passagem_solicitacoes set aprovacao_status='aprovada'
  where id=v_id;
  raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
  get stacked diagnostics v_erro=message_text;
  if v_erro not like '%CAMPOS_APROVACAO_SOMENTE_POR_RPC%' then
    raise exception 'PROTECAO_APROVACAO_INOPERANTE: %',v_erro;
  end if;
 end;
end $$;

select 'FOLGA_APROVACOES_ISOLADAS_OK' as resultado;
