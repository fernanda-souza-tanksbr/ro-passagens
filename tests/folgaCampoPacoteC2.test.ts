import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../sql/folga_semanal_trigger_draft.sql", import.meta.url), "utf8");
const release = readFileSync(new URL("../sql/folga_semanal_c2_producao.sql", import.meta.url), "utf8");
const executableStart = "CREATE OR REPLACE FUNCTION public.ro_validar_ciclo_folga_campo()";

test("C2 weekly production SQL preserves the homologated executable exactly", () => {
  const sourceStart = source.indexOf(executableStart);
  const releaseStart = release.indexOf(executableStart);
  assert.ok(sourceStart >= 0, "original function must exist");
  assert.ok(releaseStart >= 0, "release function must exist");
  assert.equal(release.slice(releaseStart), source.slice(sourceStart));
});

test("C2 weekly production SQL fails closed on an unexpected production baseline", () => {
  const guards = release.slice(0, release.indexOf(executableStart));
  for (const expected of [
    "C2_BASELINE_FUNCTION_HASH_MISMATCH",
    "C2_BASELINE_TRIGGER_MISMATCH",
    "C2_DISTANCE_GATE_NOT_ENABLED",
    "C2_SELECTIVE_SUSPENSION_NOT_ACTIVE",
  ]) assert.ok(guards.includes(expected), `Missing release guard: ${expected}`);
  assert.ok(guards.includes("pg_get_functiondef"));
  assert.ok(guards.includes("pg_get_triggerdef"));
});

test("C2 weekly rejects overlapping periods while preserving separate weekly bookings", () => {
  assert.match(release, /if new\.folga_intervalo_dias = 7 then/);
  assert.match(release, /new\.data_ida <= case when s\.retorno_indefinido/);
  assert.match(release, /s\.data_ida <= case when new\.retorno_indefinido/);
  assert.match(release, /FOLGA_FUTURA_DUPLICADA/);
  assert.match(release, /ro_funcionario_possui_folga_futura_ativa/);
});
