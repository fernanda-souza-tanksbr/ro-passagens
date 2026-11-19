import test from "node:test";
import assert from "node:assert/strict";
import { passageiroElegivelViagemAdministrativa, motivoAdministrativoPermitido } from "../src/viagemAdministrativaEligibility.ts";
import { motivoPossuiRetorno, normalizarCamposRetorno } from "../src/retornoRules.ts";

test("passageiro operacional não pode utilizar viagem administrativa", () => {
  const comum = { id: "a", funcionario_id: "a", nome: "Obra", visivel_obras_control: true, visivel_passagens: true, escopo_passagens: "comum" };
  assert.equal(passageiroElegivelViagemAdministrativa(comum), false);
  assert.equal(motivoAdministrativoPermitido("viagem_administrativa", comum), false);
  assert.equal(motivoAdministrativoPermitido("folga_campo", comum), true);
});

test("passageiro restrito ou privado sem vínculo operacional é elegível", () => {
  const restrito = { id: "a", funcionario_id: "a", nome: "Interno", visivel_obras_control: false, visivel_passagens: true, escopo_passagens: "restrito_ro" };
  const privado = { id: "b", funcionario_id: null, nome: "Escritório", visivel_obras_control: false, visivel_passagens: true, escopo_passagens: "restrito_ro" };
  assert.equal(passageiroElegivelViagemAdministrativa(restrito), true);
  assert.equal(passageiroElegivelViagemAdministrativa(privado), true);
  assert.equal(passageiroElegivelViagemAdministrativa({ ...privado, funcionario_id: "c", visivel_obras_control: true }), false);
});

test("viagem administrativa admite retorno opcional", () => {
  assert.equal(motivoPossuiRetorno("viagem_administrativa"), true);
  const base = { motivo: "viagem_administrativa" as const, data_retorno: "", destino_retorno: "", centro_custo_retorno_id: "", retorno_indefinido: false };
  assert.deepEqual(normalizarCamposRetorno(base), base);
  assert.equal(normalizarCamposRetorno({ ...base, data_retorno: "2026-12-01", destino_retorno: "Campinas", retorno_indefinido: false }).destino_retorno, "Campinas");
});
