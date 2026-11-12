-- RASCUNHO NAO EXECUTAR EM PRODUCAO
-- Preparacao transacional de contexto de Folga de Campo.
-- Complementa 01-07; NAO substitui isoladamente triggers existentes.
-- A tabela fica em schema privado, sem acesso via Data API.
create schema if not exists ro_private;

create table if not exists ro_private.folga_criacao_contexto (
  solicitacao_id uuid primary key,
  funcionario_id uuid references public.funcionarios(id),
  colaborador_id uuid references public.ro_funcionarios_enderecos_privados(id),
  constraint ro_folga_contexto_identidade check (num_nonnulls(funcionario_id,colaborador_id)=1),
  obra_id uuid not null references public.obras(id),
  alocacao_id uuid not null references public.ro_folga_alocacoes(id),
  distancia_km integer not null check (distancia_km >= 0),
  regime_faixa text not null,
  intervalo_dias integer not null check (intervalo_dias in (7,14,45,90)),
  criado_por uuid not null,
  criado_em timestamptz not null default now()
);

alter table ro_private.folga_criacao_contexto enable row level security;
revoke all on ro_private.folga_criacao_contexto from public, anon, authenticated;
revoke all on schema ro_private from anon, authenticated;

-- Padrao para uso no corpo da RPC SECURITY DEFINER:
-- 1. exigir auth.uid() e validar motivo='folga_campo', funcionario_id,
--    obra_id, id uuid, distancia/confirmacao, permissoes e aprovador.
-- 2. obter lock por funcionario, respeitando a ordem ja usada pelo trigger.
-- 3. chamar ro_private.preparar_episodio_folga; grava episodio e auditoria.
-- 4. inserir contexto nesta tabela COM id da solicitacao e auth.uid().
-- 5. chamar public.ro_criar_solicitacao_com_aprovador com o MESMO id.
-- 6. exigir retorno do MESMO id; apagar contexto antes de retornar.
-- Tudo ocorre numa unica transacao PostgreSQL da RPC. Excecao reverte tudo.
--
-- Padrao para o BEFORE INSERT trigger coordenado:
-- SELECT * FROM ro_private.folga_criacao_contexto
-- WHERE solicitacao_id=NEW.id AND (funcionario_id=NEW.funcionario_id OR colaborador_id=NEW.colaborador_id)
-- AND obra_id=NEW.obra_id AND criado_por=auth.uid();
-- Se encontrou, aplicar snapshot ANTES da insercao e calcular ciclo novo.
-- Se nao encontrou, manter caminho legado sem exigir km.
-- Nunca usar set_config/current_setting como prova de autorizacao.
--
-- IMPORTANTE: um SECURITY DEFINER sem search_path seguro e autorizacao
-- explicita seria vulneravel; nao publicar sem auditoria de grants.
-- O wrapper e o trigger precisam ser ativados na MESMA entrega.
-- A tabela so pode ser gravada por codigo privilegiado e validado.
--
-- PENDENCIAS BLOQUEANTES:
-- * Validar se o id recebido no JSON e realmente preservado em toda a cadeia.
-- * Validar se os gatilhos de UPDATE da aprovacao nao recalculam snapshot.
-- * Conferir existencia da estrutura 01 antes de executar este SQL.
-- * Testar rollback, concorrencia, grants e compatibilidade no ambiente isolado.
-- * Backup e autorizacao explicita antes de qualquer DDL em producao.
