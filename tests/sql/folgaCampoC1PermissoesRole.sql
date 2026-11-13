-- HOMOLOGACAO C1 EM POSTGRESQL 17 DESCARTAVEL (dados ficticios).
-- Acesso real como role authenticated e anon; nunca usar em producao.
\set ON_ERROR_STOP on

create or replace function public.ro_can_view_private_addresses(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$
 select exists (select 1 from public.ro_responsaveis r where r.user_id=p_user and r.ativo);
$$;

select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

-- Verificar GRANT de EXECUTE sem acesso direto a tabelas / schema privado.
DO $$
begin
 if not has_function_privilege('authenticated','public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
    or not has_function_privilege('authenticated','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
 then raise exception 'C1_GRANTS_AUTH_AUSENTES'; end if;
 if has_function_privilege('anon','public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)','EXECUTE')
    or has_function_privilege('anon','public.ro_consultar_contexto_distancia_folga(uuid,uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','public.ro_corrigir_distancia_folga(uuid,integer,text)','EXECUTE')
    or has_function_privilege('authenticated','ro_private.autorizar_acesso_folga(uuid)','EXECUTE')
    or has_schema_privilege('authenticated','ro_private','USAGE')
    or has_table_privilege('authenticated','public.ro_folga_alocacoes','SELECT')
    or has_table_privilege('authenticated','public.ro_folga_distancia_auditoria','SELECT')
 then raise exception 'C1_EXPOSICAO_INDEVIDA';end if;
 if (select ativo from ro_private.folga_configuracao where chave='novo_fluxo_distancia') is distinct from false
 then raise exception 'C1_ATIVOU_FLUXO';end if;
end $$;

set role authenticated;

-- Com o gate FALSE todos os endpoints permanecem inoperantes.
DO $$
declare v_msg text;
begin
 begin
  perform public.ro_consultar_contexto_distancia_folga(
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201',null);
  raise exception 'C1_CONSULTA_ACEITOU_GATE_FALSE';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%FOLGA_CAMPO_KM_AINDA_DESATIVADO%' then
   raise exception 'C1_CONSULTA_ERRO:%',v_msg;end if;
 end;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
    jsonb_build_object('id','00000000-0000-0000-0000-000000000901',
      'funcionario_id','00000000-0000-0000-0000-000000000101',
      'obra_id','00000000-0000-0000-0000-000000000201',
      'motivo','folga_campo','data_ida','2027-12-01'),
    '[]'::jsonb,200,false);
  raise exception 'C1_CRIACAO_ACEITOU_GATE_FALSE';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%FOLGA_CAMPO_KM_AINDA_DESATIVADO%' then
   raise exception 'C1_CRIACAO_ERRO:%',v_msg;end if;
 end;
 begin
  perform public.ro_corrigir_distancia_folga(
    '00000000-0000-0000-0000-000000000999',201,
    'Justificativa ficticia de mais de dez caracteres');
  raise exception 'C1_CORRECAO_ACEITOU_GATE_FALSE';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%FOLGA_CAMPO_KM_AINDA_DESATIVADO%' then
   raise exception 'C1_CORRECAO_ERRO:%',v_msg;end if;
 end;
end $$;

reset role;
select pg_catalog.set_config('test.uid','',false);
set role anon;
DO $$
declare v_msg text;
begin
 begin
   perform public.ro_consultar_contexto_distancia_folga(
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000201');
   raise exception 'C1_ANON_CONSEGUIU_CONSULTAR';
 exception when insufficient_privilege then
   null;
 end;
end $$;
reset role;

-- Somente no banco temporario, exercitar cenarios com gate TRUE
-- dentro de transacao REVERTIDA ao final.
begin;
update ro_private.folga_configuracao
set ativo=true where chave='novo_fluxo_distancia';

-- Usuario comum 002: autenticado, sem permissao para cadastro privado.
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
set role authenticated;
DO $$
declare v_msg text; v_count int;
begin
 -- Tentar burlar a RPC com SELECT direto nas tabelas deve falhar.
 begin
   execute 'select count(*) from public.ro_folga_alocacoes' into v_count;
   raise exception 'C1_TABELA_ALOCACOES_EXPOSTA';
 exception when insufficient_privilege then null;
 end;
 begin
   execute 'select count(*) from public.ro_folga_distancia_auditoria' into v_count;
   raise exception 'C1_TABELA_AUDITORIA_EXPOSTA';
 exception when insufficient_privilege then null;
 end;
 -- Funcionario inexistente fora do catalogo nao tem contexto consultavel.
 begin
  perform public.ro_consultar_contexto_distancia_folga(
   '00000000-0000-0000-0000-000000000999',
   '00000000-0000-0000-0000-000000000201',null);
  raise exception 'C1_FUNCIONARIO_INEXISTENTE_CONSULTOU';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%FUNCIONARIO_INDISPONIVEL%' then
   raise exception 'C1_FUNCIONARIO_INDEVIDO_ERRO:%',v_msg;end if;
 end;
end $$;
reset role;

set role authenticated;
DO $$
declare v_msg text;
begin
 begin
  perform public.ro_consultar_contexto_distancia_folga(
    null,'00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701');
  raise exception 'C1_PRIVADO_EXPOSTO_PELA_CONSULTA';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%COLABORADOR_PRIVADO_ACESSO_NEGADO%' then
   raise exception 'C1_PRIVADO_ERRO:%',v_msg;end if;
 end;
 begin
  perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id','00000000-0000-0000-0000-000000000902',
   'colaborador_id','00000000-0000-0000-0000-000000000701',
   'obra_id','00000000-0000-0000-0000-000000000201',
   'motivo','folga_campo','data_ida','2027-12-02'),
   '[]'::jsonb,200,false);
  raise exception 'C1_PRIVADO_EXPOSTO_PELA_CRIACAO';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%COLABORADOR_PRIVADO_ACESSO_NEGADO%' then
   raise exception 'C1_PRIVADO_CRIACAO_ERRO:%',v_msg;end if;
 end;
end $$;
reset role;

-- Operador RO ativo recebe apenas acesso ao cadastro privado ja autorizado.
insert into public.ro_responsaveis(user_id,ativo)
values ('00000000-0000-0000-0000-000000000001',true);
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
set role authenticated;
DO $$
declare c jsonb;
begin
 c:=public.ro_consultar_contexto_distancia_folga(
  null,'00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000701');
 if c->>'estado' is distinct from 'informar'
 then raise exception 'C1_PRIVADO_AUTORIZADO_FALHOU:%',c;end if;
 -- Cadastro privado vinculado ao funcionario 105: identidade canonica.
 c:=public.ro_consultar_contexto_distancia_folga(
  null,'00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000702');
 if c->>'funcionario_id' is distinct from '00000000-0000-0000-0000-000000000105'
    or c->>'estado' is distinct from 'informar'
 then raise exception 'C1_PRIVADO_VINCULADO_FALHOU:%',c;end if;
 c:=public.ro_consultar_contexto_distancia_folga(
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000201',null);
 if c->>'estado' is distinct from 'informar'
 then raise exception 'C1_FUNCIONARIO_REGULAR_FALHOU:%',c;end if;
end $$;
reset role;

-- Login excluido e login banido: recusa ANTES de liberar consultas.
update auth.users set banned_until=now()+interval '1 day'
where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
DO $$
declare v_msg text;
begin
 begin
  perform public.ro_consultar_contexto_distancia_folga(
   null,'00000000-0000-0000-0000-000000000201',
   '00000000-0000-0000-0000-000000000701');
  raise exception 'C1_BANIDO_CONSULTOU';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%USUARIO_INATIVO_OU_BLOQUEADO%' then
   raise exception 'C1_BANIDO_ERRO:%',v_msg;end if;
 end;
end $$;
reset role;
update auth.users set banned_until=null,deleted_at=now()
where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
DO $$
declare v_msg text;
begin
 begin
  perform public.ro_consultar_contexto_distancia_folga(
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201',null);
  raise exception 'C1_EXCLUIDO_CONSULTOU';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%USUARIO_INATIVO_OU_BLOQUEADO%' then
   raise exception 'C1_EXCLUIDO_ERRO:%',v_msg;end if;
 end;
end $$;
reset role;
update auth.users set deleted_at=null
where id='00000000-0000-0000-0000-000000000001';

-- Criacao autorizada gera episodio ficticio que pode ser corrigido somente
-- por perfil autorizado e justificativa; historico da solicitacao nao muda.
set role authenticated;
DO $$
declare v_id uuid:='00000000-0000-0000-0000-000000000903';
begin
 perform public.ro_criar_folga_campo_com_distancia(
   jsonb_build_object('id',v_id,'funcionario_id',
    '00000000-0000-0000-0000-000000000101',
    'obra_id','00000000-0000-0000-0000-000000000201',
    'motivo','folga_campo','data_ida','2027-12-03'),
   '[]'::jsonb,200,false);
end $$;
reset role;

select set_config('test.alocacao_id',(select id::text from public.ro_folga_alocacoes limit 1),false);

-- Usuário comum nao pode corrigir, mesmo conhecendo ID do episodio.
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
set role authenticated;
DO $$
declare v_id uuid; v_msg text;
begin
 v_id:=current_setting('test.alocacao_id')::uuid;
 begin
  perform public.ro_corrigir_distancia_folga(v_id,220,'Justificativa regular de mais de dez caracteres');
  raise exception 'C1_COMUM_CORRIGIU';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA%' then
   raise exception 'C1_COMUM_CORRECAO_ERRO:%',v_msg;end if;
 end;
end $$;
reset role;

select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
set role authenticated;
DO $$
declare v_id uuid; v_old integer; v_msg text; v_aud int;
begin
 v_id:=current_setting('test.alocacao_id')::uuid;
 begin
  perform public.ro_corrigir_distancia_folga(v_id,220,'curta');
  raise exception 'C1_SEM_JUSTIFICATIVA_CORRIGIU';
 exception when others then
  get stacked diagnostics v_msg=message_text;
  if v_msg not like '%JUSTIFICATIVA_CORRECAO_OBRIGATORIA%' then
   raise exception 'C1_JUSTIFICATIVA_ERRO:%',v_msg;end if;
 end;
 perform public.ro_corrigir_distancia_folga(v_id,220,'Justificativa autorizada para corrigir distancia');

end $$;
reset role;
DO $$
declare v_id uuid := current_setting('test.alocacao_id')::uuid;
begin
 if (select distancia_km from public.ro_folga_alocacoes where id=v_id)<>220
   or (select count(*) from public.ro_folga_distancia_auditoria where alocacao_id=v_id and acao='correcao')<>1
   or (select folga_distancia_km from public.ro_passagem_solicitacoes
       where id='00000000-0000-0000-0000-000000000903')<>200
 then raise exception 'C1_CORRECAO_AUDITORIA_SNAPSHOT_FALHOU';end if;
end $$;


-- Coordenador e gerente tambem podem corrigir, conforme a regra existente.
-- A identidade e verificada dentro da funcao privada, sem GRANT nas tabelas.
insert into public.user_roles(user_id,role)
values ('00000000-0000-0000-0000-000000000002','coordenador');
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
set role authenticated;
DO $$
declare v_id uuid := current_setting('test.alocacao_id')::uuid;
begin
 perform public.ro_corrigir_distancia_folga(
  v_id,230,'Ajuste autorizado pela coordenacao de campo');
end $$;
reset role;

delete from public.user_roles
where user_id='00000000-0000-0000-0000-000000000002'
  and role='coordenador';
insert into public.user_roles(user_id,role)
values ('00000000-0000-0000-0000-000000000002','gerente');
set role authenticated;
DO $$
declare v_id uuid := current_setting('test.alocacao_id')::uuid;
begin
 perform public.ro_corrigir_distancia_folga(
  v_id,240,'Revisao autorizada pela gerencia da obra');
end $$;
reset role;
DO $$
declare v_id uuid := current_setting('test.alocacao_id')::uuid;
begin
 if (select distancia_km from public.ro_folga_alocacoes where id=v_id)<>240
    or (select count(*) from public.ro_folga_distancia_auditoria where alocacao_id=v_id and acao='correcao')<>3
    or (select folga_distancia_km from public.ro_passagem_solicitacoes
      where id='00000000-0000-0000-0000-000000000903')<>200
 then raise exception 'C1_COORDENADOR_GERENTE_AUDITORIA_FALHOU';end if;
end $$;

rollback;
select 'FOLGA_C1_ACESSO_COM_GATE_FALSO_E_ATIVO_SIMULADO_OK' as resultado;
