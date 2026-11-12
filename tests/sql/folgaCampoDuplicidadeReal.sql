-- Teste isolado da funcao REAL de duplicidade consultada no Supabase.
-- Aplicado DEPOIS dos testes anteriores, que usam o mock sempre-null.
\set ON_ERROR_STOP on
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);

alter table public.ro_passagem_solicitacoes
  add column if not exists excluida_em timestamptz,
  add column if not exists created_at timestamptz not null default now();

-- Copia estrutural do predicado vigente no Supabase em 11/11/2026.
create or replace function public.ro_funcionario_possui_folga_futura_ativa(
  p_funcionario_id uuid,
  p_ignorar_solicitacao_id uuid default null
) returns uuid
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select s.id
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id
    and s.motivo='folga_campo'
    and s.id is distinct from p_ignorar_solicitacao_id
    and s.excluida_em is null
    and s.data_ida >= (now() at time zone 'America/Sao_Paulo')::date
    and s.status in ('solicitada','em_andamento','passagem_comprada')
    and s.aprovacao_status is distinct from 'reprovada'
  order by s.data_ida,s.created_at
  limit 1;
$$;

insert into public.funcionarios(id)
values('00000000-0000-0000-0000-000000000103');

DO $$
declare v_erro text; v_episodios int; v_pedidos int; v_aud int;
begin
  perform public.ro_criar_folga_campo_com_distancia(
    jsonb_build_object(
      'id','00000000-0000-0000-0000-000000000601',
      'funcionario_id','00000000-0000-0000-0000-000000000103',
      'obra_id','00000000-0000-0000-0000-000000000201',
      'motivo','folga_campo','data_ida','2027-08-02',
      'aprovador_id','00000000-0000-0000-0000-000000000001'
    ), '[]'::jsonb, 200, false);

  if not exists(
    select 1 from public.ro_passagem_solicitacoes
    where id='00000000-0000-0000-0000-000000000601'
      and folga_intervalo_dias=7
  ) then raise exception 'PRIMEIRA_FOLGA_AUSENTE';end if;

  select count(*) into v_episodios from public.ro_folga_alocacoes where funcionario_id='00000000-0000-0000-0000-000000000103';
  select count(*) into v_pedidos from public.ro_passagem_solicitacoes where funcionario_id='00000000-0000-0000-0000-000000000103';
  select count(*) into v_aud from public.ro_folga_distancia_auditoria;

  begin
    -- Mesmo funcionario, CC diferente: a segunda criacao nao pode deixar
    -- episodio de transferencia registrado quando houver folga futura ativa.
    perform public.ro_criar_folga_campo_com_distancia(
      jsonb_build_object(
        'id','00000000-0000-0000-0000-000000000602',
        'funcionario_id','00000000-0000-0000-0000-000000000103',
        'obra_id','00000000-0000-0000-0000-000000000202',
        'motivo','folga_campo','data_ida','2027-09-01',
        'aprovador_id','00000000-0000-0000-0000-000000000001'
      ), '[]'::jsonb, 601, false);
    raise exception 'SEGUNDA_FOLGA_DEVERIA_FALHAR';
  exception when others then
    get stacked diagnostics v_erro=message_text;
    if v_erro not like 'FOLGA_FUTURA_DUPLICADA:%' then
      raise exception 'ERRO_NAO_ESPERADO_NA_DUPLICIDADE: %',v_erro;
    end if;
  end;
  if (select count(*) from public.ro_folga_alocacoes
      where funcionario_id='00000000-0000-0000-0000-000000000103')<>v_episodios
     or (select count(*) from public.ro_passagem_solicitacoes
         where funcionario_id='00000000-0000-0000-0000-000000000103')<>v_pedidos
     or (select count(*) from public.ro_folga_distancia_auditoria)<>v_aud
     or (select count(*) from ro_private.folga_criacao_contexto)<>0
  then raise exception 'ROLLBACK_DUPLICIDADE_INCOMPLETO';end if;
end $$;

-- A regra real ignora folga reprovada: sua exclusao do predicado
-- permite uma segunda criacao valida.
DO $$
begin
  -- A fixture exige o mesmo contexto usado pela RPC legitima de aprovacao.
  perform pg_catalog.set_config('ro.aprovacao_rpc','1',true);
  update public.ro_passagem_solicitacoes
     set aprovacao_status='reprovada'
   where id='00000000-0000-0000-0000-000000000601';
  perform pg_catalog.set_config('ro.aprovacao_rpc','',true);
  perform public.ro_criar_folga_campo_com_distancia(
    jsonb_build_object(
      'id','00000000-0000-0000-0000-000000000603',
      'funcionario_id','00000000-0000-0000-0000-000000000103',
      'obra_id','00000000-0000-0000-0000-000000000202',
      'motivo','folga_campo','data_ida','2027-09-01',
      'aprovador_id','00000000-0000-0000-0000-000000000001'
    ), '[]'::jsonb, 601, false);
  if (select folga_distancia_km from public.ro_passagem_solicitacoes
      where id='00000000-0000-0000-0000-000000000603')<>601
  then raise exception 'CRIACAO_APOS_REPROVACAO_FALHOU';end if;
end $$;
select 'FOLGA_DUPLICIDADE_FUTURA_OK' as resultado;
