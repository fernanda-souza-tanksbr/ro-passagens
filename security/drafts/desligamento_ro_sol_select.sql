-- DRAFT ONLY - DO NOT APPLY TO PRODUCTION
-- Confidentiality: desligamento. Requires isolated integration tests and review of dependent policies/RPCs.
-- Original production ro_sol_select USING:
-- ro_is_active_internal_user() AND
-- (excluida_em IS NULL OR (excluida_em IS NOT NULL AND ro_can_operate()))
--
-- This policy is NOT a complete security fix by itself.
-- Review and patch related child-table policies, SECURITY DEFINER RPCs, storage and reports first.
BEGIN;
ALTER POLICY ro_sol_select ON public.ro_passagem_solicitacoes
USING (
  public.ro_is_active_internal_user()
  AND (excluida_em IS NULL OR public.ro_can_operate())
  AND (
    motivo IS DISTINCT FROM 'desligamento'
    OR solicitante_id = (select auth.uid())
    OR public.ro_can_operate()
  )
);
COMMIT;
--
-- ROLLBACK (requires separate controlled execution, NOT automatically run):
-- ALTER POLICY ro_sol_select ON public.ro_passagem_solicitacoes
-- USING (public.ro_is_active_internal_user() AND
--   (excluida_em IS NULL OR (excluida_em IS NOT NULL AND public.ro_can_operate())));
