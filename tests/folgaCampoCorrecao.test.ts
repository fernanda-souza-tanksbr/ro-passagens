import test from "node:test";
import assert from "node:assert/strict";
import { validarCorrecaoDistancia, podeExibirCorrecaoDistancia } from "../src/folgaCampoCorrecao.ts";

test("corrige 6 km para 1400 km, com justificativa e nova faixa", () => {
  assert.deepEqual(validarCorrecaoDistancia(" 1400 ", "Distância anterior entre alojamento e obra.", 6), {
    km: 1400, justificativa: "Distância anterior entre alojamento e obra.",
  });
});
test("recusa valor igual, fracionário, texto, negativo, inseguro ou justificativa insuficiente", () => {
  for (const entrada of ["6", "6.0", "-1", "1e4", "1.400", "1400km", "9007199254740993", ""]) {
    assert.throws(() => validarCorrecaoDistancia(entrada, "Justificativa adequada com detalhes", 6));
  }
  assert.throws(() => validarCorrecaoDistancia("1400", "curta", 6));
});
test("somente RO, coordenador e gerente visualizam painel", () => {
  assert.equal(podeExibirCorrecaoDistancia({ isRO: true, role: null }), true);
  assert.equal(podeExibirCorrecaoDistancia({ isRO: false, role: "coordenador" }), true);
  assert.equal(podeExibirCorrecaoDistancia({ isRO: false, role: "gerente" }), true);
  assert.equal(podeExibirCorrecaoDistancia({ isRO: false, role: "diretor" }), false);
  assert.equal(podeExibirCorrecaoDistancia({ isRO: false, role: null }), false);
});
