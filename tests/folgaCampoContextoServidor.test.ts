import test from "node:test";
import assert from "node:assert/strict";
import { validarContextoDistancia } from "../src/folgaCampoContextoServidor.ts";

const base = {
  funcionario_id: "f1", obra_id: "cc1", distancia_km: 250,
  retorno_ao_cc: false, estado: "reutilizar",
  ultima_folga_data_ida: "2026-10-01",
  proxima_folga_prevista: "2026-10-15",
  solicitacao_futura_existente_id: null,
};

test("reutiliza km validado do CC consultado", () => {
  assert.equal(validarContextoDistancia(base,"f1","cc1").distancia_km,250);
});
test("rejeita resposta atrasada de outro CC", () => {
  assert.throws(() => validarContextoDistancia(base,"f1","cc2"), /CONTEXTO_DESATUALIZADO/);
});
test("primeira alocacao exige ausencia de km salvo", () => {
  assert.equal(validarContextoDistancia({...base,distancia_km:null,estado:"informar"},"f1","cc1").estado,"informar");
  assert.throws(() => validarContextoDistancia({...base,estado:"informar"},"f1","cc1"),/DISTANCIA_INCONSISTENTE/);
});
test("retorno exige confirmacao", () => {
  assert.equal(validarContextoDistancia({...base,estado:"confirmar",retorno_ao_cc:true},"f1","cc1").estado,"confirmar");
  assert.throws(() => validarContextoDistancia({...base,estado:"confirmar"},"f1","cc1"),/RETORNO_INCONSISTENTE/);
});
test("rejeita distancia negativa", () => {
  assert.throws(() => validarContextoDistancia({...base,distancia_km:-1},"f1","cc1"),/DISTANCIA_INVALIDA/);
});
test("rejeita dados incompletos", () => {
  assert.throws(() => validarContextoDistancia({funcionario_id:"f1"},"f1","cc1"));
});
