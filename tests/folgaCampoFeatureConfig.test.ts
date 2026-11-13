import assert from "node:assert/strict";
import test from "node:test";
import { fluxoFolgaDistanciaHabilitado } from "../src/folgaCampoFeatureConfig.ts";

test("C2 fica desligada sem autorizacao explicita de build", () => {
  for (const valor of [undefined,null,false,true,"","true","1","C2_PREVIEW","c2_producao_aprovada"]) {
    assert.equal(fluxoFolgaDistanciaHabilitado(valor),false);
  }
});
test("C2 so habilita com o token publico exato de liberacao",()=>{
  assert.equal(fluxoFolgaDistanciaHabilitado("C2_PRODUCAO_APROVADA"),true);
});
