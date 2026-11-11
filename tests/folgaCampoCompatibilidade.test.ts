import assert from "node:assert/strict";
import test from "node:test";
import { planejarRotaCriacao } from "../src/folgaCampoCompatibilidade.ts";
import type { ContextoFolgaCampo } from "../src/folgaCampoIntegracao.ts";

const base: ContextoFolgaCampo = {
  funcionarioId:"f",obraId:"cc",kmSalvo:null,retornoAoCc:false,
  kmInformado:"601",confirmacaoRetorno:false,historico:[],dataIda:"2026-11-11"
};
test("fluxo desabilitado preserva RPC atual de folga sem exigir km",()=>{
  assert.deepEqual(planejarRotaCriacao("folga_campo",false,null),{
    ok:true,rpc:"ro_criar_solicitacao_com_aprovador",argumentosExtras:null
  });
});
test("outros motivos permanecem na RPC atual mesmo com recurso habilitado",()=>{
  assert.equal(planejarRotaCriacao("visita",true,null).ok,true);
  assert.equal(planejarRotaCriacao("visita",true,null).ok && planejarRotaCriacao("visita",true,null).rpc,"ro_criar_solicitacao_com_aprovador");
});
test("novo fluxo de folga exige contexto, sem fallback silencioso",()=>{
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,null),{ok:false,motivo:"FUNCIONARIO_OU_CC_OBRIGATORIO"});
});
test("novo CC informa distancia somente na RPC nova",()=>{
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,base),{
    ok:true,rpc:"ro_criar_folga_campo_com_distancia",
    argumentosExtras:{p_distancia_declarada_km:601,p_confirma_retorno:false}
  });
});
test("mesmo CC nao envia distancia para substituir valor existente",()=>{
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,{...base,kmSalvo:601,kmInformado:""}),{
    ok:true,rpc:"ro_criar_folga_campo_com_distancia",
    argumentosExtras:{p_distancia_declarada_km:null,p_confirma_retorno:false}
  });
});
test("retorno exige confirmacao e nao altera km existente",()=>{
  const c={...base,kmSalvo:601,kmInformado:"",retornoAoCc:true};
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,c),{ok:false,motivo:"CONFIRMACAO_RETORNO_OBRIGATORIA"});
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,{...c,confirmacaoRetorno:true}),{
    ok:true,rpc:"ro_criar_folga_campo_com_distancia",
    argumentosExtras:{p_distancia_declarada_km:null,p_confirma_retorno:true}
  });
});
test("distancia invalida nao recai no fluxo legado quando habilitado",()=>{
  assert.deepEqual(planejarRotaCriacao("folga_campo",true,{...base,kmInformado:"-1"}),{ok:false,motivo:"DISTANCIA_INVALIDA"});
});
