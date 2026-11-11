import { validarContextoDistancia, type ContextoDistanciaServidor } from "./folgaCampoContextoServidor.ts";

type ResultadoRpc = { data: unknown; error: { message: string } | null };
type RpcConsulta = (args: { p_funcionario_id: string; p_obra_id: string }) => Promise<ResultadoRpc>;

/** Consulta somente quando o backend estiver implantado e a flag explicitamente ligada.
 * Nunca converte erro de rede/permissao em "km nao cadastrado".
 */
export async function consultarContextoFolga(
  funcionarioId: string,
  obraId: string,
  habilitado: boolean,
  rpc: RpcConsulta
): Promise<ContextoDistanciaServidor | null> {
  if (!habilitado) return null;
  if (!funcionarioId || !obraId) throw new Error("FUNCIONARIO_CC_OBRIGATORIOS");
  const { data, error } = await rpc({ p_funcionario_id: funcionarioId, p_obra_id: obraId });
  if (error) throw new Error("CONSULTA_CONTEXTO_FOLGA_FALHOU");
  return validarContextoDistancia(data, funcionarioId, obraId);
}
