import { useCallback, useEffect, useState, type FormEvent } from "react";
import type { Access } from "./accessCache";
import type { Solicitacao } from "./types";
import { supabase } from "./supabase";
import { consultarContextoFolga } from "./folgaCampoConsulta";
import { regimePorDistancia } from "./folgaCampoRegimes";
import { podeExibirCorrecaoDistancia, validarCorrecaoDistancia } from "./folgaCampoCorrecao";
import type { ContextoDistanciaServidor } from "./folgaCampoContextoServidor";

type Props = {
  solicitacao: Pick<Solicitacao,
    "id" | "motivo" | "status" | "aprovacao_status" | "funcionario_id" | "colaborador_id"
    | "obra_id" | "folga_alocacao_id" | "folga_distancia_km" | "folga_intervalo_dias">;
  access: Access;
};

/**
 * Corrige SOMENTE a quilometragem da alocação vigente, por RPC auditada.
 * O backend decide a autorização; nenhum UPDATE direto ou alteração de snapshot é feito aqui.
 */
export function CorrecaoQuilometragemFolga({ solicitacao, access }: Props) {
  const [contexto, setContexto] = useState<ContextoDistanciaServidor | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [editando, setEditando] = useState(false);
  const [novoKm, setNovoKm] = useState("");
  const [justificativa, setJustificativa] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState("");
  const [sucesso, setSucesso] = useState("");

  const permitido = podeExibirCorrecaoDistancia(access);
  const valido = permitido && solicitacao.motivo === "folga_campo"
    && Boolean(solicitacao.folga_alocacao_id && solicitacao.obra_id)
    && Boolean(solicitacao.funcionario_id || solicitacao.colaborador_id);

  const consultar = useCallback(async () => {
    if (!solicitacao.obra_id) throw new Error("Centro de custo indisponível.");
    return consultarContextoFolga(
      solicitacao.funcionario_id,
      solicitacao.obra_id,
      true,
      async args => supabase.rpc("ro_consultar_contexto_distancia_folga", args),
      solicitacao.colaborador_id ?? null,
    );
  }, [solicitacao.funcionario_id, solicitacao.colaborador_id, solicitacao.obra_id]);

  useEffect(() => {
    if (!valido) return;
    let cancelado = false;
    setCarregando(true);
    setErro("");
    void consultar()
      .then(resultado => { if (!cancelado) setContexto(resultado); })
      .catch(() => { if (!cancelado) setErro("Não foi possível consultar o cadastro de distância. Tente novamente mais tarde."); })
      .finally(() => { if (!cancelado) setCarregando(false); });
    return () => { cancelado = true; };
  }, [valido, consultar]);

  if (!valido) return null;

  const ativaNoCc = contexto?.estado === "reutilizar" && contexto.distancia_km !== null;
  const kmAtual = ativaNoCc ? contexto.distancia_km : null;
  const intervalo = kmAtual !== null ? regimePorDistancia(kmAtual).intervaloDias : null;
  const intervaloSolicitacao = solicitacao.folga_intervalo_dias;
  const kmSolicitacao = solicitacao.folga_distancia_km;

  async function salvar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!solicitacao.folga_alocacao_id || !ativaNoCc || kmAtual === null || enviando) return;
    setErro("");
    setSucesso("");
    let entrada;
    try {
      entrada = validarCorrecaoDistancia(novoKm, justificativa, kmAtual);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Informe valores válidos.");
      return;
    }
    setEnviando(true);
    try {
      // Segurança: valida o contexto novamente antes de alterar a alocação.
      const antes = await consultar();
      if (antes?.estado !== "reutilizar" || antes.distancia_km !== kmAtual) {
        throw new Error("A distância ou a alocação foi modificada. Atualize a página antes de continuar.");
      }
      const { data, error } = await supabase.rpc("ro_corrigir_distancia_folga", {
        p_alocacao_id: solicitacao.folga_alocacao_id,
        p_nova_distancia_km: entrada.km,
        p_justificativa: entrada.justificativa,
      });
      if (error) throw new Error(error.message || "Não foi possível salvar a correção.");
      // A RPC devolve o ID e os dois valores; não aceitar retorno inesperado.
      const resposta = data as { alocacao_id?: string; distancia_anterior_km?: number; distancia_nova_km?: number } | null;
      if (resposta?.alocacao_id !== solicitacao.folga_alocacao_id
        || resposta?.distancia_anterior_km !== kmAtual
        || resposta?.distancia_nova_km !== entrada.km) {
        throw new Error("A resposta da correção não corresponde ao esperado. Verifique o cadastro antes de tentar novamente.");
      }
      const depois = await consultar();
      if (depois?.estado !== "reutilizar" || depois.distancia_km !== entrada.km) {
        throw new Error("A correção foi enviada, mas a consulta de confirmação não retornou a nova distância. Atualize a página antes de tentar novamente.");
      }
      setContexto(depois);
      setEditando(false);
      setNovoKm("");
      setJustificativa("");
      setSucesso("Quilometragem da alocação ativa corrigida e conferida. As solicitações já criadas mantêm o histórico original.");
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Não foi possível concluir a correção.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <section className="card detail" aria-label="Correção da quilometragem da Folga de Campo">
      <h2>Quilometragem da Folga de Campo</h2>
      <p>Distância rodoviária entre o centro de custo atual e a cidade de residência do funcionário — não entre o alojamento e a obra.</p>
      {carregando && <p>Consultando a alocação atual...</p>}
      {erro && <p className="error" role="alert">{erro}</p>}
      {sucesso && <p className="alert" role="status">{sucesso}</p>}
      {!carregando && contexto && (
        <>
          <p>Distância da solicitação: <strong>{kmSolicitacao ?? "Não registrada"}{kmSolicitacao !== null && kmSolicitacao !== undefined ? " km" : ""}</strong>
            {intervaloSolicitacao ? ` (regime de ${intervaloSolicitacao} dias)` : ""}.
          </p>
          {ativaNoCc ? (
            <>
              <p>Distância atual da alocação: <strong>{kmAtual} km</strong> (regime de {intervalo} dias).</p>
              {(kmSolicitacao !== null && kmSolicitacao !== undefined && kmSolicitacao !== kmAtual) &&
                <p className="alert">A distância da solicitação é histórica e difere da alocação atual. Não será alterada por esta correção.</p>}
              {!editando && <button type="button" className="btn secondary" onClick={() => { setEditando(true); setErro(""); setSucesso(""); }}>Corrigir quilometragem</button>}
              {editando && (
                <form onSubmit={salvar}>
                  <label>Nova distância do centro de custo até a cidade de residência (km)
                    <input type="number" min="0" step="1" inputMode="numeric" value={novoKm}
                      onChange={e => setNovoKm(e.target.value)} disabled={enviando} required />
                  </label>
                  <label>Justificativa da correção (obrigatória)
                    <textarea value={justificativa} onChange={e => setJustificativa(e.target.value)}
                      rows={3} minLength={10} disabled={enviando} required />
                  </label>
                  {/^\d+$/.test(novoKm.trim()) && Number.isSafeInteger(Number(novoKm.trim())) &&
                    <p>Regime previsto para {novoKm.trim()} km: {regimePorDistancia(Number(novoKm.trim())).intervaloDias} dias.</p>}
                  <p className="alert">Esta ação altera somente a alocação ativa e registra auditoria. Se a solicitação ainda está pendente, ela deve ser recusada e refeita para considerar o novo regime.</p>
                  <div className="actions">
                    <button type="submit" className="btn primary" disabled={enviando}>{enviando ? "Salvando..." : "Confirmar correção"}</button>
                    <button type="button" className="btn secondary" disabled={enviando} onClick={() => { setEditando(false); setErro(""); }}>Cancelar</button>
                  </div>
                </form>
              )}
            </>
          ) : (
            <p className="alert">Esta solicitação não corresponde a uma alocação ativa neste centro de custo. A correção deve ser realizada a partir de uma solicitação vinculada à alocação vigente.</p>
          )}
        </>
      )}
    </section>
  );
}
