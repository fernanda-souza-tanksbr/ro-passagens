/** Contrato estatico de release, sem acesso ao Supabase.
 * Abas anteriores a esta implementacao continuam protegidas pelo gatilho SQL da Etapa B.
 * O arquivo /folga-campo-release.json acompanha cada deploy e nao pode ser cacheado.
 */
export const VERSAO_FORMULARIO_FOLGA = 2;
export type ModoFolga = "legado" | "transicao" | "distancia";
export type ManifestoFolga = { modo: ModoFolga; versao_minima: number };
export type ResultadoVersao = { ok: true } | { ok: false; mensagem: string };
export const MENSAGEM_ATUALIZAR_FOLGA =
  "Existe uma nova versao do formulario de Folga de Campo. Atualize a pagina para continuar. Ferias, desligamentos e as demais solicitacoes permanecem disponiveis.";
export const MENSAGEM_TRANSICAO_FOLGA =
  "A Folga de Campo esta temporariamente suspensa para atualizacao do formulario. As demais solicitacoes continuam disponiveis.";
export const MENSAGEM_INDISPONIVEL_FOLGA =
  "Nao foi possivel verificar a versao do formulario de Folga de Campo. Tente novamente em instantes. As demais solicitacoes continuam disponiveis.";

export function avaliarManifestoFolga(
  manifesto: unknown, versao: number, clienteDistancia: boolean
): ResultadoVersao {
  if (!manifesto || typeof manifesto !== "object") return { ok:false, mensagem:MENSAGEM_INDISPONIVEL_FOLGA };
  const valor = manifesto as Partial<ManifestoFolga>;
  if (!Number.isSafeInteger(valor.versao_minima) || (valor.versao_minima ?? 0) < 1 ||
      !["legado","transicao","distancia"].includes(valor.modo ?? "")) {
    return { ok:false, mensagem:MENSAGEM_INDISPONIVEL_FOLGA };
  }
  if (valor.modo === "transicao") return { ok:false, mensagem:MENSAGEM_TRANSICAO_FOLGA };
  if (versao < valor.versao_minima! || (valor.modo === "distancia" && !clienteDistancia)) {
    return { ok:false, mensagem:MENSAGEM_ATUALIZAR_FOLGA };
  }
  if (valor.modo === "legado" && clienteDistancia) return { ok:false, mensagem:MENSAGEM_TRANSICAO_FOLGA };
  return { ok:true };
}

export async function checarVersaoFolga(versao: number, clienteDistancia = false): Promise<ResultadoVersao> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4000);
  try {
    const response = await fetch("/folga-campo-release.json", {
      cache:"no-store", credentials:"same-origin", signal:controller.signal,
      headers: { "Cache-Control":"no-cache" }
    });
    if (!response.ok || !response.headers.get("content-type")?.includes("application/json")) {
      return { ok:false, mensagem:MENSAGEM_INDISPONIVEL_FOLGA };
    }
    return avaliarManifestoFolga(await response.json(), versao, clienteDistancia);
  } catch {
    return { ok:false, mensagem:MENSAGEM_INDISPONIVEL_FOLGA };
  } finally { clearTimeout(timeout); }
}
