-- Continua apos folgaCampoTransacoes.sql na MESMA conexao psql.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

DO $$
declare c jsonb; v_episodio uuid; v_anterior integer;
begin
 c:=public.ro_consultar_contexto_distancia_folga(
 '00000000-0000-0000-0000-000000000101',
 '00000000-0000-0000-0000-000000000201');
 if c->>'estado'<>'reutilizar' or (c->>'distancia_km')::integer<>200
 then raise exception 'CONSULTA_ATUAL_INCONSISTENTE: %',c;end if;
 c:=public.ro_consultar_contexto_distancia_folga(
 '00000000-0000-0000-0000-000000000101',
 '00000000-0000-0000-0000-000000000202');
 if c->>'estado'<>'confirmar' or (c->>'distancia_km')::integer<>601
 then raise exception 'CONSULTA_RETORNO_INCONSISTENTE: %',c;end if;
 c:=public.ro_consultar_contexto_distancia_folga(
 '00000000-0000-0000-0000-000000000101',
 '00000000-0000-0000-0000-000000000203');
 if c->>'estado'<>'informar' or c->>'distancia_km' is not null
 then raise exception 'CONSULTA_NOVA_OBRA_INCONSISTENTE: %',c;end if;
end $$;

DO $$
declare v_erro text;
begin
 perform pg_catalog.set_config('test.uid','',true);
 begin
   perform public.ro_consultar_contexto_distancia_folga(
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201');
   raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%AUTENTICACAO_OBRIGATORIA%' then
     raise exception 'ERRO_DE_AUTENTICACAO_INESPERADO %',v_erro;
   end if;
 end;
end $$;

DO $$
declare v_erro text;
begin
 update public.obras set visivel_passagens=false where id='00000000-0000-0000-0000-000000000203';
 begin
   perform public.ro_consultar_contexto_distancia_folga(
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000203');
   raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%CENTRO_CUSTO_INDISPONIVEL%' then raise exception 'CC_INDEVIDAMENTE_EXPOSTO: %',v_erro; end if;
 end;
 update public.obras set visivel_passagens=true where id='00000000-0000-0000-0000-000000000203';
end $$;

DO $$
declare v_id uuid; v_old integer; v_audit int; v_erro text; v_snapshot integer;
begin
 select id,distancia_km into strict v_id,v_old from public.ro_folga_alocacoes
 where funcionario_id='00000000-0000-0000-0000-000000000101' and encerrada_em is null;
 select count(*) into v_audit from public.ro_folga_distancia_auditoria;
 select folga_distancia_km into v_snapshot from public.ro_passagem_solicitacoes
 where id='00000000-0000-0000-0000-000000000307';
 begin
   perform public.ro_corrigir_distancia_folga(v_id,220,'Justificativa detalhada para correcao');
   raise exception 'TESTE_DEVERIA_FALHAR';
 exception when others then
   get stacked diagnostics v_erro=message_text;
   if v_erro not like '%CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA%' then
     raise exception 'CORRECAO_SEM_PERMISSAO: %',v_erro; end if;
 end;
 insert into public.user_roles(user_id,role)
 values ('00000000-0000-0000-0000-000000000001','coordenador');
 perform public.ro_corrigir_distancia_folga(v_id,220,'Justificativa detalhada para correcao');
 if (select distancia_km from public.ro_folga_alocacoes where id=v_id)<>220
 or (select count(*) from public.ro_folga_distancia_auditoria)<>v_audit+1
 or (select folga_distancia_km from public.ro_passagem_solicitacoes where id='00000000-0000-0000-0000-000000000307')<>v_snapshot
 then raise exception 'CORRECAO_OU_HISTORICO_INCONSISTENTE';end if;
 if not exists (
   select 1 from public.ro_folga_distancia_auditoria
   where alocacao_id=v_id and acao='correcao'
     and distancia_anterior_km=v_old and distancia_nova_km=220
     and length(justificativa)>=10
 ) then raise exception 'AUDITORIA_CORRECAO_INCOMPLETA';end if;
end $$;

-- Coordenador com conta Auth bloqueada ou excluida nao pode corrigir.
DO $$
declare v_id uuid;v_km integer;v_err text;v_audit int;
begin
 select id,distancia_km into strict v_id,v_km
 from public.ro_folga_alocacoes
 where funcionario_id='00000000-0000-0000-0000-000000000101'
   and encerrada_em is null;
 select count(*) into v_audit from public.ro_folga_distancia_auditoria;
 update auth.users set banned_until=now()+interval '1 day'
 where id='00000000-0000-0000-0000-000000000001';
 begin
   perform public.ro_corrigir_distancia_folga(v_id,230,'Correcao indevida por banido');
   raise exception 'BANIDO_PODE_CORRIGIR';
 exception when others then
   get stacked diagnostics v_err=message_text;
   if v_err not like '%CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA%' then
     raise exception 'ERRO_INESPERADO_BANIDO: %',v_err;
   end if;
 end;
 update auth.users set banned_until=null,deleted_at=now()
 where id='00000000-0000-0000-0000-000000000001';
 begin
   perform public.ro_corrigir_distancia_folga(v_id,230,'Correcao indevida por excluido');
   raise exception 'EXCLUIDO_PODE_CORRIGIR';
 exception when others then
   get stacked diagnostics v_err=message_text;
   if v_err not like '%CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA%' then
     raise exception 'ERRO_INESPERADO_EXCLUIDO: %',v_err;
   end if;
 end;
 update auth.users set deleted_at=null
 where id='00000000-0000-0000-0000-000000000001';
 if (select distancia_km from public.ro_folga_alocacoes where id=v_id)<>v_km
    or (select count(*) from public.ro_folga_distancia_auditoria)<>v_audit
 then raise exception 'USUARIO_BLOQUEADO_ALTEROU_DISTANCIA_OU_AUDITORIA';
 end if;
end $$;

select 'FOLGA_SQL_PERMISSOES_OK' as resultado;
