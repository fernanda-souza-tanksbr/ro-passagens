import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import { EMPTY_ACCESS } from "../src/accessCache.ts";
import { reportRouteDecision } from "../src/reportRouteDecision.ts";
import { defaultReportViewState, normalizeReportFilters, readReportViewState, writeReportViewState } from "../src/relatoriosPersistence.ts";

const allowed = { ...EMPTY_ACCESS, canViewAll: true, role: "gerente" };
test("F5: sessão autenticada aguarda permissões sem redirecionamento", () => {
  assert.equal(reportRouteDecision("u1", null, EMPTY_ACCESS), "pending");
  assert.equal(reportRouteDecision("u1", "u2", allowed), "pending");
  assert.equal(reportRouteDecision("u1", "u1", allowed), "allowed");
});
test("permissões negadas redirecionam legitimamente", () => {
  assert.equal(reportRouteDecision("u1", "u1", EMPTY_ACCESS), "denied");
  assert.equal(reportRouteDecision("u1", "u1", { ...allowed, isRh: true, canImport: false }), "denied");
  assert.equal(reportRouteDecision("u1", "u1", { ...allowed, isRh: true, canImport: true }), "allowed");
});
test("App espera autorização da sessão atual antes de montar relatórios", () => {
  const app = fs.readFileSync("src/App.tsx", "utf8");
  assert.match(app, /reportRouteDecision\(session\.user\.id, accessReadyUserId, access\) === "pending"/);
  assert.match(app, /reportRoute === "allowed"/);
  assert.match(app, /<Navigate to="\/solicitacoes" replace \/>/);
  assert.match(app, /setAccessReadyUserId\(session\.user\.id\)/);
});
test("datas ISO reais e estado completo sobrevivem ao reload", () => {
  const filters = normalizeReportFilters({ ...defaultReportViewState().filtros, inicio: "2026-11-01", fim: "2026-11-18" });
  assert.equal(filters.inicio, "2026-11-01");
  assert.equal(filters.fim, "2026-11-18");
  const store = new Map<string,string>();
  const storage = { getItem: (key:string) => store.get(key) ?? null, setItem: (key:string,value:string) => { store.set(key,value); } };
  const state = { ...defaultReportViewState(), filtros: { ...filters, motivo: "ferias" }, aplicados: filters, ordem: "valor_total" as const, direcao: "desc" as const, scrollY: 731, centroSelecionado: "sem-centro" };
  writeReportViewState("u1",state,storage);
  const restored=readReportViewState("u1",storage);
  assert.deepEqual(restored.filtros,state.filtros);
  assert.deepEqual(restored.aplicados,state.aplicados);
  assert.equal(restored.ordem,"valor_total");
  assert.equal(restored.direcao,"desc");
  assert.equal(restored.scrollY,731);
  assert.equal(restored.centroSelecionado,"sem-centro");
});
