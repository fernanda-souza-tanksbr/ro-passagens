-- Portal TanksBR — correção mínima e auditável do acesso da Diretoria à edição de KM.
-- Preparar e validar; executar em produção somente após autorização supervisionada.
-- Não modifica alocações, histórico, solicitações, RLS nem outros perfis.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $guard$
DECLARE
  v_def text;
BEGIN
  IF to_regprocedure('ro_private.pode_corrigir_distancia_folga(uuid)') IS NULL THEN
    RAISE EXCEPTION 'KM_DIRETORIA_FUNCAO_AUSENTE';
  END IF;
  SELECT pg_get_functiondef('ro_private.pode_corrigir_distancia_folga(uuid)'::regprocedure) INTO v_def;
  IF v_def IS NULL
     OR v_def NOT ILIKE '%SECURITY DEFINER%'
     OR v_def NOT LIKE '%auth.users%'
     OR v_def NOT LIKE '%user_roles%'
     OR v_def NOT LIKE '%ro_is_operador_ativo%'
     OR v_def NOT LIKE '%coordenador%'
     OR v_def NOT LIKE '%gerente%'
     OR v_def LIKE '%''diretor''%' THEN
    RAISE EXCEPTION 'KM_DIRETORIA_DEFINICAO_DIVERGENTE: revisar função atual sem sobrescrever';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION ro_private.pode_corrigir_distancia_folga(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $func$
  SELECT p_user IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = p_user
        AND u.deleted_at IS NULL
        AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
    )
    AND (
      EXISTS (
        SELECT 1 FROM public.user_roles ur
        WHERE ur.user_id = p_user
          AND ur.role::text IN ('coordenador', 'gerente', 'diretor')
      )
      OR public.ro_is_operador_ativo(p_user)
    );
$func$;

REVOKE ALL ON FUNCTION ro_private.pode_corrigir_distancia_folga(uuid)
FROM PUBLIC, anon, authenticated;

DO $confirm$
BEGIN
  IF pg_get_functiondef('ro_private.pode_corrigir_distancia_folga(uuid)'::regprocedure)
        NOT LIKE '%''diretor''%' THEN
    RAISE EXCEPTION 'KM_DIRETORIA_NAO_INSTALADO';
  END IF;
END;
$confirm$;
COMMIT;

-- Verificação não invasiva:
SELECT
  to_regprocedure('ro_private.pode_corrigir_distancia_folga(uuid)') IS NOT NULL AS funcao_existe,
  pg_get_functiondef('ro_private.pode_corrigir_distancia_folga(uuid)'::regprocedure)
    LIKE '%''diretor''%' AS papel_diretor_incluido,
  NOT has_function_privilege('anon', 'ro_private.pode_corrigir_distancia_folga(uuid)', 'EXECUTE')
    AS anon_sem_execucao,
  NOT has_function_privilege('authenticated', 'ro_private.pode_corrigir_distancia_folga(uuid)', 'EXECUTE')
    AS authenticated_sem_execucao_direta;
