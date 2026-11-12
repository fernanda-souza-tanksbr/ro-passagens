# Folga de Campo — colaboradores privados contemplados

Decisao funcional aprovada em 12/11/2026: **as mesmas faixas de distancia, antecipacao e regras de CC valem para funcionarios do cadastro geral e colaboradores privados, com ou sem vinculo a funcionario.**

## Referencia da producao (consulta agregada somente leitura)

Nas 76 Folgas de Campo nao excluidas consultadas, 23 usam cadastro privado: 20 vinculadas ao cadastro geral e 3 sem vinculo. Nao foi encontrado viajante com nome manual nessa amostra.

## Modelo implementado na branch de desenvolvimento

- A identidade canonica e `funcionario_id` quando o colaborador privado possui vinculo valido a `funcionarios`; sem vinculo, a identidade e `colaborador_id`.
- `ro_folga_alocacoes` e contexto transacional exigem **exatamente uma** dessas identidades, com chaves e indices exclusivos por identidade ativa.
- A solicitacao conserva seu `colaborador_id` real, mesmo quando compartilha historico com o funcionario vinculado.
- A consulta valida que o cadastro privado existe e esta ativo e rejeita incompatibilidade entre o funcionario informado e o vinculo real.
- A troca de CC e gravada somente na mesma transacao da criacao bem-sucedida; correcoes autorizadas preservam snapshots antigos.
- A consulta e a criacao ainda nao estao publicadas no Supabase, e o frontend mantem `NOVO_FLUXO_FOLGA_ATIVO=false`.

## Evidencia de testes isolados

`tests/sql/folgaCampoPrivados.sql` cobre privado sem vinculo, vinculado com historico misto, recusa de colaborador inativo, duplicidade, retorno confirmado, correcao auditada e tentativa de forjar vinculo. `tests/folgaCampoPrivadosFrontend.test.ts` cobre a identidade na consulta e montagem da RPC.

`tests/sql/folgaCampoAtivacao.sql` verifica que, quando a regra estiver ativada no banco, a RPC antiga rejeita Folga sem km mas continua aceitando outros motivos.

## Limite ainda existente

Viajante com nome informado manualmente (`viajante_nome_informado`) nao equivale a colaborador privado cadastrado. Nao possui identidade persistida adequada a episodio e continua recusado pelo wrapper novo. O tratamento desse modo exige decisao e desenho separados se for necessario solicitar Folga de Campo para viajantes exclusivamente manuais. Nenhuma migracao ou atualizacao de registros historicos foi executada.

**Producao inalterada.** Os scripts permanecem rascunhos sujeitos a backup, homologacao e autorizacao.
