import test from "node:test";
import assert from "node:assert/strict";
import { responsavelRoCorrespondeFiltro } from "../src/solicitacoesFilters.ts";
import { normalizeSolicitacoesFilters, defaultSolicitacoesFilters } from "../src/solicitacoesFilterPersistence.ts";
import { statusPertenceAoFiltro } from "../src/solicitacoesFilters.ts";
import { matchesApprovalFilter } from "../src/approvalVisibility.ts";

const user = "c1d074ea-9140-42f7-98bb-91992985b101";
const outro = "c1d074ea-9140-42f7-98bb-91992985b102";

test("todos, minhas, sem responsável e operador selecionado", () => {
  for (const owner of [user, outro, null]) assert.equal(responsavelRoCorrespondeFiltro(owner, "", user, true), true);
  assert.equal(responsavelRoCorrespondeFiltro(user, "minhas", user, true), true);
  assert.equal(responsavelRoCorrespondeFiltro(outro, "minhas", user, true), false);
  assert.equal(responsavelRoCorrespondeFiltro(null, "sem_responsavel", user, true), true);
  assert.equal(responsavelRoCorrespondeFiltro(user, "sem_responsavel", user, true), false);
  assert.equal(responsavelRoCorrespondeFiltro(outro, outro, user, true), true);
  assert.equal(responsavelRoCorrespondeFiltro(user, outro, user, true), false);
});

test("sem permissão de visualização geral não reduz nem expande o escopo do banco", () => {
  assert.equal(responsavelRoCorrespondeFiltro(outro, "minhas", user, false), true);
  assert.equal(responsavelRoCorrespondeFiltro(null, "sem_responsavel", user, false), true);
});

test("responsável inativo permanece filtrável por ID e outros filtros são combinados", () => {
  const filters = normalizeSolicitacoesFilters({ ...defaultSolicitacoesFilters(), responsavelRo: outro, status: ["em_andamento"], motivo: "ferias", obra: "obra1", aprovacao: "pendente", busca: "Recife" });
  const row = { responsavel_ro_id: outro, status: "passagem_comprada" as const, motivo: "ferias", obra: "obra1", aprovacao_status: "pendente" as const, nome: "Recife" };
  const valid = statusPertenceAoFiltro(row.status, filters.status) &&
    (!filters.motivo || row.motivo === filters.motivo) &&
    matchesApprovalFilter(row.aprovacao_status, filters.aprovacao) &&
    (!filters.obra || row.obra === filters.obra) &&
    responsavelRoCorrespondeFiltro(row.responsavel_ro_id, filters.responsavelRo, user, true) &&
    row.nome.includes(filters.busca);
  assert.equal(valid, true);
  assert.equal(responsavelRoCorrespondeFiltro(row.responsavel_ro_id, "minhas", user, true), false);
});
