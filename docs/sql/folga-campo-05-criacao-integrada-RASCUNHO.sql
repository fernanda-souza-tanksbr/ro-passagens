-- RASCUNHO NAO EXECUTAR EM PRODUCAO
-- Funcao de entrada futura para a nova Folga de Campo.
-- Dependencias: etapas 01 e 04 e trigger de ciclo atualizado na MESMA migracao.
-- O wrapper usa a RPC existente para preservar aprovacao, historico e notificacoes.
-- A transacao da chamada PostgreSQL reverte episodio se a criacao falhar.
-- IMPORTANTE: o contexto auth.uid() e a permissao de solicitar em nome de outro
-- funcionario devem ser validados pela cadeia existente; revisar todos os seus caminhos.
create or replace function public.ro_criar_folga_campo_com_distancia(
  p_solicitacao jsonb,
  p_documentos jsonb default '[]'::jsonb,
  p_distancia_declarada_km integer default null,
  p_confirma_retorno boolean default false
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_funcionario uuid;
  v_obra uuid;
  v_episodio jsonb;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  if p_solicitacao is null or p_solicitacao->>'motivo' <> 'folga_campo' then
    raise exception 'MOTIVO_FOLGA_CAMPO_OBRIGATORIO';
  end if;
  v_funcionario := nullif(p_solicitacao->>'funcionario_id','')::uuid;
  v_obra := nullif(p_solicitacao->>'obra_id','')::uuid;
  if v_funcionario is null or v_obra is null then
    raise exception 'FUNCIONARIO_CC_OBRIGATORIOS';
  end if;
  -- Nao confiar em snapshot enviado pelo cliente.
  -- A RPC existente continua validando solicitante, documentos e aprovador.
  v_episodio := ro_private.preparar_episodio_folga(
    v_funcionario,v_obra,p_distancia_declarada_km,p_confirma_retorno
  );
  -- Exige que a trigger de ciclo ja leia o episodio/snapshot desta transacao.
  -- Nao liberar esta funcao antes da migracao coordenada.
  v_id := public.ro_criar_solicitacao_com_aprovador(
    p_solicitacao
      - 'folga_alocacao_id'
      - 'folga_distancia_km'
      - 'folga_regime_faixa'
      - 'folga_intervalo_dias',
    p_documentos
  );
  update public.ro_passagem_solicitacoes
  set folga_alocacao_id=(v_episodio->>'alocacao_id')::uuid,
      folga_distancia_km=(v_episodio->>'distancia_km')::integer,
      folga_regime_faixa=v_episodio->>'regime_faixa',
      folga_intervalo_dias=(v_episodio->>'intervalo_dias')::integer
  where id=v_id
    and motivo='folga_campo'
    and funcionario_id=v_funcionario
    and obra_id=v_obra;
  if not found then
    raise exception 'SNAPSHOT_FOLGA_NAO_APLICADO';
  end if;
  return v_id;
end;
$$;
-- Bloquear execucao por usuarios ate finalizar a revisao de autorizacao.
revoke all on function public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)
  from public,anon,authenticated;

-- PENDENCIAS BLOQUEANTES:
-- 1. Corrigir ordem do snapshot: o trigger BEFORE INSERT deve ter acesso ao km
--    na mesma transacao, e o AFTER INSERT de auditoria deve registrar snapshot.
--    O UPDATE acima e apenas esqueleto; nao garante essa ordem.
-- 2. Revisar se a cadeia de criacao permite que o solicitante represente o
--    funcionario informado; nao criar episodio antes dessa verificacao.
-- 3. Ajustar trigger de ciclo para evitar recalculo em UPDATE de status.
-- 4. Garantir que o contexto de episodio nao seja manipulado por RPC externa.
-- 5. Definir grants/RLS e testes com papeis reais em ambiente isolado.
-- 6. Nao aplicar isoladamente nem ativar a rota do frontend.
