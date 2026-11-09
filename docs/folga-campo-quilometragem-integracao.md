# Folga de Campo por quilometragem — plano de integração (sem deploy)

## Escopo
- Não criar página, aba ou módulo de quilometragem.
- O campo **Centro de custo atual** continua editável na nova solicitação.
- A distância é informada na primeira Folga da **alocação atual** do funcionário; em solicitações seguintes dessa alocação, reutilizar o valor.
- Ao trocar de CC, solicitar nova declaração. Ao retornar a um CC anterior, mostrar o valor histórico e exigir confirmação explícita; a confirmação pertence à nova alocação.
- Correções por perfis autorizados somente nos detalhes da solicitação, com registro de autor, data e valores antigo/novo. Corrigir apenas solicitações futuras.
- A distância declarada e o regime aplicável devem ser registrados como **snapshot** na solicitação para preservar o histórico.

## Regimes
| km | transporte | intervalo para antecipação |
|---|---|---|
| 0–200 | ônibus | 7 dias |
| 201–600 | ônibus | 14 dias |
| 601–800 | ônibus/avião | 45 dias |
| 801–1500 | ônibus/avião | 90 dias |
| >1500 | avião | 90 dias |

A duração do descanso e os dias úteis não devem ser inferidos do intervalo. O intervalo serve apenas para identificar antecipação.

## Cálculo
A próxima data de referência = `data_ida` da Folga mais recente com status finalizada **e** aprovação aprovada ou dispensada + intervalo da alocação/CC atual. Folgas pendentes, recusadas ou não finalizadas não viram âncora. Na primeira folga, não há antecipação. A mudança de CC não zera a última saída válida.

## Integração pendente (depende de banco)
1. Criar estrutura interna de alocações/declarações e trilha de auditoria, com políticas de acesso restritas. Uma chave apenas `funcionario_id + obra_id` é insuficiente para distinguir retorno ao mesmo CC.
2. Adicionar snapshot de km e regime à solicitação; garantir preenchimento e consistência na RPC de criação, sem confiar em valores arbitrários do cliente.
3. Estender a consulta `ro_obter_ciclo_folga_funcionario` com contexto de CC e distância, preservando compatibilidade dos demais consumidores.
4. Atualizar trigger `ro_validar_ciclo_folga_campo` e auditoria para âncora da saída real e intervalo variável.
5. No formulário `src/pages.tsx`, consultar estado de declaração e ciclo sempre que funcionário, motivo **ou obra_id** mudarem. Exibir entrada/confirmar/reutilizar km e regime automaticamente; exigir confirmação antes de enviar quando aplicável.
6. Adicionar correção de km na tela de detalhes existente com autorização verificada **no banco** e auditoria.
7. Garantir que solicitações pendentes preservem CC/regime da criação e que históricos não sejam recalculados.

## Segurança e implantação
Nenhuma migração deve ser executada no projeto Supabase de produção durante esta preparação. O teste local não prova integração com banco. Antes da implantação: backup verificado, revisão de RLS e grants, testes de autorização e regressão, plano de rollback e autorização explícita.

## Testes isolados
`npm test` executa os testes Node existentes. O arquivo `tests/folgaCampoRegimes.test.ts` cobre limites, datas, antecipação e estado da confirmação; acrescentar testes de integração após implementação da RPC.
