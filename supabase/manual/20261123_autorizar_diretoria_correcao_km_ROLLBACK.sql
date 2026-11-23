-- Rollback exclusivo da autorização de Diretoria (se necessário).
-- Não desfaz correções já auditadas nem modifica snapshots.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
DECLARE v_def text;
BEGIN
  IF to_regprocedure('ro_private.pode_corrigir_distancia_folga(uuid)') IS NULL THEN
    RAISE EXCEPTION 'KM_DIRETORIA_ROLLBACK_FUNCAO_AUSENTE';
  END IF;
  SELECT pg_get_functiondef('ro_private.pode_corrigir_distancia_folga(uuid)'::regprocedure)
    INTO v_def;
  IF v_def NOT LIKE '%''diretor''%' OR v_def NOT LIKE '%coordenador%'
     OR v_def NOT LIKE '%gerente%' OR v_def NOT LIKE '%ro_is_operador_ativo%' THEN
    RAISE EXCEPTION 'KM_DIRETORIA_ROLLBACK_DEFINICAO_DIVERGENTE';
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
          AND ur.role::text IN ('coordenador', 'gerente')
      )
      OR public.ro_is_operador_ativo(p_user)
    );
$func$;
REVOKE ALL ON FUNCTION ro_private.pode_corrigir_distancia_folga(uuid)
FROM PUBLIC, anon, authenticated;
COMMIT;
