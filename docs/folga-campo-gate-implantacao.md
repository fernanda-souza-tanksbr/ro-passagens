# Gate de implantacao — Folga de Campo por distancia

Atualizado em 12/11/2026. **Nao executar SQL em producao sem autorizacao.**

## Modelo aprovado

As regras de km contemplam funcionarios gerais e colaboradores privados, inclusive sem vinculo ao cadastro geral. Vinculos validos compartilham a identidade de funcionario; sem vinculo usa-se a chave privada. Nenhuma alteracao no cadastro oficial ou Obras Control.

## Evidencias da branch

- `docs/implantacao/folga-campo-etapa-a-aditiva-RASCUNHO.sql`: estruturas, funcoes, tabela privada de ativacao com `ativo=false`, RPCs novas sem grants.
- `docs/implantacao/folga-campo-etapa-b-coordenada-RASCUNHO.sql`: substituicao coordenada de funcoes de ciclo/auditoria, mantendo o fluxo antigo enquanto gate desligado.
- `tests/sql/folgaCampoPrivados.sql`: privado sem vinculo, vinculado, historico misto, duplicidade, retorno e correcao auditada.
- `tests/sql/folgaCampoAtivacao.sql`: quando gate e ligado no PostgreSQL ficticio, a RPC legada nao consegue criar Folga sem km; outros motivos continuam.
- `tests/sql/folgaCampoConcorrencia.sh`: segunda transacao bloqueada e revertida ao tentar nova Folga futura ativa.
- `tests/sql/folgaCampoGrants.sql`: RLS habilitado e novas RPCs indisponiveis aos papeis anon/authenticated.
- `.github/workflows/validar-folga-campo.yml`: testes, TypeScript e build Vite sem deploy.

## Condicoes ainda bloqueantes para publicacao

1. A aprovacao, notificacao, compras, documentos, papeis e demais gatilhos existentes sao simulados parcialmente no PostgreSQL temporario; falta validacao end-to-end com a cadeia real.
2. As RPCs novas seguem com EXECUTE revogado para clientes. Os grants finais precisam ocorrer junto com o rollout autorizado.
3. O frontend esta integrado sob constante fixa `NOVO_FLUXO_FOLGA_ATIVO=false`; a ativacao exige teste da versao de referencia e deploy explicitamente autorizado.
4. Nenhum backup de preimplantacao ou teste de recuperacao especifico para a mudanca foi feito nesta etapa. Confirmar antes de DDL.
5. Os arquivos de implantacao sao **rascunhos**, nao migracoes liberadas. O pacote de `tests/sql` jamais deve ser usado em producao.
6. Viajantes puramente manuais (sem funcionario ou cadastro privado) nao estao incluidos no novo modelo; nao houve casos na amostra consultada.

## Ordem de rollout proposta (sujeita a aprovacao)

Backup + captura das funcoes e triggers vigentes; fase A; fase B; testes de compatibilidade legada; deploy da UI com controle explicito; grants minimos; habilitacao da regra obrigatoria no banco em passo coordenado; monitoramento. Uma reversao deve desabilitar o gate antes de restabelecer o app antigo, revogar grants e preservar tabelas/snapshots para auditoria.

## Regra de seguranca

Nao alterar `funcionarios`, `obras`, lotacao oficial, Obras Control ou dados historicos. Corrigir km apenas no episodio vigente, por coordenadores, gerentes ou operadores RO ativos, com justificativa e auditoria.
