import assert from "node:assert/strict";
import test from "node:test";
import { adicionarDiasIso, calcularCicloFolga, estadoQuilometragem, regimePorDistancia } from "../src/folgaCampoRegimes.ts";

test("limites de distancia e meios de transporte", () => {
  for (const [km, dias, transporte] of [[0,7,"onibus"],[200,7,"onibus"],[201,14,"onibus"],[600,14,"onibus"],[601,45,"onibus_ou_aviao"],[800,45,"onibus_ou_aviao"],[801,90,"onibus_ou_aviao"],[1500,90,"onibus_ou_aviao"],[1501,90,"aviao"]] as const) {
    assert.equal(regimePorDistancia(km).intervaloDias, dias);
    assert.equal(regimePorDistancia(km).transporte, transporte);
  }
});
test("distancia exige inteiro nao negativo", () => {
  for (const km of [-1,1.5,NaN,Infinity]) assert.throws(() => regimePorDistancia(km));
});
test("primeira folga nao e antecipada", () => {
  assert.equal(calcularCicloFolga([],450,"2026-11-09").antecipada,false);
});
test("ultima saida aprovada e finalizada ancora o ciclo", () => {
  const f = [{dataIda:"2026-11-01",status:"finalizada",aprovacaoStatus:"aprovada"},{dataIda:"2026-11-08",status:"finalizada",aprovacaoStatus:"aprovada"},{dataIda:"2026-11-09",status:"solicitada",aprovacaoStatus:"aprovada"},{dataIda:"2026-11-10",status:"finalizada",aprovacaoStatus:"recusada"}];
  assert.deepEqual(calcularCicloFolga(f,450,"2026-11-21").proximaPrevista,"2026-11-22");
  assert.equal(calcularCicloFolga(f,450,"2026-11-21").antecipada,true);
  assert.equal(calcularCicloFolga(f,450,"2026-11-22").antecipada,false);
});
test("mudanca de regime preserva ultima saida", () => {
  const f=[{dataIda:"2026-11-01",status:"finalizada",aprovacaoStatus:"dispensada"}];
  assert.equal(calcularCicloFolga(f,700,"2026-12-01").proximaPrevista,"2026-12-16");
});
test("retorno ao CC solicita confirmacao", () => {
  assert.equal(estadoQuilometragem(null,false),"informar");
  assert.equal(estadoQuilometragem(450,false),"reutilizar");
  assert.equal(estadoQuilometragem(450,true),"confirmar");
});
test("datas de calendario, inclusive virada de ano", () => {
  assert.equal(adicionarDiasIso("2026-12-31",7),"2027-01-07");
  assert.throws(()=>adicionarDiasIso("2026-02-30",7));
});
