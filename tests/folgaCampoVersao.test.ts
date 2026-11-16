import { test } from "node:test";
import { strict as assert } from "node:assert";
import { avaliarManifestoFolga, MENSAGEM_ATUALIZAR_FOLGA, MENSAGEM_TRANSICAO_FOLGA } from "../src/folgaCampoVersao.ts";
test("versao antiga bloqueada somente no fluxo de folga", () => {
  assert.deepEqual(avaliarManifestoFolga({modo:"distancia",versao_minima:2},1,false),{ok:false,mensagem:MENSAGEM_ATUALIZAR_FOLGA});
  assert.deepEqual(avaliarManifestoFolga({modo:"distancia",versao_minima:2},2,true),{ok:true});
});
test("transicao suspende folga mesmo com cliente atualizado", () => {
  assert.deepEqual(avaliarManifestoFolga({modo:"transicao",versao_minima:2},2,true),{ok:false,mensagem:MENSAGEM_TRANSICAO_FOLGA});
  assert.deepEqual(avaliarManifestoFolga({modo:"legado",versao_minima:2},2,false),{ok:true});
});
test("manifesto invalido falha fechado", () => {
  assert.equal(avaliarManifestoFolga(null,2,false).ok,false);
  assert.equal(avaliarManifestoFolga({modo:"desconhecido",versao_minima:2},2,false).ok,false);
});
