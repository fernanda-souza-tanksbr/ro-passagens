-- SECURITY HARDENING CANDIDATE - NOT APPROVED OR EXECUTED
-- Must be combined with SECURITY DEFINER fixes and isolated tests before deployment.
-- Restrictive SELECT policies combine by AND with all permissive policies, including FOR ALL.
begin;
set local lock_timeout = '3s';
create or replace function public.ro_desligamento_read_allowed(p_solicitacao uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists (
   select 1 from public.ro_passagem_solicitacoes s
   where s.id = p_solicitacao
     and (s.motivo is distinct from 'desligamento'
       or (public.ro_is_active_internal_user() and
           (s.solicitante_id = (select auth.uid()) or public.ro_can_operate())))
 );
$$;
revoke all on function public.ro_desligamento_read_allowed(uuid) from public, anon;
grant execute on function public.ro_desligamento_read_allowed(uuid) to authenticated;
create policy ro_desligamento_guard_select on public.ro_passagem_solicitacoes
as restrictive for select to authenticated
using (motivo is distinct from 'desligamento'
  or (public.ro_is_active_internal_user() and
      (solicitante_id = (select auth.uid()) or public.ro_can_operate())));
create policy ro_desligamento_guard_cost on public.ro_passagem_custos
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_history on public.ro_passagem_historico
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_notification on public.ro_passagem_notificacoes
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_audit on public.ro_auditoria_interna
as restrictive for select to authenticated
using (solicitacao_id is null or public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_docs on public.ro_passagem_documentos_internos
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_attachments on public.ro_passagem_anexos
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
create policy ro_desligamento_guard_resolution on public.ro_resolucao_operacional
as restrictive for select to authenticated
using (public.ro_desligamento_read_allowed(solicitacao_id));
commit;
-- CRITICAL: This is a partial candidate and NOT a complete deployment migration.
-- SECURITY DEFINER RPCs, storage policies, email logs, aggregate reports, and write paths
-- require coordinated fixes; do not deploy this file alone.
