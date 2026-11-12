-- RASCUNHO NAO EXECUTAR EM PRODUCAO
-- Etapa 1: estruturas aditivas, sem substituir funcoes ou triggers existentes.
-- Revisar backup, autorizacoes, politicas e dependencias antes de executar.
begin;

create table if not exists public.ro_folga_alocacoes (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid references public.funcionarios(id),
  colaborador_id uuid references public.ro_funcionarios_enderecos_privados(id),
  constraint ro_folga_alocacoes_identidade check (num_nonnulls(funcionario_id,colaborador_id)=1),
  obra_id uuid not null references public.obras(id),
  iniciada_em timestamptz not null default now(),
  encerrada_em timestamptz,
  distancia_km integer not null check (distancia_km >= 0),
  confirmada_em timestamptz,
  confirmada_por uuid,
  origem_alocacao_id uuid references public.ro_folga_alocacoes(id),
  criado_em timestamptz not null default now(),
  constraint ro_folga_alocacoes_datas check (encerrada_em is null or encerrada_em >= iniciada_em)
);
create unique index if not exists ro_folga_alocacao_ativa_unica
  on public.ro_folga_alocacoes(funcionario_id)
  where encerrada_em is null and funcionario_id is not null;
create unique index if not exists ro_folga_alocacao_privada_ativa_unica
  on public.ro_folga_alocacoes(colaborador_id)
  where encerrada_em is null and colaborador_id is not null;
create index if not exists ro_folga_alocacoes_funcionario_obra
  on public.ro_folga_alocacoes(funcionario_id,obra_id,iniciada_em desc);
create index if not exists ro_folga_alocacoes_colaborador_obra
  on public.ro_folga_alocacoes(colaborador_id,obra_id,iniciada_em desc);
alter table public.ro_folga_alocacoes enable row level security;
revoke all on public.ro_folga_alocacoes from anon,authenticated;

create table if not exists public.ro_folga_distancia_auditoria (
  id bigint generated always as identity primary key,
  alocacao_id uuid not null references public.ro_folga_alocacoes(id),
  distancia_anterior_km integer check (distancia_anterior_km >= 0),
  distancia_nova_km integer not null check (distancia_nova_km >= 0),
  acao text not null check (acao in ('declaracao','confirmacao','correcao')),
  realizado_por uuid not null,
  realizado_em timestamptz not null default now(),
  justificativa text
);
alter table public.ro_folga_distancia_auditoria enable row level security;
revoke all on public.ro_folga_distancia_auditoria from anon,authenticated;

alter table public.ro_passagem_solicitacoes
  add column if not exists folga_alocacao_id uuid references public.ro_folga_alocacoes(id),
  add column if not exists folga_distancia_km integer check (folga_distancia_km >= 0),
  add column if not exists folga_regime_faixa text,
  add column if not exists folga_intervalo_dias integer check (folga_intervalo_dias in (7,14,45,90));

create schema if not exists ro_private;
revoke all on schema ro_private from public,anon,authenticated;

-- Controle privado de ativacao: false preserva o fluxo antigo ate a
-- publicacao coordenada. Nunca alterar diretamente pelo cliente.
create table if not exists ro_private.folga_configuracao (
  chave text primary key check(chave='novo_fluxo_distancia'),
  ativo boolean not null default false,
  atualizado_em timestamptz not null default now()
);
insert into ro_private.folga_configuracao(chave,ativo)
values('novo_fluxo_distancia',false)
on conflict (chave) do nothing;
alter table ro_private.folga_configuracao enable row level security;
revoke all on ro_private.folga_configuracao from public,anon,authenticated;

-- Funcao pura e privada: sem leitura de dados e sem SECURITY DEFINER.
-- Nao conceder EXECUTE a clientes; o servidor devera chama-la na futura RPC.
create or replace function ro_private.regime_folga_km(p_km integer)
returns table(faixa text, intervalo_dias integer, transporte text)
language sql immutable
set search_path = ''
as $$
  select
    case when p_km <= 200 then 'ate_200'
         when p_km <= 600 then '201_600'
         when p_km <= 800 then '601_800'
         when p_km <= 1500 then '801_1500'
         else 'acima_1500' end,
    case when p_km <= 200 then 7
         when p_km <= 600 then 14
         when p_km <= 800 then 45
         else 90 end,
    case when p_km <= 600 then 'onibus'
         when p_km <= 1500 then 'onibus_ou_aviao'
         else 'aviao' end
  where p_km is not null and p_km >= 0;
$$;
revoke all on function ro_private.regime_folga_km(integer) from public,anon,authenticated;

commit;

-- NAO INCLUIDOS NESTA ETAPA:
-- 1. RPC autorizada de declaracao/confirmacao/correcao e identificacao de episodio.
-- 2. RPC de consulta por funcionario e CC com validacao de acesso.
-- 3. Adaptacao da RPC de criacao e triggers; nao alterar cadeia de aprovacao.
-- 4. Backfill e estrategia de dados historicos.
-- 5. Testes de permissao e rollback validado.
-- OBS: a FK funcionarios(id) deve ser confirmada contra o identificador real
-- empregado em ro_passagem_solicitacoes.funcionario_id antes de aplicar.
