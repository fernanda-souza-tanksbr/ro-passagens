import { calcularCicloFolga, estadoQuilometragem, regimePorDistancia, type FolgaAnterior } from "./folgaCampoRegimes.ts";

export type ContextoFolgaCampo = {
  funcionarioId: string;
  colaboradorId?: string | null;
  obraId: string;
  kmSalvo: number | null;
  retornoAoCc: boolean;
  kmInformado: string;
  confirmacaoRetorno: boolean;
  historico: readonly FolgaAnterior[];
  dataIda: string;
};
export type PreparacaoFolgaCampo =
  | { ok: false; motivo: "FUNCIONARIO_OU_CC_OBRIGATORIO" | "DISTANCIA_OBRIGATORIA" | "DISTANCIA_INVALIDA" | "CONFIRMACAO_RETORNO_OBRIGATORIA" | "DATA_INVALIDA" }
  | { ok: true; km: number; faixa: string; intervaloDias: number; transporte: string; proximaPrevista: string | null; antecipada: boolean; exigeDeclaracao: boolean };

export function prepararFolgaCampo(c: ContextoFolgaCampo): PreparacaoFolgaCampo {
  if ((!c.funcionarioId && !c.colaboradorId) || !c.obraId) return { ok: false, motivo: "FUNCIONARIO_OU_CC_OBRIGATORIO" };
  let estado: ReturnType<typeof estadoQuilometragem>;
  try { estado = estadoQuilometragem(c.kmSalvo, c.retornoAoCc); }
  catch { return { ok: false, motivo: "DISTANCIA_INVALIDA" }; }
  if (estado === "informar" && !c.kmInformado.trim()) return { ok: false, motivo: "DISTANCIA_OBRIGATORIA" };
  const km = estado === "informar" ? Number(c.kmInformado) : c.kmSalvo;
  if (km === null || (estado === "informar" && !/^\d+$/.test(c.kmInformado.trim()))) return { ok: false, motivo: "DISTANCIA_INVALIDA" };
  let regime: ReturnType<typeof regimePorDistancia>;
  try { regime = regimePorDistancia(km); } catch { return { ok: false, motivo: "DISTANCIA_INVALIDA" }; }
  if (estado === "confirmar" && !c.confirmacaoRetorno) return { ok: false, motivo: "CONFIRMACAO_RETORNO_OBRIGATORIA" };
  try {
    const ciclo = calcularCicloFolga(c.historico, km, c.dataIda);
    return { ok: true, km, faixa: regime.faixa, intervaloDias: regime.intervaloDias, transporte: regime.transporte, proximaPrevista: ciclo.proximaPrevista, antecipada: ciclo.antecipada, exigeDeclaracao: estado !== "reutilizar" };
  } catch { return { ok: false, motivo: "DATA_INVALIDA" }; }
}
/** Chave de consulta: deve variar quando o usuario altera o CC no formulario. */
export function chaveConsultaFolga(funcionarioId: string, obraId: string): string {
  return JSON.stringify([funcionarioId, obraId]);
}
/** Snapshot somente para a futura RPC; nao enviar a funcao antiga antes da migracao. */
export function snapshotFolga(preparacao: Extract<PreparacaoFolgaCampo, { ok: true }>, obraId: string) {
  return { obra_id: obraId, distancia_km: preparacao.km, regime_faixa: preparacao.faixa, regime_intervalo_dias: preparacao.intervaloDias };
}
