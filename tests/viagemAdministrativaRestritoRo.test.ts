import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../supabase/migrations/20261127160000_permite_viagem_administrativa_restrito_ro.sql", import.meta.url),
  "utf8",
);

test("permite apenas funcionarios restritos nao operacionais, ativos e visiveis no RO", () => {
  assert.match(migration, /f\.escopo_passagens = 'restrito_ro'/);
  assert.match(migration, /f\.visivel_obras_control is false/);
  assert.match(migration, /f\.visivel_passagens is true/);
  assert.match(migration, /f\.ativo is true/);
  assert.match(migration, /f\.deleted_at is null/);
  assert.match(migration, /if new\.colaborador_id is null then/);
  assert.match(migration, /new\.funcionario_id is null/);
  assert.match(migration, /new\.viajante_nome_informado is not null/);
});

test("preserva demais verificacoes e falha se a funcao instalada divergir", () => {
  assert.match(migration, /v_def :=|INTO v_def/);
  assert.match(migration, /REGRA_VIAGEM_ADMINISTRATIVA_DIVERGENTE/);
  assert.match(migration, /VIAGEM_ADMINISTRATIVA_VINCULO_DIVERGENTE/);
  assert.match(migration, /VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL/);
  assert.match(migration, /VALIDACAO_RETORNO_AUSENTE/);
  assert.match(migration, /EXECUTE replace\(v_def, v_old, v_new\)/);
  assert.doesNotMatch(migration, /\bdisable trigger\b/i);
  assert.doesNotMatch(migration, /\binsert into\b/i);
  assert.doesNotMatch(migration, /\bupdate public\.funcionarios\b/i);
});
