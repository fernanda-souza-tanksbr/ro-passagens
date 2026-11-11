import { prepararFolgaCampo, type ContextoFolgaCampo, type PreparacaoFolgaCampo } from "./folgaCampoIntegracao.ts";

/**
 * Planejamento puro da chamada. Nao chama Supabase e nao altera a criacao atual.
 * A ativacao e explicita: por padrao, todas as solicitacoes usam a RPC legada.
 */
export type RotaCriacao =
  | { ok: true; rpc: "ro_criar_solicitacao_com_aprovador"; argumentosExtras: null }
  | { ok: true; rpc: "ro_criar_folga_campo_com_distancia"; argumentosExtras: { p_distancia_declarada_km: number | null; p_confirma_retorno: boolean } }
  | { ok: false; motivo: Extract<PreparacaoFolgaCampo, { ok: false }>["motivo"] };

export function planejarRotaCriacao(
  motivo: string,
  habilitarNovoFluxo: boolean,
  contexto: ContextoFolgaCampo | null
): RotaCriacao {
  if (motivo !== "folga_campo" || !habilitarNovoFluxo) {
    return { ok: true, rpc: "ro_criar_solicitacao_com_aprovador", argumentosExtras: null };
  }
  if (!contexto) return { ok: false, motivo: "FUNCIONARIO_OU_CC_OBRIGATORIO" };
  const preparacao = prepararFolgaCampo(contexto);
  if (!preparacao.ok) return preparacao;
  // Km existente nunca pode ser sobrescrito pelo formulario comum.
  // No retorno, o usuario apenas confirma o valor ja persistido.
  return {
    ok: true,
    rpc: "ro_criar_folga_campo_com_distancia",
    argumentosExtras: {
      p_distancia_declarada_km: contexto.kmSalvo === null ? preparacao.km : null,
      p_confirma_retorno: contexto.retornoAoCc && contexto.confirmacaoRetorno
    }
  };
}
