import type { AddressAccess } from "./addressAccess";
import { podeAcessarAreasGerais } from "./addressAccess";

/** Until access for this exact session is resolved, protected routes must wait. */
export function reportRouteDecision(sessionUserId: string | null, readyUserId: string | null, access: AddressAccess & { canViewAll: boolean }): "pending" | "allowed" | "denied" {
  if (!sessionUserId || readyUserId !== sessionUserId) return "pending";
  return podeAcessarAreasGerais(access) ? "allowed" : "denied";
}
