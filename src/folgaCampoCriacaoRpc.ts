import type { RotaCriacao } from "./folgaCampoCompatibilidade.ts";

export type DocumentosCriacao = readonly Record<string, string | number>[];
export type ArgumentosRpcCriacao = {
  p_solicitacao: Record<string, unknown>;
  p_documentos: DocumentosCriacao;
};
export type ChamadaCriacaoFolga =
  | { rpc: "ro_criar_solicitacao_com_aprovador"; args: ArgumentosRpcCriacao }
  | { rpc: "ro_criar_folga_campo_com_distancia"; args: ArgumentosRpcCriacao & {
      p_distancia_declarada_km: number | null;
      p_confirma_retorno: boolean;
    } };

/** Nao envia nenhum campo de distancia na RPC legada.
 * No fluxo novo, a quilometragem fornecida pelo usuario e sempre
 * revalidada no servidor contra funcionario, CC e episodio vigente.
 */
export function montarChamadaCriacao(
  rota: RotaCriacao,
  solicitacao: Record<string, unknown>,
  documentos: DocumentosCriacao
): ChamadaCriacaoFolga {
  if (!rota.ok) throw new Error(rota.motivo);
  const base: ArgumentosRpcCriacao = { p_solicitacao: solicitacao, p_documentos: documentos };
  if (rota.rpc === "ro_criar_solicitacao_com_aprovador") {
    return { rpc: rota.rpc, args: base };
  }
  if (!rota.argumentosExtras) throw new Error("ARGUMENTOS_DISTANCIA_AUSENTES");
  return { rpc: rota.rpc, args: { ...base, ...rota.argumentosExtras } };
}
