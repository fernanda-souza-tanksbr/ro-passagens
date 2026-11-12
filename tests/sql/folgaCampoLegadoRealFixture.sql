-- Extensoes MINIMAS de colunas para executar as funcoes reais capturadas.
-- Somente banco de homologacao temporario (PostgreSQL 17).
\set ON_ERROR_STOP on
alter table public.ro_passagem_solicitacoes
  add column excluida_em timestamptz,
  add column created_at timestamptz not null default now(),
  add column comprado_em timestamptz,
  add column comprado_por uuid;
-- O fixture gera auth.uid() via test.uid; as funcoes capturadas substituem mocks
-- mantendo as assinaturas existentes e as dependencias em public.
select 'FOLGA_FIXTURE_LEGADO_REAL_PREPARADO' as resultado;
