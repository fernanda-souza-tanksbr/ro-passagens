import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const sql=fs.readFileSync("supabase/manual/20261119_restringir_viagem_administrativa_NAO_APLICAR.sql","utf8");
const rollback=fs.readFileSync("supabase/manual/20261119_restringir_viagem_administrativa_ROLLBACK.sql","utf8");
const page=fs.readFileSync("src/pages.tsx","utf8");

test("SQL protege todas as entradas da API (insert, alteração de identidade e motivo)",()=>{
  assert.match(sql,/before insert or update of motivo,funcionario_id,colaborador_id,viajante_nome_informado/i);
  assert.match(sql,/new\.colaborador_id is null or new\.viajante_nome_informado is not null/i);
  assert.match(sql,/new\.funcionario_id is distinct from v_funcionario_vinculado/i);
  assert.match(sql,/public\.ro_funcionarios_enderecos_privados/i);
  assert.match(sql,/public\.funcionarios/i);
  assert.match(sql,/visivel_obras_control/i);
  assert.doesNotMatch(sql,/\bupdate\s+public\.ro_passagem_solicitacoes\b/i);
});

test("retorno é reconhecido na função de produção e o rollback protege dados novos",()=>{
  assert.match(sql,/create or replace function public\.ro_motivo_possui_retorno/i);
  assert.match(sql,/recesso','viagem_administrativa/i);
  assert.match(sql,/RETORNO_ANTERIOR_A_IDA/i);
  assert.match(sql,/DATA_RETORNO_OBRIGATORIA_PARA_TRECHO_RETORNO/i);
  assert.match(rollback,/ROLLBACK_RETORNO_BLOQUEADO/i);
  assert.match(rollback,/drop trigger if exists ro_validar_passageiro_viagem_administrativa/i);
  assert.match(page,/erroRetornoAdministrativo\(form\.motivo/);
  assert.match(page,/row\.destino_retorno && <DT t="Destino de retorno"/);
});

test("frontend valida somente passageiro, sem confundir autorização do solicitante",()=>{
  assert.match(page,/passageiroElegivelViagemAdministrativa\(funcionarioSelecionado\)/);
  assert.match(page,/motivoAdministrativoPermitido\(form\.motivo, funcionarioSelecionado\)/);
  assert.match(page,/supabase\.rpc\("ro_criar_solicitacao_com_aprovador"/);
});

test("SQL de aplicação e rollback contêm corpos SQL e PL/pgSQL delimitados corretamente",()=>{
  for (const script of [sql, rollback]) {
    assert.doesNotMatch(script, /\bas \$(?!\$|function\$)/i);
    assert.doesNotMatch(script, /\bend \$(?!\$)/i);
    assert.equal((script.match(/\$\$/g)||[]).length % 2,0);
    assert.equal((script.match(/\$function\$/g)||[]).length,2);
    assert.match(script,/\$function\$;\s*commit;/i);
    assert.match(script,/^begin;/im);
    assert.match(script,/commit;\s*$/i);
  }
});

test("catálogo privado expõe vínculo não operacional, rollback restaura seleção original",()=>{
  assert.match(sql,/create or replace function public\.ro_catalogo_colaboradores_viagem\(\)/i);
  assert.match(sql,/e\.funcionario_id is null or exists/i);
  assert.match(sql,/f\.visivel_obras_control = false/i);
  assert.match(rollback,/and e\.funcionario_id is null/i);
  assert.match(sql,/new\.funcionario_id is distinct from v_funcionario_vinculado/i);
});
