-- RASCUNHO SQL - NAO EXECUTAR NO BANCO DE PRODUCAO
-- Dependencia: folga-campo-01-estruturas-RASCUNHO.sql
-- Funcao interna para ser chamada NA MESMA TRANSACAO da RPC de criacao.
-- Nao chamar isoladamente: sua execucao isolada mudaria o historico interno
-- sem criar a solicitacao. Nenhuma tabela do sistema oficial de alocacao e escrita.
create or replace function ro_private.preparar_episodio_folga(
  p_funcionario_id uuid,
  p_obra_id uuid,
  p_distancia_declarada_km integer,
  p_confirma_retorno boolean,
  p_colaborador_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_novo_id uuid;
  v_km integer;
  v_faixa text;
  v_intervalo integer;
  v_transporte text;
  v_acao text;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if pg_catalog.num_nonnulls(p_funcionario_id,p_colaborador_id)<>1
     or p_obra_id is null then
    raise exception 'IDENTIDADE_CC_OBRIGATORIOS';
  end if;
  -- A RPC chamadora deve confirmar autorizacao para criar em nome do funcionario.
  -- Este lock deve ser compartilhado com a validacao de ciclo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(coalesce(p_funcionario_id::text,'privado:'||p_colaborador_id::text), 904)
  );
  select * into v_atual
  from public.ro_folga_alocacoes
  where funcionario_id is not distinct from p_funcionario_id
    and colaborador_id is not distinct from p_colaborador_id and encerrada_em is null
  for update;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    if p_distancia_declarada_km is not null
       and p_distancia_declarada_km <> v_atual.distancia_km then
      raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
    end if;
    v_km:=v_atual.distancia_km;
    v_novo_id:=v_atual.id;
    v_acao:=null;
  else
    select * into v_anterior
    from public.ro_folga_alocacoes
    where funcionario_id is not distinct from p_funcionario_id
      and colaborador_id is not distinct from p_colaborador_id and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;

    if v_anterior.id is not null then
      if p_confirma_retorno is distinct from true then
        raise exception 'CONFIRMACAO_RETORNO_OBRIGATORIA';
      end if;
      if p_distancia_declarada_km is not null
         and p_distancia_declarada_km <> v_anterior.distancia_km then
        raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
      end if;
      v_km:=v_anterior.distancia_km;
      v_acao:='confirmacao';
    else
      if p_distancia_declarada_km is null or p_distancia_declarada_km < 0 then
        raise exception 'DISTANCIA_OBRIGATORIA_OU_INVALIDA';
      end if;
      v_km:=p_distancia_declarada_km;
      v_acao:='declaracao';
    end if;

    if v_atual.id is not null then
      update public.ro_folga_alocacoes
      set encerrada_em=pg_catalog.now()
      where id=v_atual.id;
    end if;
    insert into public.ro_folga_alocacoes(
      funcionario_id,colaborador_id,obra_id,distancia_km,confirmada_em,confirmada_por,origem_alocacao_id
    ) values (
      p_funcionario_id,p_colaborador_id,p_obra_id,v_km,pg_catalog.now(),auth.uid(),v_anterior.id
    ) returning id into v_novo_id;
    insert into public.ro_folga_distancia_auditoria(
      alocacao_id,distancia_anterior_km,distancia_nova_km,
      acao,realizado_por
    ) values (
      v_novo_id,v_anterior.distancia_km,v_km,v_acao,auth.uid()
    );
  end if;

  select faixa,intervalo_dias,transporte
  into v_faixa,v_intervalo,v_transporte
  from ro_private.regime_folga_km(v_km);

  return pg_catalog.jsonb_build_object(
    'alocacao_id',v_novo_id,'obra_id',p_obra_id,
    'funcionario_id',p_funcionario_id,'colaborador_id',p_colaborador_id,
    'distancia_km',v_km,'regime_faixa',v_faixa,
    'intervalo_dias',v_intervalo,'transporte',v_transporte
  );
end;
$$;
revoke all on function ro_private.preparar_episodio_folga(uuid,uuid,integer,boolean,uuid)
  from public,anon,authenticated;

-- INTEGRACAO AINDA NAO PRONTA:
-- A RPC publica de criacao deve executar preparar_episodio_folga e a
-- ro_criar_solicitacao_com_aprovador na MESMA transacao, apos validar permissao.
-- O trigger ro_validar_ciclo_folga_campo precisa ser atualizado para calcular
-- pela distancia do episodio e pela ultima data_ida aprovada+finalizada.
-- O snapshot devera ser escrito na solicitacao de forma protegida.
-- Nao conceder acesso a esta funcao privada ate completar e testar o fluxo.
