import { regimePorDistancia } from "./folgaCampoRegimes.ts";

export type PeriodoFolga = { data_ida: string; data_retorno?: string | null; retorno_indefinido?: boolean | null };
export function fimEfetivoFolga(p: PeriodoFolga): string {
  return !p.retorno_indefinido && p.data_retorno && p.data_retorno >= p.data_ida ? p.data_retorno : p.data_ida;
}
export function periodosFolgaConflitam(a: PeriodoFolga, b: PeriodoFolga): boolean {
  return a.data_ida <= fimEfetivoFolga(b) && b.data_ida <= fimEfetivoFolga(a);
}
export function podePlanejarOutraFolgaSemanal(km: number | null | undefined): boolean {
  if (km === null || km === undefined || !Number.isSafeInteger(km)) return false;
  try { return regimePorDistancia(km).intervaloDias === 7; } catch { return false; }
}
