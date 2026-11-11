-- RASCUNHO: NAO EXECUTAR EM PRODUCAO.
-- Depende de folga-campo-01-estruturas-RASCUNHO.sql.
-- Revisar grants, identificacao de usuario ativo, trigger de protecao de snapshot,
-- e autorizacao de escrita antes de disponibilizar qualquer RPC.

-- Funcao de autorizacao interna; nao conceder EXECUTE a anon/authenticated.
create or replace function ro_private.pode_corrigir_distancia_folga(p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select p_user is not null and (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = p_user and ur.role::text in ('coordenador','gerente')
    )
    or public.ro_is_operador_ativo(p_user)
  );
$$;
revoke all on function ro_private.pode_corrigir_distancia_folga(uuid) from public,anon,authenticated;

-- Correcao atomica apenas do episodio vigente.
-- SECURITY DEFINER exige auditoria e verificacao de permissoes; manter em schema privado.
create or replace function ro_private.corrigir_distancia_folga(
  p_alocacao_id uuid,
  p_nova_distancia_km integer,
  p_justificativa text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_user uuid := auth.uid();
  v_funcionario_id uuid;
begin
  if v_user is null or not ro_private.pode_corrigir_distancia_folga(v_user) then
    raise exception 'CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA';
  end if;
  if p_nova_distancia_km is null or p_nova_distancia_km < 0 then
    raise exception 'DISTANCIA_INVALIDA';
  end if;
  if length(btrim(coalesce(p_justificativa,''))) < 10 then
    raise exception 'JUSTIFICATIVA_CORRECAO_OBRIGATORIA';
  end if;
  -- Compartilha o advisory lock da criacao para serializar correcao e
  -- transferencia de CC do mesmo funcionario.
  select funcionario_id into v_funcionario_id
  from public.ro_folga_alocacoes where id=p_alocacao_id;
  if v_funcionario_id is null then raise exception 'ALOCACAO_ATIVA_NAO_ENCONTRADA'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_funcionario_id::text,904)
  );
  select * into v_atual
    from public.ro_folga_alocacoes
    where id = p_alocacao_id and encerrada_em is null
    for update;
  if not found then raise exception 'ALOCACAO_ATIVA_NAO_ENCONTRADA'; end if;
  if v_atual.distancia_km = p_nova_distancia_km then
    raise exception 'DISTANCIA_SEM_ALTERACAO';
  end if;

  update public.ro_folga_alocacoes
     set distancia_km = p_nova_distancia_km,
         confirmada_por = v_user,
         confirmada_em = now()
   where id = p_alocacao_id;

  insert into public.ro_folga_distancia_auditoria(
    alocacao_id, distancia_anterior_km, distancia_nova_km,
    acao, realizado_por, justificativa
  ) values (
    p_alocacao_id, v_atual.distancia_km, p_nova_distancia_km,
    'correcao', v_user, btrim(p_justificativa)
  );

  -- Nunca atualizar snapshots em ro_passagem_solicitacoes.
  return jsonb_build_object(
    'alocacao_id',p_alocacao_id,
    'distancia_anterior_km',v_atual.distancia_km,
    'distancia_nova_km',p_nova_distancia_km
  );
end;
$$;
revoke all on function ro_private.corrigir_distancia_folga(uuid,integer,text) from public,anon,authenticated;

-- PROXIMOS PASSOS ANTES DE USAR:
-- 1. Expor somente uma RPC publica de entrada, com auth.uid() e grants explicitos.
-- 2. Validar status de usuario ativo para coordenador/gerente.
-- 3. Integrar criacao atomica de episodio com ro_criar_solicitacao_com_aprovador
--    sem reescrever cadeia de aprovacao; garantir lock por funcionario.
-- 4. Proteger snapshots de alteracao direta e testar permissao com JWT real.
-- 5. Testar falha transacional e concorrencia. Nao executar este arquivo isoladamente.
