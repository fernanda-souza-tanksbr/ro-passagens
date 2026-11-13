import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  // Teste exclusivamente em servidor local com dados ficticios.
  await page.route("**/*", route => {
    const url = new URL(route.request().url());
    if (url.hostname !== "127.0.0.1" && url.hostname !== "localhost") return route.abort();
    return route.continue();
  });
  await page.goto("http://127.0.0.1:8008/");
  await expect(page.getByText("AMBIENTE FICTÍCIO · SEM SUPABASE")).toBeVisible();
});

test("limites de quilometragem e meios de transporte", async ({ page }) => {
  const variants = [
    [0, "0–200 km", "Rodoviário", "7 dias"],
    [200, "0–200 km", "Rodoviário", "7 dias"],
    [201, "201–600 km", "Rodoviário", "14 dias"],
    [600, "201–600 km", "Rodoviário", "14 dias"],
    [601, "601–800 km", "Rodoviário ou aéreo", "45 dias"],
    [800, "601–800 km", "Rodoviário ou aéreo", "45 dias"],
    [801, "801–1.500 km", "Rodoviário ou aéreo", "90 dias"],
    [1500, "801–1.500 km", "Rodoviário ou aéreo", "90 dias"],
    [1501, "Acima de 1.500 km", "Aéreo", "90 dias"]
  ] as const;
  for (const [km, band, transport, days] of variants) {
    await page.locator("#km").fill(String(km));
    await expect(page.locator("#summary-band")).toHaveText(band);
    await expect(page.locator("#summary-transport")).toHaveText(transport);
    await expect(page.locator("#summary-days")).toHaveText(days);
  }
});

test("primeira solicitacao sem historico e envio apenas ficticio", async ({ page }) => {
  await expect(page.locator("#summary-early")).toHaveText("Não");
  await page.locator("#approver").selectOption("coord");
  await page.locator("#submit").click();
  await expect(page.locator("#result")).toContainText("nenhuma gravação realizada");
  await expect(page.locator("#result")).toContainText("ro_criar_folga_campo_com_distancia");
});

test("permanencia reutiliza km, mudanca pede nova distancia, retorno exige confirmacao", async ({ page }) => {
  await page.locator("#scenario").selectOption("same");
  await expect(page.locator("#km-input-wrap")).toBeHidden();
  await expect(page.locator("#km-saved")).toContainText("420 km");
  await page.locator("#scenario").selectOption("move");
  await expect(page.locator("#km-input-wrap")).toBeVisible();
  await page.locator("#scenario").selectOption("return");
  await expect(page.locator("#confirm-wrap")).toBeVisible();
  await page.locator("#approver").selectOption("coord");
  await page.locator("#submit").click();
  await expect(page.locator("#alert")).toContainText("Confirme a distância");
  await page.locator("#confirm").check();
  await page.locator("#submit").click();
  await expect(page.locator("#result")).toContainText("nenhuma gravação realizada");
});

test("colaboradores privados com e sem vinculo selecionados sem obter dados reais", async ({ page }) => {
  await page.locator("#scenario").selectOption("private");
  await expect(page.locator("#employee")).toHaveValue("private");
  await expect(page.locator("#summary-transport")).toHaveText("Aéreo");
  await page.locator("#scenario").selectOption("linked");
  await expect(page.locator("#employee")).toHaveValue("linked");
  await expect(page.locator("#summary-days")).toHaveText("45 dias");
});

test("antecipacao exige justificativa, preserva aprovacao e bloqueia compra pendente", async ({ page }) => {
  await page.locator("#scenario").selectOption("early");
  await expect(page.locator("#summary-early")).toContainText("Sim");
  await page.locator("#approver").selectOption("coord");
  await page.locator("#submit").click();
  await expect(page.locator("#alert")).toContainText("justificativa");
  await page.locator("#just").fill("Motivo de antecipação fictício autorizado para análise");
  await page.locator("#submit").click();
  await expect(page.locator("#result")).toContainText("compra bloqueada enquanto pendente");
});

test("solicitacao futura existente impede duplicidade", async ({ page }) => {
  await page.locator("#scenario").selectOption("duplicate");
  await page.locator("#approver").selectOption("coord");
  await page.locator("#submit").click();
  await expect(page.locator("#alert")).toContainText("futura ativa");
  await expect(page.locator("#result")).toBeHidden();
});

test("correcao exige perfil e justificativa, snapshot anterior e preservado", async ({ page }) => {
  await page.locator("#approver").selectOption("coord");
  await page.locator("#submit").click();
  await expect(page.locator("#snapshot")).toContainText("200 km");
  await page.locator("#correct").click();
  await expect(page.locator("#correct-result")).toContainText("Acesso negado");
  await page.locator("#role").selectOption("manager");
  await page.locator("#correct").click();
  await expect(page.locator("#correct-result")).toContainText("Justificativa obrigatória");
  await page.locator("#correction-reason").fill("Revisão fictícia da distância pela gerência");
  await page.locator("#correct").click();
  await expect(page.locator("#correct-result")).toContainText("auditoria local");
  await expect(page.locator("#snapshot")).toContainText("200 km");
});

test("ferias e desligamento usam fluxo legado e nao exigem km", async ({ page }) => {
  for (const reason of ["ferias", "desligamento"]) {
    await page.locator("#reason").selectOption(reason);
    await expect(page.locator("#km-section")).toBeHidden();
    await page.locator("#approver").selectOption("coord");
    await page.locator("#submit").click();
    await expect(page.locator("#result")).toContainText("ro_criar_solicitacao_com_aprovador");
  }
});

test("sem origem de rede para Supabase, apenas servidor local", async ({ page }) => {
  const remoteRequests: string[] = [];
  page.on("request", request => {
    const url = new URL(request.url());
    if (!["127.0.0.1", "localhost"].includes(url.hostname)) remoteRequests.push(url.hostname);
  });
  await page.reload();
  await page.locator("#scenario").selectOption("private");
  await page.locator("#approver").selectOption("manager");
  await page.locator("#submit").click();
  expect(remoteRequests).toEqual([]);
  await expect(page.getByText("Somente simulação.")).toBeVisible();
});
