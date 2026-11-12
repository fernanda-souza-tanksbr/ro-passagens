import test from "node:test";
import assert from "node:assert/strict";
import { validarContextoDistancia } from "../src/folgaCampoContextoServidor.ts";
import { consultarContextoFolga } from "../src/folgaCampoConsulta.ts";
import { planejarRotaCriacao } from "../src/folgaCampoCompatibilidade.ts";
import { montarChamadaCriacao } from "../src/folgaCampoCriacaoRpc.ts";

const base = {
  funcionario_id: null, colaborador_id: "colab1", obra_id: "cc1",
  distancia_km: 601, retorno_ao_cc: false, estado: "reutilizar",
  ultima_folga_data_ida: "2026-05-01",
  proxima_folga_prevista: "2026-06-15",
  solicitacao_futura_existente_id: null
};

test("privado sem vinculo valida contexto com funcionario null",()=>{
  const resultado=validarContextoDistancia(base,null,"cc1","colab1");
  assert.equal(resultado.funcionario_id,null);
  assert.equal(resultado.colaborador_id,"colab1");
  assert.equal(resultado.distancia_km,601);
});

test("privado vinculado valida funcionario retornado",()=>{
  const resultado=validarContextoDistancia({...base,funcionario_id:"func1"},null,"cc1","colab1");
  assert.equal(resultado.funcionario_id,"func1");
});

test("resposta de outro colaborador e rejeitada",()=>{
  assert.throws(()=>validarContextoDistancia(base,null,"cc1","colab2"),/CONTEXTO_DESATUALIZADO/);
});

test("consulta privada envia ambos IDs sem inferir funcionario inexistente",async()=>{
  const result=await consultarContextoFolga(null,"cc1",true,async args=>{
    assert.deepEqual(args,{p_funcionario_id:null,p_obra_id:"cc1",p_colaborador_id:"colab1"});
    return {data:base,error:null};
  },"colab1");
  assert.equal(result?.colaborador_id,"colab1");
});

test("rota privada sem vinculo utiliza RPC nova e declara km",()=>{
  const rota=planejarRotaCriacao("folga_campo",true,{
    funcionarioId:"",colaboradorId:"colab1",obraId:"cc1",
    kmSalvo:null,retornoAoCc:false,kmInformado:"601",
    confirmacaoRetorno:false,historico:[],dataIda:"2027-06-01"
  });
  assert.equal(rota.ok,true);
  const chamada=montarChamadaCriacao(rota,{
    id:"sol1",motivo:"folga_campo",funcionario_id:null,
    colaborador_id:"colab1",obra_id:"cc1"
  },[]);
  assert.equal(chamada.rpc,"ro_criar_folga_campo_com_distancia");
  assert.equal(chamada.args.p_distancia_declarada_km,601);
});

test("privado sem contexto nao pode usar caminho legado quando ativado",()=>{
  const rota=planejarRotaCriacao("folga_campo",true,null);
  assert.throws(()=>montarChamadaCriacao(rota,{},[]),/FUNCIONARIO_OU_CC_OBRIGATORIO/);
});

test("flag desligada preserva RPC legada para privado",()=>{
  const payload={motivo:"folga_campo",colaborador_id:"colab1",funcionario_id:null};
  const rota=planejarRotaCriacao("folga_campo",false,null);
  const chamada=montarChamadaCriacao(rota,payload,[]);
  assert.equal(chamada.rpc,"ro_criar_solicitacao_com_aprovador");
  assert.deepEqual(chamada.args.p_solicitacao,payload);
});
