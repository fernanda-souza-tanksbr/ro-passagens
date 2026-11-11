import { regimePorDistancia } from "./folgaCampoRegimes.ts";

export type ContextoDistanciaServidor = {
  funcionario_id: string;
  obra_id: string;
  distancia_km: number | null;
  retorno_ao_cc: boolean;
  estado: "informar" | "reutilizar" | "confirmar";
  ultima_folga_data_ida: string | null;
  proxima_folga_prevista: string | null;
  solicitacao_futura_existente_id: string | null;
};

/** Nao confia no contexto retornado pela RPC sem validar o CC e funcionario consultados. */
export function validarContextoDistancia(
  raw: unknown,
  funcionarioId: string,
  obraId: string
): ContextoDistanciaServidor {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("CONTEXTO_INVALIDO");
  const c = raw as Record<string, unknown>;
  if (!funcionarioId || !obraId || c.funcionario_id !== funcionarioId || c.obra_id !== obraId) {
    throw new Error("CONTEXTO_DESATUALIZADO");
  }
  const estado = c.estado;
  if (estado !== "informar" && estado !== "reutilizar" && estado !== "confirmar") {
    throw new Error("ESTADO_INVALIDO");
  }
  const km = c.distancia_km;
  if (estado === "informar" && km !== null) throw new Error("DISTANCIA_INCONSISTENTE");
  if (estado !== "informar") {
    if (typeof km !== "number") throw new Error("DISTANCIA_INCONSISTENTE");
    regimePorDistancia(km);
  }
  if (c.retorno_ao_cc !== (estado === "confirmar")) throw new Error("RETORNO_INCONSISTENTE");
  for (const campo of ["ultima_folga_data_ida", "proxima_folga_prevista"] as const) {
    const valor = c[campo];
    if (valor !== null && (typeof valor !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(valor))) {
      throw new Error("DATA_INVALIDA");
    }
  }
  const futura = c.solicitacao_futura_existente_id;
  if (futura !== null && typeof futura !== "string") throw new Error("SOLICITACAO_FUTURA_INVALIDA");
  return {
    funcionario_id: funcionarioId,
    obra_id: obraId,
    distancia_km: km as number | null,
    retorno_ao_cc: estado === "confirmar",
    estado,
    ultima_folga_data_ida: c.ultima_folga_data_ida as string | null,
    proxima_folga_prevista: c.proxima_folga_prevista as string | null,
    solicitacao_futura_existente_id: futura as string | null,
  };
}
