-- RASCUNHO 12 - CONSULTA SEGURA DE CONTEXTO DE FOLGA
-- NAO EXECUTAR EM PRODUCAO. Requer estruturas do arquivo 01.
-- O acesso precisa ser equivalente ao acesso a criacao de solicitacao.
-- IMPORTANTE: validar politicas de acesso por funcionario antes de conceder EXECUTE.
create or replace function public.ro_consultar_contexto_distancia_folga(
  p_funcionario_id uuid,
  p_obra_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_km integer;
  v_estado text;
  v_ultima date;
  v_futura uuid;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if p_funcionario_id is null or p_obra_id is null then
    raise exception 'FUNCIONARIO_CC_OBRIGATORIOS';
  end if;
  -- BLOQUEADOR DE SEGURANCA: inserir validacao de autorizacao para
  -- consultar o funcionario, equivalente ao fluxo atual do RO Passagens.
  -- Sem esta verificacao, NAO conceder EXECUTE a authenticated.
  select * into v_atual from public.ro_folga_alocacoes
  where funcionario_id=p_funcionario_id and encerrada_em is null
  order by iniciada_em desc limit 1;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    v_estado:='reutilizar';v_km:=v_atual.distancia_km;
  else
    select * into v_anterior from public.ro_folga_alocacoes
    where funcionario_id=p_funcionario_id and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;
    if v_anterior.id is not null then
      v_estado:='confirmar';v_km:=v_anterior.distancia_km;
    else
      v_estado:='informar';v_km:=null;
    end if;
  end if;

  select s.data_ida into v_ultima
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id and s.motivo='folga_campo'
    and s.status='finalizada'
    and s.aprovacao_status in ('aprovada','dispensada')
    and s.data_ida <= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
  order by s.data_ida desc,s.id desc limit 1;

  v_futura:=public.ro_funcionario_possui_folga_futura_ativa(p_funcionario_id,null);
  return pg_catalog.jsonb_build_object(
    'funcionario_id',p_funcionario_id,'obra_id',p_obra_id,
    'distancia_km',v_km,'retorno_ao_cc',v_estado='confirmar',
    'estado',v_estado,'ultima_folga_data_ida',v_ultima,
    'proxima_folga_prevista',case when v_km is not null and v_ultima is not null
      then v_ultima+(select intervalo_dias from ro_private.regime_folga_km(v_km))
      else null end,
    'solicitacao_futura_existente_id',v_futura
  );
end;
$$;
revoke all on function public.ro_consultar_contexto_distancia_folga(uuid,uuid)
  from public,anon,authenticated;

-- ATENCAO: antes de habilitar, implementar autorizacao por funcionario,
-- testar que colaboradores privados nao vazem dados e confirmar grants.
