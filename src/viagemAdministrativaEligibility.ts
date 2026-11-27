import type { Funcionario } from "./types";

/**
 * Duas origens elegiveis para Viagem Administrativa:
 * - cadastro privado RO, sem vinculo operacional (regra original);
 * - funcionario restrito_ro cadastrado diretamente em funcionarios,
 *   ativo no RO e explicitamente nao operacional.
 *
 * O banco faz a validacao definitiva. A UI nao pode rejeitar um passageiro
 * permitido pelo trigger por causa da origem de seu cadastro.
 */
export function passageiroElegivelViagemAdministrativa(funcionario: Funcionario | null | undefined): boolean {
  if (!funcionario) return false;
  const semVinculoOperacional = funcionario.visivel_obras_control === false;
  if (!semVinculoOperacional) return false;

  const cadastroPrivado = funcionario.funcionario_id !== funcionario.id;
  if (cadastroPrivado) return true;

  return funcionario.visivel_passagens === true &&
    funcionario.escopo_passagens === "restrito_ro";
}

export function motivoAdministrativoPermitido(motivo: string, funcionario: Funcionario | null | undefined): boolean {
  return motivo !== "viagem_administrativa" || passageiroElegivelViagemAdministrativa(funcionario);
}
