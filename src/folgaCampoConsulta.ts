import { validarContextoDistancia, type ContextoDistanciaServidor } from "./folgaCampoContextoServidor.ts";

type ResultadoRpc = { data: unknown; error: { message: string } | null };
type RpcConsulta = (args: { p_funcionario_id: string | null; p_obra_id: string; p_colaborador_id?: string }) => Promise<ResultadoRpc>;

/** Consulta somente quando o backend estiver implantado e a flag explicitamente ligada.
 * Nunca converte erro de rede/permissao em "km nao cadastrado".
 */
export async function consultarContextoFolga(
  funcionarioId: string | null,
  obraId: string,
  habilitado: boolean,
  rpc: RpcConsulta,
  colaboradorId: string | null = null
): Promise<ContextoDistanciaServidor | null> {
  if (!habilitado) return null;
  if ((!funcionarioId && !colaboradorId) || !obraId) throw new Error("FUNCIONARIO_CC_OBRIGATORIOS");
  const args = colaboradorId
    ? { p_funcionario_id: funcionarioId || null, p_obra_id: obraId, p_colaborador_id: colaboradorId }
    : { p_funcionario_id: funcionarioId, p_obra_id: obraId };
  const { data, error } = await rpc(args);
  if (error) throw new Error("CONSULTA_CONTEXTO_FOLGA_FALHOU");
  return validarContextoDistancia(data, funcionarioId, obraId, colaboradorId);
}
