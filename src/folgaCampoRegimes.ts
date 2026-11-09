export function regimePorDistancia(km: number) {
  if (!Number.isSafeInteger(km) || km < 0) throw new Error("DISTANCIA_INVALIDA");
  if (km <= 200) return { faixa: "ate_200", intervaloDias: 7, transporte: "onibus" };
  if (km <= 600) return { faixa: "201_600", intervaloDias: 14, transporte: "onibus" };
  if (km <= 800) return { faixa: "601_800", intervaloDias: 45, transporte: "onibus_ou_aviao" };
  if (km <= 1500) return { faixa: "801_1500", intervaloDias: 90, transporte: "onibus_ou_aviao" };
  return { faixa: "acima_1500", intervaloDias: 90, transporte: "aviao" };
}
export function adicionarDiasIso(data: string, dias: number): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data) || !Number.isSafeInteger(dias)) throw new Error("DATA_INVALIDA");
  const d = new Date(data + "T00:00:00.000Z");
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== data) throw new Error("DATA_INVALIDA");
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}
export type FolgaAnterior = { dataIda: string; status: string; aprovacaoStatus: string };
export function ultimaFolgaValida(folgas: readonly FolgaAnterior[]): FolgaAnterior | null {
  return folgas.filter(f => f.status === "finalizada" && ["aprovada", "dispensada"].includes(f.aprovacaoStatus))
    .reduce<FolgaAnterior | null>((a, f) => !a || f.dataIda > a.dataIda ? f : a, null);
}
export function calcularCicloFolga(folgas: readonly FolgaAnterior[], km: number, dataSolicitada: string) {
  const regime = regimePorDistancia(km);
  const anterior = ultimaFolgaValida(folgas);
  const proximaPrevista = anterior ? adicionarDiasIso(anterior.dataIda, regime.intervaloDias) : null;
  adicionarDiasIso(dataSolicitada, 0);
  return { regime, ultimaSaida: anterior?.dataIda ?? null, proximaPrevista, antecipada: proximaPrevista !== null && dataSolicitada < proximaPrevista };
}
export function estadoQuilometragem(kmSalvo: number | null, retornoAoCc: boolean) {
  if (kmSalvo === null) return "informar";
  regimePorDistancia(kmSalvo);
  return retornoAoCc ? "confirmar" : "reutilizar";
}
