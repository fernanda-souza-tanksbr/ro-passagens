import test from "node:test";
import assert from "node:assert/strict";
import { montarChamadaCriacao } from "../src/folgaCampoCriacaoRpc.ts";
import { planejarRotaCriacao } from "../src/folgaCampoCompatibilidade.ts";

const payload={id:"pedido1",motivo:"folga_campo",funcionario_id:"func1",obra_id:"cc1"};
const documentos=[{categoria:"comprovante",storage_path:"pedido1/comprovante/file.pdf"}];
const contexto={
  funcionarioId:"func1",obraId:"cc1",kmSalvo:null,retornoAoCc:false,
  kmInformado:"601",confirmacaoRetorno:false,historico:[],dataIda:"2027-03-01"
};
test("fluxo desligado preserva argumentos da RPC legada sem campos adicionais",()=>{
  const rota=planejarRotaCriacao("folga_campo",false,contexto);
  const chamada=montarChamadaCriacao(rota,payload,documentos);
  assert.equal(chamada.rpc,"ro_criar_solicitacao_com_aprovador");
  assert.deepEqual(chamada.args,{p_solicitacao:payload,p_documentos:documentos});
});
test("outros motivos sempre preservam a RPC antiga",()=>{
  const rota=planejarRotaCriacao("ferias",true,contexto);
  const chamada=montarChamadaCriacao(rota,payload,documentos);
  assert.equal(chamada.rpc,"ro_criar_solicitacao_com_aprovador");
});
test("novo fluxo passa id, payload, documentos e km na mesma chamada",()=>{
  const rota=planejarRotaCriacao("folga_campo",true,contexto);
  const chamada=montarChamadaCriacao(rota,payload,documentos);
  assert.equal(chamada.rpc,"ro_criar_folga_campo_com_distancia");
  assert.deepEqual(chamada.args,{
    p_solicitacao:payload,p_documentos:documentos,
    p_distancia_declarada_km:601,p_confirma_retorno:false
  });
});
test("retorno ao CC reutiliza km salvo e exige confirmacao",()=>{
  const rota=planejarRotaCriacao("folga_campo",true,{
    ...contexto,kmSalvo:250,retornoAoCc:true,kmInformado:"",confirmacaoRetorno:true
  });
  const chamada=montarChamadaCriacao(rota,payload,documentos);
  assert.equal(chamada.rpc,"ro_criar_folga_campo_com_distancia");
  assert.equal(chamada.args.p_distancia_declarada_km,null);
  assert.equal(chamada.args.p_confirma_retorno,true);
});
test("validacao invalida nunca cai silenciosamente na criacao legada",()=>{
  const rota=planejarRotaCriacao("folga_campo",true,{...contexto,kmInformado:"-1"});
  assert.throws(()=>montarChamadaCriacao(rota,payload,documentos),/DISTANCIA_INVALIDA/);
});
