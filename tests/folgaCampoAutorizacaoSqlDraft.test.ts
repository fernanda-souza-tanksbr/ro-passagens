import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const consulta = readFileSync("docs/sql/folga-campo-12-consulta-contexto-RASCUNHO.sql","utf8");
const criacao = readFileSync("docs/sql/folga-campo-09-rpc-criacao-coordenada-RASCUNHO.sql","utf8");
const estruturas = readFileSync("docs/sql/folga-campo-01-estruturas-RASCUNHO.sql","utf8");

test("consulta exige usuario e valida funcionario antes de ler distancia e historico",()=>{
  assert.match(consulta,/auth\.uid\(\) is null[\s\S]*IDENTIDADE_CC_OBRIGATORIOS/);
  const autorizacao = consulta.indexOf("ro_funcionario_disponivel_para_usuario(");
  const primeiraLeitura = consulta.indexOf("select * into v_atual from public.ro_folga_alocacoes");
  assert.ok(autorizacao>=0 && autorizacao<primeiraLeitura);
});

test("consulta e criacao aplicam a mesma visibilidade de CC do catalogo oficial",()=>{
  for(const sql of [consulta,criacao]){
    assert.match(sql,/ro_catalogo_centros_custo\(\)/);
    assert.match(sql,/ro_funcionario_disponivel_para_usuario\(auth\.uid\(\),/);
  }
});

test("consulta nao abre EXECUTE a anon ou authenticated",()=>{
  assert.match(consulta,/revoke all on function public\.ro_consultar_contexto_distancia_folga\(uuid,uuid,uuid\)[\s\S]*from public,anon,authenticated/);
  assert.doesNotMatch(consulta,/grant\s+execute\s+on\s+function/i);
});

test("estruturas de km possuem RLS e acessos de tabelas revogados",()=>{
  assert.match(estruturas,/alter table public\.ro_folga_alocacoes enable row level security/);
  assert.match(estruturas,/alter table public\.ro_folga_distancia_auditoria enable row level security/);
  assert.match(estruturas,/revoke all on public\.ro_folga_alocacoes from anon,authenticated/);
  assert.match(estruturas,/revoke all on public\.ro_folga_distancia_auditoria from anon,authenticated/);
});
