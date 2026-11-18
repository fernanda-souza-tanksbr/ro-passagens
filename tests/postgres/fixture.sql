-- Isolated PostgreSQL 17 fixture: minimal real column/type dependencies of the production trigger.
-- No production data or credentials. The trigger itself is loaded unchanged from SQL files.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS ro_private;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claim.sub',true),'')::uuid,'00000000-0000-0000-0000-000000000001'::uuid) $$;
CREATE TABLE public.ro_funcionarios_enderecos_privados (id uuid PRIMARY KEY, funcionario_id uuid, ativo boolean NOT NULL DEFAULT true);
CREATE TABLE ro_private.folga_configuracao (chave text PRIMARY KEY, ativo boolean NOT NULL);
INSERT INTO ro_private.folga_configuracao VALUES ('novo_fluxo_distancia',true);
CREATE TABLE ro_private.folga_criacao_contexto (
 solicitacao_id uuid PRIMARY KEY, funcionario_id uuid, colaborador_id uuid, obra_id uuid,
 criado_por uuid, alocacao_id uuid, distancia_km integer, regime_faixa text, intervalo_dias integer
);
CREATE TABLE public.ro_passagem_solicitacoes (
 id uuid PRIMARY KEY, funcionario_id uuid, colaborador_id uuid, obra_id uuid,
 motivo text NOT NULL DEFAULT 'folga_campo', data_ida date NOT NULL, data_retorno date,
 recusada_em timestamptz, recusada_por uuid, motivo_recusa text,
 excluida_por uuid, motivo_exclusao text, updated_at timestamptz,
 solicitacao_origem_id uuid, solicitante_id uuid,
 retorno_indefinido boolean NOT NULL DEFAULT false, status text NOT NULL DEFAULT 'solicitada',
 aprovacao_status text, excluida_em timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 folga_antecipacao_justificativa text, folga_data_prevista_ciclo date,
 folga_ciclo_anterior_id uuid, folga_antecipada boolean,
 folga_antecipacao_status text, folga_antecipacao_analisada_por uuid,
 folga_antecipacao_analisada_em timestamptz,
 folga_alocacao_id uuid, folga_distancia_km integer,
 folga_regime_faixa text, folga_intervalo_dias integer
);
CREATE TABLE public.ro_auditoria_interna (
 evento text, solicitacao_id uuid, detalhes jsonb, criado_por uuid
);
CREATE FUNCTION public.ro_obter_ciclo_folga_funcionario(uuid) RETURNS jsonb
 LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.ro_funcionario_possui_folga_futura_ativa(p_funcionario uuid,p_ignorar uuid)
 RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT s.id FROM public.ro_passagem_solicitacoes s
 WHERE s.funcionario_id=p_funcionario AND s.id IS DISTINCT FROM p_ignorar
 AND s.motivo='folga_campo' AND s.excluida_em IS NULL
 AND s.data_ida >= (now() AT TIME ZONE 'America/Sao_Paulo')::date
 AND s.status IN ('solicitada','em_andamento','passagem_comprada')
 AND s.aprovacao_status IS DISTINCT FROM 'reprovada'
 ORDER BY s.data_ida,s.created_at LIMIT 1 $$;
-- Match the production refusal guard for the tested terminal-status behavior.
-- Production refusal function and trigger are loaded from production-dependencies.sql.
