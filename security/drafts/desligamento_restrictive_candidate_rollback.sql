-- ROLLBACK FOR security/drafts/desligamento_restrictive_candidate.sql ONLY.
-- NOT rollback for any complete future migration. NOT EXECUTED.
begin;
set local lock_timeout='3s';
drop policy if exists ro_desligamento_guard_select on public.ro_passagem_solicitacoes;
drop policy if exists ro_desligamento_guard_cost on public.ro_passagem_custos;
drop policy if exists ro_desligamento_guard_history on public.ro_passagem_historico;
drop policy if exists ro_desligamento_guard_notification on public.ro_passagem_notificacoes;
drop policy if exists ro_desligamento_guard_audit on public.ro_auditoria_interna;
drop policy if exists ro_desligamento_guard_docs on public.ro_passagem_documentos_internos;
drop policy if exists ro_desligamento_guard_attachments on public.ro_passagem_anexos;
drop policy if exists ro_desligamento_guard_resolution on public.ro_resolucao_operacional;
drop function if exists public.ro_desligamento_read_allowed(uuid);
commit;
