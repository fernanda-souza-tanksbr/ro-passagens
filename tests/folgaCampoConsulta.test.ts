import test from "node:test";
import assert from "node:assert/strict";
import { consultarContextoFolga } from "../src/folgaCampoConsulta.ts";

const dados = { funcionario_id:"f",obra_id:"cc",distancia_km:250,retorno_ao_cc:false,estado:"reutilizar",ultima_folga_data_ida:null,proxima_folga_prevista:null,solicitacao_futura_existente_id:null };

test("flag desligada nao faz chamada remota",async()=>{
  let chamadas=0;
  const resultado=await consultarContextoFolga("f","cc",false,async()=>{chamadas++;return {data:dados,error:null}});
  assert.equal(resultado,null);assert.equal(chamadas,0);
});
test("flag ligada usa funcionario e CC selecionados",async()=>{
  const resultado=await consultarContextoFolga("f","cc",true,async args=>{
    assert.deepEqual(args,{p_funcionario_id:"f",p_obra_id:"cc"});
    return {data:dados,error:null};
  });
  assert.equal(resultado?.distancia_km,250);
});
test("falha de RPC nunca vira km nao cadastrado",async()=>{
  await assert.rejects(consultarContextoFolga("f","cc",true,async()=>({data:null,error:{message:"sem permissao"}})),/CONSULTA_CONTEXTO_FOLGA_FALHOU/);
});
test("resposta de outro CC nao pode ser reutilizada",async()=>{
  await assert.rejects(consultarContextoFolga("f","outro",true,async()=>({data:dados,error:null})),/CONTEXTO_DESATUALIZADO/);
});
