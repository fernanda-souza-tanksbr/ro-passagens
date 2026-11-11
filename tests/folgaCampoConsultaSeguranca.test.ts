import test from "node:test";
import assert from "node:assert/strict";
import { consultarContextoFolga } from "../src/folgaCampoConsulta.ts";
import { validarContextoDistancia } from "../src/folgaCampoContextoServidor.ts";

const base = {
  funcionario_id:"f",obra_id:"cc",distancia_km:250,
  retorno_ao_cc:false,estado:"reutilizar",
  ultima_folga_data_ida:null,proxima_folga_prevista:null,
  solicitacao_futura_existente_id:null
};
test("a consulta desligada nao consulta o servidor",async()=>{
  let n=0;
  assert.equal(await consultarContextoFolga("f","cc",false,async()=>{n++;return {data:base,error:null}}),null);
  assert.equal(n,0);
});
test("consulta ativa valida funcionario e CC",async()=>{
  assert.equal((await consultarContextoFolga("f","cc",true,async()=>({data:base,error:null})))?.distancia_km,250);
});
test("falha remota nao vira distancia nova",async()=>{
  await assert.rejects(consultarContextoFolga("f","cc",true,async()=>({data:null,error:{message:"denied"}})),/CONSULTA_CONTEXTO_FOLGA_FALHOU/);
});
test("troca de CC invalida resposta anterior",()=>{
  assert.throws(()=>validarContextoDistancia(base,"f","cc2"),/CONTEXTO_DESATUALIZADO/);
});
