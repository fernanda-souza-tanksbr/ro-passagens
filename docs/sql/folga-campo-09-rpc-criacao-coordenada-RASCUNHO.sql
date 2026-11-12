-- RASCUNHO 09: RPC de criacao coordenada (NAO EXECUTAR ISOLADAMENTE).
-- Depende das estruturas 01, episodio 04, contexto 08 e trigger coordenado
-- que consome ro_private.folga_criacao_contexto ANTES DO INSERT.
-- O trigger coordenado AINDA NAO FOI IMPLEMENTADO.
-- Nao conceder EXECUTE enquanto nao houver trigger e testes de seguranca.
--
-- O PostgreSQL executa toda a chamada de funcao numa unica transacao.
-- Qualquer RAISE EXCEPTION desfaz episodio, auditoria e solicitacao.
create or replace function public.ro_criar_folga_campo_com_distancia(
  p_solicitacao jsonb,
  p_documentos jsonb default '[]'::jsonb,
  p_distancia_declarada_km integer default null,
  p_confirma_retorno boolean default false
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_criado uuid;
  v_funcionario uuid;
  v_obra uuid;
  v_episodio jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  if p_solicitacao is null or pg_catalog.jsonb_typeof(p_solicitacao) <> 'object'
     or p_solicitacao->>'motivo' is distinct from 'folga_campo' then
    raise exception 'MOTIVO_FOLGA_CAMPO_OBRIGATORIO';
  end if;
  if p_solicitacao->>'colaborador_id' is not null
     or p_solicitacao->>'viajante_nome_informado' is not null then
    raise exception 'VIAJANTE_NAO_SUPORTADO_NESTA_ETAPA';
  end if;
  begin
    v_id := (p_solicitacao->>'id')::uuid;
    v_funcionario := (p_solicitacao->>'funcionario_id')::uuid;
    v_obra := (p_solicitacao->>'obra_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'IDENTIFICADOR_INVALIDO';
  end;
  if v_id is null or v_funcionario is null or v_obra is null then
    raise exception 'IDENTIFICADORES_OBRIGATORIOS';
  end if;
  -- Validacao previa equivalente aos filtros canonicos do trigger
  -- ro_validar_solicitacao_visibilidade. A cadeia legada continua sendo
  -- executada e permanece autoridade final sobre todas as demais regras.
  if public.ro_funcionario_disponivel_para_usuario(auth.uid(),v_funcionario) is distinct from true then
    raise exception 'FUNCIONARIO_INDISPONIVEL';
  end if;
  if not exists (
    select 1 from public.ro_catalogo_centros_custo() c
    where c.id=v_obra
  ) then
    raise exception 'CENTRO_CUSTO_INDISPONIVEL';
  end if;
  v_episodio := ro_private.preparar_episodio_folga(
    v_funcionario,v_obra,p_distancia_declarada_km,p_confirma_retorno
  );
  insert into ro_private.folga_criacao_contexto(
    solicitacao_id,funcionario_id,obra_id,alocacao_id,
    distancia_km,regime_faixa,intervalo_dias,criado_por
  ) values (
    v_id,v_funcionario,v_obra,
    (v_episodio->>'alocacao_id')::uuid,
    (v_episodio->>'distancia_km')::integer,
    v_episodio->>'regime_faixa',
    (v_episodio->>'intervalo_dias')::integer,
    auth.uid()
  );
  -- Preserva validacoes, aprovador, historico e notificacao existentes.
  v_criado := public.ro_criar_solicitacao_com_aprovador(
    p_solicitacao,p_documentos
  );
  if v_criado is distinct from v_id then
    raise exception 'ID_CRIACAO_DIVERGENTE';
  end if;
  -- O BEFORE INSERT deve ter preenchido os snapshots com base no contexto.
  if not exists (
    select 1 from public.ro_passagem_solicitacoes s
    where s.id=v_id
      and s.funcionario_id=v_funcionario and s.obra_id=v_obra
      and s.folga_alocacao_id=(v_episodio->>'alocacao_id')::uuid
      and s.folga_distancia_km=(v_episodio->>'distancia_km')::integer
      and s.folga_intervalo_dias=(v_episodio->>'intervalo_dias')::integer
  ) then
    raise exception 'SNAPSHOT_FOLGA_NAO_APLICADO';
  end if;
  delete from ro_private.folga_criacao_contexto
  where solicitacao_id=v_id and criado_por=auth.uid();
  return v_id;
end;
$$;
revoke all on function public.ro_criar_folga_campo_com_distancia(
  jsonb,jsonb,integer,boolean
) from public,anon,authenticated;

-- ATENCAO: a RPC acima NAO esta pronta para publicacao.
-- O trigger deve validar contexto privado e proteger contra escrita direta
-- de snapshots por chamadas legadas. Os grants devem ser concedidos somente
-- apos testes transacionais, aprovacao e backup.
-- Verificar que o caminho legado conserva criacao sem distancia.
