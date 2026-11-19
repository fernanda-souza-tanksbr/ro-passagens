import test from "node:test";
import assert from "node:assert/strict";
import { passageiroElegivelViagemAdministrativa, motivoAdministrativoPermitido } from "../src/viagemAdministrativaEligibility.ts";
import { erroRetornoAdministrativo, motivoPossuiRetorno, normalizarCamposRetorno } from "../src/retornoRules.ts";
import type { Funcionario } from "../src/types.ts";

const interno = { id: "privado-1", funcionario_id: null, nome: "Colaborador administrativo", visivel_obras_control: false, visivel_passagens: true, escopo_passagens: "restrito_ro" } satisfies Funcionario;
const obras = { id: "operacional-1", funcionario_id: "operacional-1", nome: "Técnico de segurança", visivel_obras_control: true, visivel_passagens: true, escopo_passagens: "comum" } satisfies Funcionario;

test("somente cadastro privado RO sem vínculo operacional pode ser selecionado", () => {
  assert.equal(passageiroElegivelViagemAdministrativa(interno), true);
  assert.equal(passageiroElegivelViagemAdministrativa({ ...interno, visivel_passagens: undefined, escopo_passagens: undefined }), true, "a origem privada prevalece sobre flags auxiliares");
  assert.equal(passageiroElegivelViagemAdministrativa(obras), false);
  assert.equal(passageiroElegivelViagemAdministrativa({ ...obras, visivel_obras_control: false, escopo_passagens: "restrito_ro" }), false, "registro em funcionarios continua não elegível");
  assert.equal(passageiroElegivelViagemAdministrativa({ ...interno, funcionario_id: "operacional-1", visivel_obras_control: true }), false);
  assert.equal(passageiroElegivelViagemAdministrativa({ ...interno, funcionario_id: "restrito-1", visivel_obras_control: false }), true);
  assert.equal(passageiroElegivelViagemAdministrativa(null), false);
  assert.equal(motivoAdministrativoPermitido("viagem_administrativa", obras), false);
  assert.equal(motivoAdministrativoPermitido("viagem_administrativa", interno), true);
  assert.equal(motivoAdministrativoPermitido("folga_campo", obras), true, "Folga de Campo não é alterada");
});

test("retorno da Viagem Administrativa é opcional sem introduzir campos obrigatórios", () => {
  assert.equal(motivoPossuiRetorno("viagem_administrativa"), true);
  const ida = { motivo: "viagem_administrativa" as const, data_retorno: "", destino_retorno: "", centro_custo_retorno_id: "", retorno_indefinido: false };
  assert.deepEqual(normalizarCamposRetorno(ida), ida);
  const idaEVolta = { ...ida, data_retorno: "2026-12-10", destino_retorno: "Campinas / SP", centro_custo_retorno_id: "obra-1" };
  assert.deepEqual(normalizarCamposRetorno(idaEVolta), idaEVolta);
  assert.deepEqual(normalizarCamposRetorno({ ...idaEVolta, retorno_indefinido: true }), { ...idaEVolta, retorno_indefinido: true, destino_retorno: "", centro_custo_retorno_id: "" });
});

test("motivos existentes permanecem intactos", () => {
  for (const motivo of ["ferias", "folga_campo", "recesso"] as const) assert.equal(motivoPossuiRetorno(motivo), true);
  assert.equal(motivoPossuiRetorno("desligamento"), false);
});

test("retorno anterior à ida e trecho sem data são rejeitados", () => {
  assert.equal(erroRetornoAdministrativo("viagem_administrativa", "2026-12-12", "2026-12-11", "", ""), "A data de retorno não pode ser anterior à data de ida.");
  assert.match(erroRetornoAdministrativo("viagem_administrativa", "2026-12-12", "", "São Paulo / SP", "") || "", /data de retorno/);
  assert.match(erroRetornoAdministrativo("viagem_administrativa", "2026-12-12", "", "", "obra") || "", /data de retorno/);
  assert.equal(erroRetornoAdministrativo("viagem_administrativa", "2026-12-12", "", "", ""), null);
  assert.equal(erroRetornoAdministrativo("viagem_administrativa", "2026-12-12", "2026-12-12", "São Paulo / SP", "obra"), null);
  assert.equal(erroRetornoAdministrativo("ferias", "2026-12-12", "", "Recife", ""), null);
});
