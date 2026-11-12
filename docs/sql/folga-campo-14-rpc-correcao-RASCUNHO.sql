-- RASCUNHO 14: RPC PUBLICA CONTROLADA PARA CORRECAO DE KM.
-- DEPENDE de 01 (estruturas) e 03 (autorizacao e correcao privada).
-- NAO EXECUTAR EM PRODUCAO. Sem GRANT para usuarios nesta etapa.
create or replace function public.ro_corrigir_distancia_folga(
  p_alocacao_id uuid,
  p_nova_distancia_km integer,
  p_justificativa text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;
  -- A funcao privada exige coordenador/gerente ou RO ativo globalmente,
  -- justificativa e lock por funcionario; nunca toca snapshots historicos.
  return ro_private.corrigir_distancia_folga(
    p_alocacao_id,p_nova_distancia_km,p_justificativa
  );
end;
$$;
revoke all on function public.ro_corrigir_distancia_folga(uuid,integer,text)
from public,anon,authenticated;

-- A liberacao futura da RPC depende de homologacao de permissoes e auditoria,
-- inclusive perfis sem acesso, RO inativo e usuario sem autenticacao.
