/** Exporta exatamente as linhas visíveis, sem recalcular valores ou filtros. */
export type CsvLinhaFinanceira = { centro_custo_id: string | null; compradas: number; abertas: number; imprevistos: number; valor_total: number };
export function montarCsvCentrosCusto<T extends CsvLinhaFinanceira>(linhas: T[], label: (linha: T) => string, colaboradoresPorCentro: ReadonlyMap<string, readonly string[]>, mostrarNomes: boolean): string {
  const cabecalho = ["Centro de custo","Funcionários","Compradas","Em aberto","Imprevistos/complementares","Valor total"];
  const escape = (value: string | number) => `"${String(value).replaceAll('"', '""')}"`;
  const registros = linhas.map((linha) => [label(linha),mostrarNomes ? (colaboradoresPorCentro.get(linha.centro_custo_id || "sem-centro") || []).join(", ") : "",linha.compradas,linha.abertas,linha.imprevistos,Number(linha.valor_total).toFixed(2)]);
  return `\uFEFF${[cabecalho,...registros].map((row)=>row.map(escape).join(";")).join("\r\n")}`;
}
