/** Interruptor de build explicitamente desligado por padrao.
 * Somente o deploy de producao autorizado deve usar o valor exato.
 * Previews com variaveis do Supabase de producao NAO devem usar esta chave.
 */
export function fluxoFolgaDistanciaHabilitado(valor: unknown): boolean {
  return valor === "C2_PRODUCAO_APROVADA";
}
