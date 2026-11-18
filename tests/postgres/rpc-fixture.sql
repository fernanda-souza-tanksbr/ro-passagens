-- Isolated, synthetic records; these structures enforce real authorization function predicates.
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, deleted_at timestamptz, banned_until timestamptz);
INSERT INTO auth.users(id) VALUES ('00000000-0000-0000-0000-000000000001');
CREATE TABLE IF NOT EXISTS public.user_roles (user_id uuid NOT NULL, role text NOT NULL);
CREATE TABLE IF NOT EXISTS public.ro_folga_alocacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), funcionario_id uuid, colaborador_id uuid,
 obra_id uuid NOT NULL, distancia_km integer NOT NULL CHECK (distancia_km >= 0),
 iniciada_em timestamptz NOT NULL DEFAULT now(), encerrada_em timestamptz,
 confirmada_em timestamptz, confirmada_por uuid, origem_alocacao_id uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS ro_folga_alocacoes_ativa_ci
 ON public.ro_folga_alocacoes(funcionario_id,obra_id) WHERE encerrada_em IS NULL AND funcionario_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.ro_folga_distancia_auditoria (
 alocacao_id uuid, distancia_anterior_km integer, distancia_nova_km integer,
 acao text, realizado_por uuid
);
CREATE TABLE IF NOT EXISTS public.ro_passagem_historico (
 solicitacao_id uuid, status_anterior text, status_novo text, descricao text, criado_por uuid
);
CREATE TABLE IF NOT EXISTS storage.objects (
 id uuid DEFAULT gen_random_uuid(), bucket_id text, name text, owner_id text, metadata jsonb
);
CREATE TABLE IF NOT EXISTS public.ro_passagem_documentos_internos (
 id uuid, solicitacao_id uuid, categoria text, storage_path text,
 arquivo_nome text, mime_type text, tamanho_bytes bigint, created_by uuid
);
-- These extra columns are referenced by the original creation and approval RPCs.
ALTER TABLE public.ro_passagem_solicitacoes
 ADD COLUMN IF NOT EXISTS aprovador_id uuid,
 ADD COLUMN IF NOT EXISTS aprovado_em timestamptz,
 ADD COLUMN IF NOT EXISTS pix_viajante text,
 ADD COLUMN IF NOT EXISTS necessita_hospedagem boolean,
 ADD COLUMN IF NOT EXISTS hospedagem_checkin date,
 ADD COLUMN IF NOT EXISTS hospedagem_checkout date,
 ADD COLUMN IF NOT EXISTS ida_a_partir_horario time,
 ADD COLUMN IF NOT EXISTS origem text,
 ADD COLUMN IF NOT EXISTS destino text,
 ADD COLUMN IF NOT EXISTS destino_retorno text,
 ADD COLUMN IF NOT EXISTS centro_custo_retorno_id uuid,
 ADD COLUMN IF NOT EXISTS centro_custo_destino_id uuid,
 ADD COLUMN IF NOT EXISTS desligamento_subtipo text,
 ADD COLUMN IF NOT EXISTS justificativa_excecao_prazo text,
 ADD COLUMN IF NOT EXISTS prazo_excecao_justificativa text,
 ADD COLUMN IF NOT EXISTS observacoes_solicitante text,
 ADD COLUMN IF NOT EXISTS destino_residencial_origem text,
 ADD COLUMN IF NOT EXISTS destino_residencial_justificativa text,
 ADD COLUMN IF NOT EXISTS primeiro_embarque_em timestamptz,
 ADD COLUMN IF NOT EXISTS prazo_regra_codigo text,
 ADD COLUMN IF NOT EXISTS prazo_tipo text,
 ADD COLUMN IF NOT EXISTS prazo_quantidade integer,
 ADD COLUMN IF NOT EXISTS data_minima_permitida date,
 ADD COLUMN IF NOT EXISTS prazo_excecao boolean;
-- Authorization, cost-center, approval and operational helpers are NOT stubbed here.
-- They must be loaded from their actual production definitions before running RPC calls.
