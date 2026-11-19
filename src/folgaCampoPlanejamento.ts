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

/** Usa o km do contexto validado; enquanto ainda não há snapshot, aceita somente dígitos decimais. */
export function distanciaPlanejamentoSemanal(kmSalvo: number | null | undefined, kmInformado: string): number | null {
  if (kmSalvo !== null && kmSalvo !== undefined) return kmSalvo;
  const texto = kmInformado.trim();
  if (!/^\d+$/.test(texto)) return null;
  const km = Number(texto);
  return Number.isSafeInteger(km) ? km : null;
}
