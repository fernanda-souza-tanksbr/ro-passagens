import { expect, test } from "@playwright/test";
/** Versao legada ficticia e aviso real renderizado pelo React, sem backend operacional. */
const HOST="http://127.0.0.1:4174";
test("formulario antigo detecta transicao e preserva outros motivos",async({page})=>{
  await page.route("**/folga-campo-release.json",route=>route.fulfill({
    status:200,contentType:"application/json",
    body:JSON.stringify({modo:"transicao",versao_minima:2})
  }));
  // Testa o contrato no navegador via modulo TS real servido pelo Vite.
  await page.goto(HOST+"/");
  const resultado=await page.evaluate(async()=>{
    const mod=await import("/src/folgaCampoVersao.ts");
    return {
      folga:mod.avaliarManifestoFolga({modo:"transicao",versao_minima:2},2,true),
      antiga:mod.avaliarManifestoFolga({modo:"distancia",versao_minima:2},1,false),
      outras:mod.avaliarManifestoFolga({modo:"legado",versao_minima:2},2,false)
    };
  });
  expect(resultado.folga.ok).toBe(false);
  expect(resultado.antiga.ok).toBe(false);
  expect(resultado.outras.ok).toBe(true);
});
