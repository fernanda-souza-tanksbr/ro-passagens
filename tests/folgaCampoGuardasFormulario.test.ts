import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validarContextoDistancia } from "../src/folgaCampoContextoServidor.ts";

const pages=readFileSync("src/pages.tsx","utf8");

test("novo fluxo permanece desligado ate rollout autorizado",()=>{
  assert.match(pages,/const NOVO_FLUXO_FOLGA_ATIVO\s*=\s*fluxoFolgaDistanciaHabilitado\(import\.meta\.env\.VITE_FOLGA_CAMPO_KM_ENABLED\)/);
  assert.match(readFileSync("src/folgaCampoFeatureConfig.ts","utf8"),/valor === "C2_PRODUCAO_APROVADA"/);
});

test("formulario privado vinculado nao exige id de funcionario que o catalogo nao informou",()=>{
  assert.match(pages,/!funcionarioFolgaId\s*\|\|\s*contextoKmFolga\?\.funcionario_id===funcionarioFolgaId/);
  assert.match(pages,/contextoKmFolga\?\.colaborador_id===colaboradorFolgaId/);
  const resposta={
    funcionario_id:"funcionario-servidor",colaborador_id:"colaborador-privado",
    obra_id:"obra-a",estado:"informar",distancia_km:null,
    retorno_ao_cc:false,ultima_folga_data_ida:null,
    proxima_folga_prevista:null,solicitacao_futura_existente_id:null
  };
  assert.equal(validarContextoDistancia(resposta,null,"obra-a","colaborador-privado").funcionario_id,"funcionario-servidor");
});

test("mudanca de obra exige nova consulta e cancela o resultado antigo",()=>{
  assert.match(pages,/const request=\+\+kmFolgaRequestRef\.current/);
  assert.match(pages,/request!==kmFolgaRequestRef\.current/);
  assert.match(pages,/form\.funcionario_id,form\.obra_id,form\.motivo/);
});

test("criacao legada permanece quando a flag esta desligada",()=>{
  assert.match(pages,/planejarRotaCriacao\(form\.motivo,NOVO_FLUXO_FOLGA_ATIVO,contextoFolga\)/);
  assert.match(pages,/ro_criar_solicitacao_com_aprovador/);
});
