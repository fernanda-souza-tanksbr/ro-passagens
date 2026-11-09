import { regimePorDistancia, estadoQuilometragem } from "./folgaCampoRegimes";

type Props = {
  kmSalvo: number | null;
  retornoAoCc: boolean;
  kmInformado: string;
  confirmado: boolean;
  onKmChange: (value: string) => void;
  onConfirmChange: (value: boolean) => void;
};

/** Componente isolado: integrar somente quando a RPC de persistencia estiver pronta. */
export function FolgaCampoQuilometragem({ kmSalvo, retornoAoCc, kmInformado, confirmado, onKmChange, onConfirmChange }: Props) {
  const estado = estadoQuilometragem(kmSalvo, retornoAoCc);
  const km = estado === "informar" ? Number(kmInformado) : kmSalvo;
  const valido = estado === "informar" ? /^\d+$/.test(kmInformado) && Number.isSafeInteger(km) : km !== null;
  const regime = valido && km !== null ? regimePorDistancia(km) : null;
  const transporte = regime?.transporte === "aviao" ? "Avião" : regime?.transporte === "onibus" ? "Ônibus" : "Ônibus ou avião";
  return (
    <section aria-label="Quilometragem da Folga de Campo">
      {estado === "informar" ? (
        <label>
          Distância da residência ao centro de custo atual (km)
          <input type="number" min="0" step="1" value={kmInformado} onChange={(e) => onKmChange(e.target.value)} required />
        </label>
      ) : (
        <p>Distância registrada para este centro de custo: <strong>{kmSalvo} km</strong></p>
      )}
      {estado === "confirmar" && (
        <label>
          <input type="checkbox" checked={confirmado} onChange={(e) => onConfirmChange(e.target.checked)} required />
          Confirmo que esta distância continua correta para minha nova alocação neste centro de custo.
        </label>
      )}
      {regime && (
        <p>Transporte previsto: {transporte}. Intervalo de referência para antecipação: {regime.intervaloDias} dias.</p>
      )}
      {estado === "confirmar" && <p>Se a distância estiver incorreta, solicite a correção a um responsável autorizado antes de continuar.</p>}
    </section>
  );
}
