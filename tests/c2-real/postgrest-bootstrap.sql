-- Somente PostgreSQL 17 descartavel. PostgREST autentica JWT HS256.
\set ON_ERROR_STOP on
create role authenticator login password 'teste_descartavel' noinherit;
grant anon, authenticated to authenticator;
grant usage on schema public to anon,authenticated;
-- Funcoes expostas apenas a authenticated; nao conceder acesso direto a tabelas privadas.
grant execute on function public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb) to authenticated;
revoke execute on function public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb) from public,anon;
-- Adaptador do fixture: auth.uid() usa o claim real enviado por PostgREST, sem perder
-- o parametro test.uid dos testes SQL anteriores.
create or replace function auth.uid() returns uuid language sql stable
as $$ select nullif(coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub',nullif(current_setting('test.uid',true),'')),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;
-- Auth do fixture nao e GoTrue: estas duas identidades sao apenas registros ficticios.
-- RLS aplicado em todas as tabelas publicas do baseline; acesso direto sempre negado.
do $$
declare r record;
begin
 for r in select tablename from pg_tables where schemaname='public' loop
   execute format('alter table public.%I enable row level security',r.tablename);
 end loop;
end $$;
-- Nao conceder SELECT/INSERT/UPDATE direto ao usuario REST.
revoke all on all tables in schema public from anon,authenticated;

-- Helper de acesso privado presente no fixture C1, nao e copia integral da
-- funcao operacional. Autoriza somente responsaveis ficticios ativos.
create or replace function public.ro_can_view_private_addresses(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$
 select exists (select 1 from public.ro_responsaveis r where r.user_id=p_user and r.ativo);
$$;
revoke execute on function public.ro_can_view_private_addresses(uuid) from public,anon;

-- Somente a RPC legada REDUZIDA do fixture recebe SECURITY DEFINER para
-- executar INSERT sob RLS, reproduzindo o caminho de teste da RPC real.
-- Isto NAO comprova as validacoes operacionais da RPC legada de producao.
alter function public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb) security definer;
