-- Seguranca para helper de visibilidade que retorna NULL.
-- So executar no PostgreSQL 16 descartavel, apos os demais testes.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

create or replace function public.ro_funcionario_disponivel_para_usuario(p_user uuid,p_func uuid)
returns boolean language sql stable as $$
  select case when p_func='00000000-0000-0000-0000-000000000104'::uuid
    then null::boolean
    else p_user is not null and exists (
      select 1 from public.funcionarios where id=p_func and ativo
    )
  end
$$;
insert into public.funcionarios(id) values ('00000000-0000-0000-0000-000000000104');
DO $$
declare v_erro text; v_episodios int; v_pedidos int;
begin
  select count(*) into v_episodios from public.ro_folga_alocacoes;
  select count(*) into v_pedidos from public.ro_passagem_solicitacoes;
  begin
    perform public.ro_consultar_contexto_distancia_folga(
      '00000000-0000-0000-0000-000000000104',
      '00000000-0000-0000-0000-000000000201');
    raise exception 'CONSULTA_ACEITOU_PERMISSAO_NULA';
  exception when others then
    get stacked diagnostics v_erro=message_text;
    if v_erro not like '%FUNCIONARIO_INDISPONIVEL%' then
      raise exception 'ERRO_CONSULTA_INESPERADO %',v_erro;
    end if;
  end;
  begin
    perform public.ro_criar_folga_campo_com_distancia(
      jsonb_build_object('id','00000000-0000-0000-0000-000000000604',
      'funcionario_id','00000000-0000-0000-0000-000000000104',
      'obra_id','00000000-0000-0000-0000-000000000201',
      'motivo','folga_campo','data_ida','2027-09-05',
      'aprovador_id','00000000-0000-0000-0000-000000000001'),
      '[]'::jsonb,200,false);
    raise exception 'CRIACAO_ACEITOU_PERMISSAO_NULA';
  exception when others then
    get stacked diagnostics v_erro=message_text;
    if v_erro not like '%FUNCIONARIO_INDISPONIVEL%' then
      raise exception 'ERRO_CRIACAO_INESPERADO %',v_erro;
    end if;
  end;
  if (select count(*) from public.ro_folga_alocacoes) <> v_episodios
    or (select count(*) from public.ro_passagem_solicitacoes) <> v_pedidos
  then raise exception 'PERMISSAO_NULA_GRAVOU_REGISTRO'; end if;
end $$;
select 'FOLGA_PERMISSAO_NULA_BLOQUEADA_OK' as resultado;
