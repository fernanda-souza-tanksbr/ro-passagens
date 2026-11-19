\set ON_ERROR_STOP on
-- Isolated PostgreSQL 17: column types copied from live information_schema,
-- no production data, no credentials or network calls.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA storage;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
CREATE FUNCTION storage.foldername(path text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
 SELECT string_to_array(path,'/')
$$;
CREATE TABLE storage.objects(id uuid, bucket_id text, name text);
CREATE TABLE public.funcionarios (
 "id" uuid,
 "nome" text,
 "salario" numeric(12,2),
 "encargos" numeric(12,2),
 "categoria_mo" text,
 "ativo" boolean,
 "created_at" timestamp with time zone,
 "data_desligamento" date,
 "deleted_at" timestamp with time zone,
 "deleted_by" uuid,
 "data_admissao" date,
 "visivel_obras_control" boolean,
 "visivel_passagens" boolean,
 "escopo_passagens" text
);
CREATE TABLE public.obras (
 "id" uuid,
 "nome" text,
 "status" text,
 "data_inicio" date,
 "created_at" timestamp with time zone,
 "visivel_obras_control" boolean,
 "visivel_passagens" boolean,
 "escopo_passagens" text,
 "tipo_centro_custo" text,
 "codigo" text,
 "descricao" text
);
CREATE TABLE public.ro_auditoria_interna (
 "id" uuid,
 "evento" text,
 "solicitacao_id" uuid,
 "detalhes" jsonb,
 "criado_em" timestamp with time zone,
 "criado_por" uuid
);
CREATE TABLE public.ro_funcionarios_enderecos_privados (
 "id" uuid,
 "funcionario_id" uuid,
 "nome" text,
 "cep" text,
 "logradouro" text,
 "numero" text,
 "complemento" text,
 "bairro" text,
 "cidade" text,
 "uf" text,
 "criado_em" timestamp with time zone,
 "criado_por" uuid,
 "atualizado_em" timestamp with time zone,
 "atualizado_por" uuid,
 "data_nascimento" date,
 "cpf" text,
 "rg" text,
 "telefone" text,
 "ativo" boolean
);
CREATE TABLE public.ro_passagem_anexos (
 "id" uuid,
 "solicitacao_id" uuid,
 "tipo" text,
 "nome_arquivo" text,
 "storage_path" text,
 "mime_type" text,
 "tamanho_bytes" bigint,
 "uploaded_by" uuid,
 "created_at" timestamp with time zone,
 "partida_em" timestamp with time zone,
 "valor" numeric(12,2),
 "observacao" text,
 "complementar" boolean,
 "imprevisto" boolean,
 "motivo_complementar" text,
 "criado_por" uuid,
 "criado_em" timestamp with time zone,
 "conteudo_sha256" text,
 "custo_id" uuid,
 "complemento_id" uuid
);
CREATE TABLE public.ro_passagem_custos (
 "id" uuid,
 "solicitacao_id" uuid,
 "tipo" text,
 "descricao" text,
 "valor" numeric(12,2),
 "created_at" timestamp with time zone,
 "created_by" uuid,
 "centro_custo_id" uuid,
 "compra_chave" text,
 "passagem_complementar" boolean,
 "complemento_id" uuid
);
CREATE TABLE public.ro_passagem_documentos_internos (
 "id" uuid,
 "solicitacao_id" uuid,
 "categoria" text,
 "storage_path" text,
 "arquivo_nome" text,
 "mime_type" text,
 "tamanho_bytes" bigint,
 "created_at" timestamp with time zone,
 "created_by" uuid
);
CREATE TABLE public.ro_passagem_historico (
 "id" uuid,
 "solicitacao_id" uuid,
 "status_anterior" text,
 "status_novo" text,
 "descricao" text,
 "criado_por" uuid,
 "created_at" timestamp with time zone,
 "complemento_id" uuid
);
CREATE TABLE public.ro_passagem_notificacoes (
 "id" uuid,
 "solicitacao_id" uuid,
 "canal" text,
 "destinatario_tipo" text,
 "destinatario" text,
 "mensagem" text,
 "status" text,
 "erro" text,
 "created_at" timestamp with time zone,
 "sent_at" timestamp with time zone
);
CREATE TABLE public.ro_passagem_notificacoes_lidas (
 "notificacao_id" uuid,
 "user_id" uuid,
 "lida_em" timestamp with time zone
);
CREATE TABLE public.ro_passagem_solicitacoes (
 "id" uuid,
 "funcionario_id" uuid,
 "obra_id" uuid,
 "solicitante_id" uuid,
 "origem" text,
 "destino" text,
 "motivo" text,
 "data_ida" date,
 "data_retorno" date,
 "status" text,
 "observacoes_solicitante" text,
 "observacoes_ro" text,
 "tipo_transporte" text,
 "companhia" text,
 "localizador" text,
 "origem_comprada" text,
 "destino_comprado" text,
 "partida_em" timestamp with time zone,
 "chegada_em" timestamp with time zone,
 "comprado_em" timestamp with time zone,
 "comprado_por" uuid,
 "created_at" timestamp with time zone,
 "updated_at" timestamp with time zone,
 "centro_custo_retorno_id" uuid,
 "retorno_indefinido" boolean,
 "centro_custo_destino_id" uuid,
 "justificativa_excecao_prazo" text,
 "chegou_ao_destino" boolean,
 "data_chegada_confirmada" timestamp with time zone,
 "houve_imprevisto" boolean,
 "observacao_finalizacao" text,
 "finalizado_por" uuid,
 "finalizado_em" timestamp with time zone,
 "responsavel_ro_id" uuid,
 "assumida_em" timestamp with time zone,
 "desligamento_subtipo" text,
 "primeiro_embarque_em" timestamp with time zone,
 "origem_solicitacao" text,
 "prazo_regra_codigo" text,
 "prazo_tipo" text,
 "prazo_quantidade" integer,
 "data_minima_permitida" date,
 "prazo_calculado_em" timestamp with time zone,
 "prazo_excecao" boolean,
 "prazo_excecao_justificativa" text,
 "prazo_excecao_por" uuid,
 "prazo_excecao_em" timestamp with time zone,
 "recusada_em" timestamp with time zone,
 "recusada_por" uuid,
 "motivo_recusa" text,
 "solicitacao_origem_id" uuid,
 "folga_data_prevista_ciclo" date,
 "folga_ciclo_anterior_id" uuid,
 "folga_antecipada" boolean,
 "folga_antecipacao_justificativa" text,
 "folga_antecipacao_status" text,
 "folga_antecipacao_analisada_por" uuid,
 "folga_antecipacao_analisada_em" timestamp with time zone,
 "destino_retorno" text,
 "destino_residencial_origem" text,
 "destino_residencial_justificativa" text,
 "colaborador_id" uuid,
 "pix_viajante" text,
 "necessita_hospedagem" boolean,
 "hospedagem_checkin" date,
 "hospedagem_checkout" date,
 "ida_a_partir_horario" time without time zone,
 "excluida_em" timestamp with time zone,
 "excluida_por" uuid,
 "motivo_exclusao" text,
 "aprovador_id" uuid,
 "aprovacao_status" text,
 "aprovado_em" timestamp with time zone,
 "reprovado_em" timestamp with time zone,
 "motivo_reprovacao_aprovador" text,
 "viajante_nome_informado" text,
 "folga_alocacao_id" uuid,
 "folga_distancia_km" integer,
 "folga_regime_faixa" text,
 "folga_intervalo_dias" integer
);
CREATE TABLE public.ro_resolucao_operacional (
 "solicitacao_id" uuid,
 "hospedagem_utilizada" boolean,
 "hospedagem_justificativa" text,
 "hospedagem_confirmado_por" uuid,
 "hospedagem_confirmado_em" timestamp with time zone,
 "divergencias_data" jsonb,
 "data_confirmado_por" uuid,
 "data_confirmado_em" timestamp with time zone
);
CREATE TABLE public.ro_responsaveis (
 "id" uuid,
 "user_id" uuid,
 "ativo" boolean,
 "created_at" timestamp with time zone
);
CREATE TABLE public.users_profiles (
 "id" uuid,
 "full_name" text,
 "created_at" timestamp with time zone,
 "email" text
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public,storage,auth TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;
CREATE FUNCTION public.ro_is_active_internal_user() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND current_setting('test.inactive',true) IS DISTINCT FROM 'true'
$$;
CREATE FUNCTION public.ro_can_operate() RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.ro_responsaveis r WHERE r.user_id=auth.uid() AND r.ativo)
$$;
CREATE FUNCTION public.ro_is_rh_active() RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT current_setting('test.rh',true)='true'
$$;
CREATE FUNCTION public.ro_role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT current_setting('test.role',true)
$$;
CREATE FUNCTION public.ro_can_view_all() RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT public.ro_can_operate() OR current_setting('test.role',true) IN ('gerente','diretor')
$$;
ALTER TABLE public.ro_passagem_solicitacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_solicitacoes FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_passagem_custos ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_custos FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_passagem_historico ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_historico FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_passagem_notificacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_notificacoes FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_passagem_documentos_internos ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_documentos_internos FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_passagem_anexos ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_passagem_anexos FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_auditoria_interna ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_auditoria_interna FOR ALL TO authenticated USING(true) WITH CHECK(true);
ALTER TABLE public.ro_resolucao_operacional ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_permissive ON public.ro_resolucao_operacional FOR ALL TO authenticated USING(true) WITH CHECK(true);
CREATE POLICY fixture_storage_permissive ON storage.objects FOR ALL TO authenticated USING(true) WITH CHECK(true);
-- Install the seven exact original RPC definitions captured from production.
\i security/drafts/desligamento_rpc_rollback.sql
-- Record definitions for byte-for-byte comparison after rollback.
CREATE TABLE public.test_rpc_snapshot AS
 SELECT p.proname,md5(pg_get_functiondef(p.oid)) signature
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('ro_can_view_internal_document','ro_custos_operacionais_visiveis',
 'ro_listar_minhas_notificacoes','ro_nomes_colaboradores_solicitacoes',
 'ro_relatorio_centros_custo','ro_solicitacao_foi_comprada','ro_ultimo_pix_viajante');
