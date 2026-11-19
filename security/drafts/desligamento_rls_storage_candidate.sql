-- SECURITY CANDIDATE. DO NOT APPLY BEFORE RPC REVIEW AND TESTS.
-- PostgreSQL 17; designed against live policy names (read-only inspection 2026-11-19).
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE OR REPLACE FUNCTION public.ro_desligamento_autorizado(p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
 SELECT EXISTS(
   SELECT 1 FROM public.ro_passagem_solicitacoes s
   WHERE s.id=p_id AND (
     s.motivo IS DISTINCT FROM 'desligamento'
     OR (public.ro_is_active_internal_user()
       AND (s.solicitante_id=(SELECT auth.uid()) OR public.ro_can_operate()))
   )
 );
$$;
REVOKE ALL ON FUNCTION public.ro_desligamento_autorizado(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ro_desligamento_autorizado(uuid) TO authenticated;
-- Restrictive SELECT policies override every permissive SELECT or ALL policy.
CREATE POLICY ro_confidential_select ON public.ro_passagem_solicitacoes
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (motivo IS DISTINCT FROM 'desligamento' OR
   (public.ro_is_active_internal_user()
    AND (solicitante_id=(SELECT auth.uid()) OR public.ro_can_operate())));
CREATE POLICY ro_confidential_costs ON public.ro_passagem_custos
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_history ON public.ro_passagem_historico
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_notifications ON public.ro_passagem_notificacoes
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_docs ON public.ro_passagem_documentos_internos
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_attachments ON public.ro_passagem_anexos
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_audit ON public.ro_auditoria_interna
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (solicitacao_id IS NULL OR public.ro_desligamento_autorizado(solicitacao_id));
CREATE POLICY ro_confidential_resolution ON public.ro_resolucao_operacional
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (public.ro_desligamento_autorizado(solicitacao_id));
-- Guard all existing permissive storage SELECT policies for targeted buckets.
-- Internal documents: only rows registered in the document table are readable.
CREATE POLICY ro_confidential_storage ON storage.objects
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (
  bucket_id NOT IN ('ro-passagem-anexos','ro-documentos-internos')
  OR (
    bucket_id='ro-passagem-anexos'
    AND EXISTS (
      SELECT 1 FROM public.ro_passagem_solicitacoes s
      WHERE s.id::text=(storage.foldername(name))[1]
        AND public.ro_desligamento_autorizado(s.id)
    )
  )
  OR (
    bucket_id='ro-documentos-internos'
    AND EXISTS (
      SELECT 1 FROM public.ro_passagem_documentos_internos d
      WHERE d.storage_path=name
        AND public.ro_desligamento_autorizado(d.solicitacao_id)
    )
  )
 );
COMMIT;
-- NOT A COMPLETE MIGRATION: SECURITY DEFINER RPCs and indirect aggregates
-- still bypass RLS. Do not deploy until those are secured and tested.
