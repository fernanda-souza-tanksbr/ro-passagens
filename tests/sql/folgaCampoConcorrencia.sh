#!/usr/bin/env bash
# PostgreSQL descartavel com dados ficticios. Nunca usar credenciais de producao.
set -euo pipefail

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

# Esperar explicitamente que a primeira conexao obtenha o lock.
# Ambas chamam a RPC integrada com o mesmo funcionario e CCs diferentes.
psql -X -v ON_ERROR_STOP=1 > "$tmpdir/primeira.log" 2>&1 <<'SQL' &
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
begin;
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('00000000-0000-0000-0000-000000000102',904)
);
\echo PRIMEIRO_LOCK_OBTIDO
select pg_catalog.pg_sleep(3);
select public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object(
  'id','00000000-0000-0000-0000-000000000501',
  'funcionario_id','00000000-0000-0000-0000-000000000102',
  'obra_id','00000000-0000-0000-0000-000000000201',
  'motivo','folga_campo','data_ida','2027-04-01',
  'aprovador_id','00000000-0000-0000-0000-000000000001'),
 '[]'::jsonb,200,false);
commit;
SQL
pid_primeira=$!

pronto=0
for i in $(seq 1 80); do
  if grep -q 'PRIMEIRO_LOCK_OBTIDO' "$tmpdir/primeira.log"; then pronto=1; break; fi
  if ! kill -0 "$pid_primeira" 2>/dev/null; then
    cat "$tmpdir/primeira.log"
    echo 'PRIMEIRA_CONEXAO_TERMINOU_ANTES_DO_LOCK' >&2
    exit 1
  fi
  sleep 0.1
done
if [ "$pronto" -ne 1 ]; then
  cat "$tmpdir/primeira.log"
  echo 'LOCK_INICIAL_NAO_CONFIRMADO' >&2
  exit 1
fi

# A segunda operacao deve aguardar o mesmo advisory lock.
psql -X -v ON_ERROR_STOP=1 > "$tmpdir/segunda.log" 2>&1 <<'SQL' &
select pg_catalog.set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $$
begin
  if pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('00000000-0000-0000-0000-000000000102',904)
  ) then
    raise exception 'SEGUNDA_CONEXAO_NAO_ENCONTROU_LOCK';
  end if;
end $$;
select public.ro_criar_folga_campo_com_distancia(
 jsonb_build_object(
  'id','00000000-0000-0000-0000-000000000502',
  'funcionario_id','00000000-0000-0000-0000-000000000102',
  'obra_id','00000000-0000-0000-0000-000000000202',
  'motivo','folga_campo','data_ida','2027-05-01',
  'aprovador_id','00000000-0000-0000-0000-000000000001'),
 '[]'::jsonb,601,false);
SQL
pid_segunda=$!

resultado=0
wait "$pid_primeira" || resultado=1
wait "$pid_segunda" || resultado=1
if [ "$resultado" -ne 0 ]; then
  echo 'PRIMEIRA CONEXAO'; cat "$tmpdir/primeira.log"
  echo 'SEGUNDA CONEXAO'; cat "$tmpdir/segunda.log"
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $$
declare v_ativos integer;v_episodios integer;v_pedidos integer;v_contextos integer;
begin
  select count(*) into v_ativos
    from public.ro_folga_alocacoes
    where funcionario_id='00000000-0000-0000-0000-000000000102'
      and encerrada_em is null;
  select count(*) into v_episodios
    from public.ro_folga_alocacoes
    where funcionario_id='00000000-0000-0000-0000-000000000102';
  select count(*) into v_pedidos
    from public.ro_passagem_solicitacoes
    where funcionario_id='00000000-0000-0000-0000-000000000102'
      and folga_alocacao_id is not null
      and folga_distancia_km in (200,601);
  select count(*) into v_contextos from ro_private.folga_criacao_contexto;
  if v_ativos<>1 or v_episodios<>2 or v_pedidos<>2 or v_contextos<>0 then
    raise exception 'CONCORRENCIA_INCONSISTENTE: ativos %, episodios %, pedidos %, contextos %',
      v_ativos,v_episodios,v_pedidos,v_contextos;
  end if;
  if not exists(
    select 1 from public.ro_folga_alocacoes a
    where a.funcionario_id='00000000-0000-0000-0000-000000000102'
      and a.obra_id='00000000-0000-0000-0000-000000000202'
      and a.distancia_km=601 and a.encerrada_em is null
  ) then
    raise exception 'ULTIMO_EPISODIO_ATIVO_INCORRETO';
  end if;
end $$;
select 'FOLGA_CONCORRENCIA_OK' as resultado;
SQL
