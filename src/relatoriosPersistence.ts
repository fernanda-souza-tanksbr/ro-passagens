import { motivoLabel, statusOptions } from "./lib.ts";

export type ReportFilters = { inicio: string; fim: string; centro: string; status: string; motivo: string; responsavel: string };
export type ReportSort = "codigo" | "nome" | "compradas" | "abertas" | "imprevistos" | "valor_total";
export type ReportViewState = { filtros: ReportFilters; aplicados: ReportFilters; ordem: ReportSort; direcao: "asc" | "desc"; scrollY: number; centroSelecionado: string | null };
type FilterStorage = Pick<Storage, "getItem" | "setItem">;
const prefix = "ro-passagens:relatorios:v1:";
const validSort = new Set<ReportSort>(["codigo","nome","compradas","abertas","imprevistos","valor_total"]);
const validStatus = new Set([...statusOptions.map(x => x.value), "em_analise"]);
const validMotivo = new Set(Object.keys(motivoLabel));
const date = (v: unknown) => typeof v === "string" && (v === "" || (/^\\d{4}-\\d{2}-\\d{2}$/.test(v) && !Number.isNaN(Date.parse(v)))) ? v : "";
const id = (v: unknown) => typeof v === "string" && (v === "" || v === "sem-centro" || /^[0-9a-f-]{36}$/i.test(v)) ? v : "";
export function defaultReportFilters(): ReportFilters {
  const today = new Date().toISOString().slice(0, 10);
  return { inicio: today.slice(0, 8) + "01", fim: today, centro: "", status: "", motivo: "", responsavel: "" };
}
export function normalizeReportFilters(value: unknown): ReportFilters {
  const d = defaultReportFilters();
  if (!value || typeof value !== "object" || Array.isArray(value)) return d;
  const x = value as Record<string, unknown>;
  const inicio = date(x.inicio), fim = date(x.fim);
  return { inicio: inicio || (x.inicio === "" ? "" : d.inicio), fim: fim || (x.fim === "" ? "" : d.fim), centro: id(x.centro), status: typeof x.status === "string" && validStatus.has(x.status) ? x.status : "", motivo: typeof x.motivo === "string" && validMotivo.has(x.motivo) ? x.motivo : "", responsavel: id(x.responsavel) };
}
export function hasSpecificReportFilters(f: ReportFilters) {
  const defaults = defaultReportFilters();
  return Boolean(f.centro || f.status || f.motivo || f.responsavel || f.inicio !== defaults.inicio || f.fim !== defaults.fim);
}
export function reportStateKey(userId: string) { return prefix + userId; }
export function defaultReportViewState(): ReportViewState { const filtros = defaultReportFilters(); return { filtros, aplicados: { ...filtros }, ordem: "codigo", direcao: "asc", scrollY: 0, centroSelecionado: null }; }
export function normalizeReportViewState(value: unknown): ReportViewState {
  const d = defaultReportViewState();
  if (!value || typeof value !== "object" || Array.isArray(value)) return d;
  const x = value as Record<string, unknown>;
  return { filtros: normalizeReportFilters(x.filtros), aplicados: normalizeReportFilters(x.aplicados), ordem: validSort.has(x.ordem as ReportSort) ? x.ordem as ReportSort : d.ordem, direcao: x.direcao === "desc" ? "desc" : "asc", scrollY: typeof x.scrollY === "number" && Number.isFinite(x.scrollY) ? Math.max(0, Math.min(1000000, x.scrollY)) : 0, centroSelecionado: typeof x.centroSelecionado === "string" && id(x.centroSelecionado) ? x.centroSelecionado : null };
}
export function readReportViewState(userId: string, storage: FilterStorage = localStorage): ReportViewState {
  try { const raw = storage.getItem(reportStateKey(userId)); if (!raw) return defaultReportViewState(); const parsed = JSON.parse(raw); return parsed?.version === 1 ? normalizeReportViewState(parsed.state) : defaultReportViewState(); } catch { return defaultReportViewState(); }
}
export function writeReportViewState(userId: string, state: ReportViewState, storage: FilterStorage = localStorage) {
  try { storage.setItem(reportStateKey(userId), JSON.stringify({ version: 1, state: normalizeReportViewState(state) })); } catch { /* Storage unavailable. */ }
}
export type ReportPerson = { id: string; obra_id: string | null; status: string; motivo: string | null; responsavel_ro_id: string | null; funcionario_id?: string | null; colaborador_id?: string | null; viajante_nome_informado?: string | null; funcionario?: { nome: string } | null };
export function matchesReportPerson(s: ReportPerson, f: ReportFilters) {
  return s.status !== "cancelada" && (!f.status || s.status === f.status) && (!f.motivo || s.motivo === f.motivo) && (!f.responsavel || s.responsavel_ro_id === f.responsavel);
}
export function namesByReportCenter<T extends ReportPerson>(costs: Array<{ centro_custo_id: string | null; solicitacao: T }>, open: T[], f: ReportFilters, names: Record<string,string>, resolve: (s:T, name?:string)=>string|null) {
  const groups = new Map<string, Set<string>>();
  const add = (s:T, centro:string) => { if (!matchesReportPerson(s,f)) return; if (f.centro && f.centro !== centro) return; const name = resolve(s,names[s.id])?.trim(); if (!name) return; const group=groups.get(centro)||new Set<string>(); group.add(name); groups.set(centro,group); };
  for(const c of costs) add(c.solicitacao,c.centro_custo_id||c.solicitacao.obra_id||"sem-centro");
  for(const s of open) add(s,s.obra_id||"sem-centro");
  return new Map([...groups].map(([key,value])=>[key,[...value].sort((a,b)=>a.localeCompare(b,"pt-BR"))]));
}
