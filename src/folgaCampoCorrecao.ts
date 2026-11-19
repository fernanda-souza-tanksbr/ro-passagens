import { regimePorDistancia } from "./folgaCampoRegimes.ts";

export type CorrecaoDistancia = { km: number; justificativa: string };
export function validarCorrecaoDistancia(
  textoKm: string,
  justificativa: string,
  kmAtual: number | null,
): CorrecaoDistancia {
  const texto = textoKm.trim();
  if (!/^\d+$/.test(texto)) throw new Error("Informe uma quilometragem inteira, sem sinal ou casas decimais.");
  const km = Number(texto);
  if (!Number.isSafeInteger(km)) throw new Error("Informe uma quilometragem válida.");
  regimePorDistancia(km);
  if (kmAtual !== null && km === kmAtual) throw new Error("A nova quilometragem deve ser diferente da atual.");
  const motivo = justificativa.trim();
  if (motivo.length < 10) throw new Error("Informe uma justificativa com pelo menos 10 caracteres.");
  return { km, justificativa: motivo };
}
export function podeExibirCorrecaoDistancia(access: { isRO: boolean; role: string | null }): boolean {
  return access.isRO || access.role === "coordenador" || access.role === "gerente";
}
