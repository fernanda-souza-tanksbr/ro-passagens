import type { Funcionario } from "./types";

/** Identidade do passageiro, nunca o perfil de quem solicita. */
export function passageiroElegivelViagemAdministrativa(funcionario: Funcionario | null | undefined): boolean {
  if (!funcionario) return false;
  // Cadastro privado sem vínculo operacional com Obras Control.
  if (funcionario.funcionario_id !== funcionario.id) {
    return !funcionario.visivel_obras_control && funcionario.escopo_passagens === "restrito_ro";
  }
  // Cadastro restrito e não operacional, independentemente do cargo textual.
  return funcionario.visivel_passagens !== false && !funcionario.visivel_obras_control && funcionario.escopo_passagens === "restrito_ro";
}

export function motivoAdministrativoPermitido(motivo: string, funcionario: Funcionario | null | undefined): boolean {
  return motivo !== "viagem_administrativa" || passageiroElegivelViagemAdministrativa(funcionario);
}
