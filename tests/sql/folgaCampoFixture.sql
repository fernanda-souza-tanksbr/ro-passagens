-- Banco descartavel para validar os rascunhos de Folga de Campo.
-- Somente fixtures ficticias; NUNCA apontar ao Supabase de producao.
\set ON_ERROR_STOP on
create role anon nologin;
create role authenticated nologin;
create schema if not exists auth;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(pg_catalog.current_setting('test.uid',true),'')::uuid
$$;
create table public.funcionarios(id uuid primary key, ativo boolean not null default true);
create table public.obras(id uuid primary key, nome text not null, visivel_passagens boolean not null default true);
create table public.user_roles(user_id uuid not null, role text not null);
create table public.ro_responsaveis(user_id uuid not null, ativo boolean not null default true);
create function public.ro_is_operador_ativo(p_user uuid)
returns boolean language sql stable as $$
 select exists(select 1 from public.ro_responsaveis where user_id=p_user and ativo)
$$;
create table public.ro_passagem_solicitacoes(
 id uuid primary key default gen_random_uuid(),
 funcionario_id uuid references public.funcionarios(id),
 obra_id uuid references public.obras(id),
 motivo text not null,
 data_ida date not null,
 status text not null default 'solicitada',
 aprovacao_status text not null default 'aprovada',
 folga_data_prevista_ciclo date,
 folga_ciclo_anterior_id uuid,
 folga_antecipada boolean default false,
 folga_antecipacao_justificativa text,
 folga_antecipacao_status text,
 folga_antecipacao_analisada_por uuid,
 folga_antecipacao_analisada_em timestamptz
);
create table public.ro_auditoria_interna(
 id uuid primary key default gen_random_uuid(),
 evento text not null,
 solicitacao_id uuid,
 detalhes jsonb not null,
 criado_por uuid,
 criado_em timestamptz not null default now()
);
create function public.ro_funcionario_disponivel_para_usuario(p_user uuid,p_func uuid)
returns boolean language sql stable as $$
 select p_user is not null and exists(select 1 from public.funcionarios where id=p_func and ativo)
$$;
create function public.ro_catalogo_centros_custo()
returns table(id uuid,nome text) language sql stable as $$
 select o.id,o.nome from public.obras o where auth.uid() is not null and o.visivel_passagens
$$;
create function public.ro_funcionario_possui_folga_futura_ativa(p_func uuid,p_excluir uuid)
returns uuid language sql stable as $$select null::uuid$$;
create function public.ro_obter_ciclo_folga_funcionario(p_func uuid)
returns jsonb language sql stable as $$
 select jsonb_build_object('proxima_folga_prevista',null,'ultima_solicitacao_id',null)
$$;
create function public.ro_criar_solicitacao_com_aprovador(
 p_solicitacao jsonb,p_documentos jsonb default '[]'::jsonb
) returns uuid language plpgsql as $$
declare v_id uuid;
begin
 insert into public.ro_passagem_solicitacoes(
  id,funcionario_id,obra_id,motivo,data_ida,status,aprovacao_status,
  folga_antecipacao_justificativa
 ) values (
  (p_solicitacao->>'id')::uuid,
  (p_solicitacao->>'funcionario_id')::uuid,
  (p_solicitacao->>'obra_id')::uuid,
  p_solicitacao->>'motivo',
  (p_solicitacao->>'data_ida')::date,
  'solicitada','aprovada',
  p_solicitacao->>'folga_antecipacao_justificativa'
 ) returning id into v_id;
 if coalesce((p_solicitacao->>'test_fail')::boolean,false) then
  raise exception 'FALHA_FORCADA_APOS_INSERCAO';
 end if;
 return v_id;
end;
$$;
insert into public.funcionarios(id) values
('00000000-0000-0000-0000-000000000101'),
('00000000-0000-0000-0000-000000000102');
insert into public.obras(id,nome) values
('00000000-0000-0000-0000-000000000201','CC A'),
('00000000-0000-0000-0000-000000000202','CC B'),
('00000000-0000-0000-0000-000000000203','CC C');
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
