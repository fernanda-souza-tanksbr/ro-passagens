-- PostgreSQL 17 TEST FIXTURE ONLY. Never connect to Supabase.
-- Sanitized, dependency-limited schema built from versioned migrations:
-- 202607170001_create_ro_passagens.sql, 202608060001_ajusta_campos_retorno.sql,
-- 202608110001_amplia_cadastro_colaboradores_rh.sql and 202609210002.
-- Reconstructs only objects touched by PR #6: NOT a full production clone.
create schema if not exists auth;
do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth, public to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;

create table public.users_profiles(id uuid primary key references auth.users(id),full_name text);
create table public.user_roles(user_id uuid references auth.users(id),role text);
create table public.obras(id uuid primary key,nome text);
create table public.funcionarios(
  id uuid primary key,nome text not null,ativo boolean not null default true,
  visivel_obras_control boolean not null default true,
  visivel_passagens boolean not null default true,escopo_passagens text not null default 'comum',
  deleted_at timestamptz
);
create table public.alocacoes(funcionario_id uuid references public.funcionarios(id),obra_id uuid references public.obras(id),data date);
create table public.ro_funcionarios_enderecos_privados(
  id uuid primary key, nome text not null,
  funcionario_id uuid references public.funcionarios(id),ativo boolean not null default true
);
create table public.ro_passagem_solicitacoes(
 id uuid primary key, funcionario_id uuid references public.funcionarios(id),
 colaborador_id uuid references public.ro_funcionarios_enderecos_privados(id),
 viajante_nome_informado text, obra_id uuid references public.obras(id),
 solicitante_id uuid not null references auth.users(id), origem text not null, destino text not null,
 motivo text not null, desligamento_subtipo text,
 data_ida date not null,data_retorno date,destino_retorno text,
 centro_custo_retorno_id uuid,retorno_indefinido boolean not null default false,
 centro_custo_destino_id uuid,observacoes_solicitante text,
 status text not null default 'solicitada',
 constraint ro_datas_validas check(data_retorno is null or data_retorno >= data_ida),
 constraint ro_pessoa_ck check(funcionario_id is not null or colaborador_id is not null)
);
create table public.ro_passagem_notificacoes(
 id uuid default gen_random_uuid() primary key,
 solicitacao_id uuid references public.ro_passagem_solicitacoes(id),
 canal text,destinatario_tipo text,destinatario text,mensagem text
);
create table public.ro_responsaveis(
 id uuid default gen_random_uuid() primary key,user_id uuid references auth.users(id) unique,
 ativo boolean not null default true,created_at timestamptz default now()
);

create function public.ro_is_operador_ativo(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select p_user is not null and exists(select 1 from public.ro_responsaveis where user_id=p_user and ativo);
$$;
create function public.ro_is_admin(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.user_roles where user_id=p_user and role in ('gerente','diretor'));
$$;
create function public.ro_funcionario_disponivel_para_usuario(p_user uuid,p_funcionario uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select p_user is not null and exists(select 1 from public.funcionarios where id=p_funcionario and ativo);
$$;
grant execute on function public.ro_is_operador_ativo(uuid),public.ro_is_admin(uuid) to authenticated;
grant select on public.ro_responsaveis to authenticated;
alter table public.ro_responsaveis enable row level security;
create policy ro_resp_select on public.ro_responsaveis for select to authenticated
using(user_id=auth.uid() or public.ro_is_admin());

-- Baseline function signatures and return columns reproduced from the existing
-- catalog's versioned migrations; the full function body is a sanitized equivalent.
create function public.ro_catalogo_colaboradores_viagem()
returns table(id uuid,nome text,funcionario_id uuid,ativo boolean,
 visivel_obras_control boolean,visivel_passagens boolean,escopo_passagens text,
 obra_id uuid,obra_nome text)
language sql stable security definer set search_path='' as $$
 select f.id,f.nome,f.id,true,f.visivel_obras_control,
 f.visivel_passagens,f.escopo_passagens,null::uuid,null::text
 from public.funcionarios f where public.ro_funcionario_disponivel_para_usuario(auth.uid(),f.id)
 union all
 select e.id,e.nome,null::uuid,true,false,true,'restrito_ro'::text,null::uuid,null::text
 from public.ro_funcionarios_enderecos_privados e
 where auth.uid() is not null and e.ativo and e.funcionario_id is null
 order by 2
$$;

create function public.ro_motivo_possui_retorno(p_motivo text)
returns boolean language sql immutable parallel safe set search_path=public,pg_temp as $$
 select coalesce(p_motivo in ('ferias','folga_campo','recesso'),false);
$$;
create function public.ro_normalizar_campos_retorno()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if not public.ro_motivo_possui_retorno(new.motivo) then
   new.data_retorno:=null;new.destino_retorno:=null;new.centro_custo_retorno_id:=null;new.retorno_indefinido:=false;
 elsif coalesce(new.retorno_indefinido,false) then
   new.destino_retorno:=null;new.centro_custo_retorno_id:=null;
 else
   new.destino_retorno:=nullif(trim(new.destino_retorno),'');
 end if;
 return new;
end $$;
create trigger ro_normalizar_campos_retorno
before insert or update of motivo,data_retorno,destino_retorno,centro_custo_retorno_id,retorno_indefinido
on public.ro_passagem_solicitacoes for each row execute function public.ro_normalizar_campos_retorno();
alter table public.ro_passagem_solicitacoes
 add constraint ro_campos_retorno_aplicaveis_ck check(
   (public.ro_motivo_possui_retorno(motivo) or
   (data_retorno is null and destino_retorno is null and centro_custo_retorno_id is null and not retorno_indefinido))
   and (not retorno_indefinido or (destino_retorno is null and centro_custo_retorno_id is null))
 );

-- Existing return-prefill and notifications signatures with realistic behavior.
create function public.ro_obter_dados_para_refazer_solicitacao(p_solicitacao_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
 if auth.uid() is null then raise exception 'NAO_AUTENTICADO';end if;
 select jsonb_build_object('solicitacao_origem_id',s.id,'funcionario_id',s.funcionario_id,
   'obra_id',s.obra_id,'origem',s.origem,'destino',s.destino,'motivo',s.motivo,
   'desligamento_subtipo',s.desligamento_subtipo,'data_ida',s.data_ida,
   'data_retorno',case when public.ro_motivo_possui_retorno(s.motivo) then s.data_retorno end,
   'destino_retorno',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.destino_retorno end,
   'centro_custo_retorno_id',case when public.ro_motivo_possui_retorno(s.motivo) and not s.retorno_indefinido then s.centro_custo_retorno_id end,
   'retorno_indefinido',case when public.ro_motivo_possui_retorno(s.motivo) then s.retorno_indefinido else false end,
   'centro_custo_destino_id',s.centro_custo_destino_id,'observacoes_solicitante',s.observacoes_solicitante)
 into v_result from public.ro_passagem_solicitacoes s
 where s.id=p_solicitacao_id and s.solicitante_id=auth.uid() and s.status='recusada';
 if v_result is null then raise exception 'PREFILL_NAO_AUTORIZADO';end if;
 return v_result;
end $$;
create function public.ro_notificar_retorno_pendente()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if public.ro_motivo_possui_retorno(new.motivo) and new.data_retorno is not null and
   (new.centro_custo_retorno_id is null or new.retorno_indefinido) then
  insert into public.ro_passagem_notificacoes(solicitacao_id,canal,destinatario_tipo,destinatario,mensagem)
  values(new.id,'interno','solicitante',new.solicitante_id::text,'Retorno pendente');
 end if;
 return new;
end $$;
create trigger ro_notificar_retorno_pendente
after insert on public.ro_passagem_solicitacoes
for each row execute function public.ro_notificar_retorno_pendente();

grant select,insert,update,delete on public.ro_passagem_solicitacoes to authenticated;
grant select on public.funcionarios,public.ro_funcionarios_enderecos_privados,
 public.obras,public.users_profiles to authenticated;
