import assert from "node:assert/strict";
import test from "node:test";
import { chaveConsultaFolga, prepararFolgaCampo, snapshotFolga } from "../src/folgaCampoIntegracao.ts";

const base = { funcionarioId: "func-1", obraId: "cc-1", kmSalvo: null, retornoAoCc: false, kmInformado: "601", confirmacaoRetorno: false, historico: [{dataIda:"2026-11-01",status:"finalizada",aprovacaoStatus:"aprovada"}], dataIda:"2026-11-30" };
test("declaracao inicial e snapshot do CC selecionado", () => {
  const r=prepararFolgaCampo(base);
  assert.equal(r.ok,true);
  if(r.ok) assert.deepEqual(snapshotFolga(r,base.obraId),{obra_id:"cc-1",distancia_km:601,regime_faixa:"601_800",regime_intervalo_dias:45});
});
test("nao reutiliza contexto se o CC mudou", () => {
  assert.notEqual(chaveConsultaFolga("func-1","cc-1"),chaveConsultaFolga("func-1","cc-2"));
});
test("quilometragem obrigatoria na primeira alocacao", () => {
  assert.deepEqual(prepararFolgaCampo({...base,kmInformado:""}),{ok:false,motivo:"DISTANCIA_OBRIGATORIA"});
});
test("rejeita decimal e distancia negativa", () => {
  for(const km of ["12.5","-1","abc"]) assert.deepEqual(prepararFolgaCampo({...base,kmInformado:km}),{ok:false,motivo:"DISTANCIA_INVALIDA"});
});
test("retorno ao CC exige confirmacao", () => {
  const retorno={...base,kmSalvo:601,retornoAoCc:true,kmInformado:""};
  assert.deepEqual(prepararFolgaCampo(retorno),{ok:false,motivo:"CONFIRMACAO_RETORNO_OBRIGATORIA"});
  assert.equal(prepararFolgaCampo({...retorno,confirmacaoRetorno:true}).ok,true);
});
test("reutilizacao da alocacao vigente nao exige nova declaracao", () => {
  const r=prepararFolgaCampo({...base,kmSalvo:601,kmInformado:""});
  assert.equal(r.ok,true);
  if(r.ok) assert.equal(r.exigeDeclaracao,false);
});

test("distancia salva corrompida retorna erro controlado, sem excecao", () => {
  for (const kmSalvo of [-1, 12.5, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.deepEqual(prepararFolgaCampo({...base, kmSalvo, kmInformado: ""}), {ok:false,motivo:"DISTANCIA_INVALIDA"});
  }
});
test("primeira folga sem historico nao e antecipada", () => {
  const r=prepararFolgaCampo({...base,historico:[]});
  assert.equal(r.ok,true);
  if(r.ok) { assert.equal(r.proximaPrevista,null); assert.equal(r.antecipada,false); }
});
