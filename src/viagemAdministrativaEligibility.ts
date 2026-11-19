import type { Funcionario } from "./types";

/**
 * A origem do cadastro é o critério primário: somente registros importados
 * em ro_funcionarios_enderecos_privados podem utilizar Viagem Administrativa.
 * Um vínculo a funcionario operacional do Obras Control torna o passageiro inelegível.
 * O catálogo canônico ro_catalogo_colaboradores_viagem devolve o id privado como
 * id e o vínculo operacional (se existir) como funcionario_id.
 */
export function passageiroElegivelViagemAdministrativa(funcionario: Funcionario | null | undefined): boolean {
  if (!funcionario) return false;
  const cadastroPrivado = funcionario.funcionario_id !== funcionario.id;
  const semVinculoOperacional = funcionario.visivel_obras_control === false;
  return cadastroPrivado && semVinculoOperacional &&
    funcionario.visivel_passagens === true && funcionario.escopo_passagens === "restrito_ro";
}

export function motivoAdministrativoPermitido(motivo: string, funcionario: Funcionario | null | undefined): boolean {
  return motivo !== "viagem_administrativa" || passageiroElegivelViagemAdministrativa(funcionario);
}
