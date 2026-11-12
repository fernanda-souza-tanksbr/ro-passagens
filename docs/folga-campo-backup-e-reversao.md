# Backup, ativacao controlada e reversao — Folga de Campo

**Plano para futura autorizacao. Nenhuma instrucao deste arquivo foi executada na producao.**

## Antes de qualquer alteracao no Supabase compartilhado

- Identificar commit/deploy de referencia no GitHub e Vercel, conferindo o estado atual da producao.
- Confirmar backup manual verificavel do PostgreSQL, integridade das solicitacoes e possibilidade de restauracao. Nao modificar Storage ou tabelas oficiais.
- Exportar com `pg_get_functiondef` os corpos vigentes de `ro_validar_ciclo_folga_campo` e `ro_auditar_ciclo_folga_campo`.
- Exportar com `pg_get_triggerdef` todos os triggers ligados a `ro_passagem_solicitacoes`, mais grants/RLS existentes e quantidade de Folgas por identidade.
- Revisar potenciais mudancas de schema desde os testes isolados.

## Implantacao por etapas, somente com aprovacao explicita

1. **A aditiva:** criar estruturas e RPCs sem grants; `ro_private.folga_configuracao.ativo=false` preserva o fluxo antigo.
2. **B coordenada:** atualizar as duas funcoes existentes e adicionar protecao de snapshot numa transacao controlada. Gate continua desligado. Conferir todas as operacoes legadas, inclusive privados.
3. **Ativacao separada:** publicar interface aprovada, conceder EXECUTE somente a authenticated nas RPCs publicas validadas e habilitar a configuracao `novo_fluxo_distancia`. O gatilho passa a rejeitar Folga de Campo por RPC antiga sem km, preservando outros motivos.
4. Monitorar cadastro, retorno de CC, historico, aprovacoes, notificacoes, compra, correcao autorizada e erros de API.

## Reversao imediata, preservando dados

1. Se houver incidentes, desabilitar `ro_private.folga_configuracao.ativo` e, conforme necessario, voltar o deploy Vercel a versao de referencia.
2. Revogar grants de EXECUTE das RPCs novas para impedir uso indevido.
3. Se for preciso reverter a etapa B, restaurar transacionalmente os corpos originais exportados das funcoes, **sem** apagar colunas de snapshot ou tabelas com dados de novos episodios. Avaliar impacto da guarda de snapshots.
4. Preservar todos os episodios, trilhas de auditoria e solicitacoes criados no intervalo; nunca apagar para simplificar rollback.
5. Confirmar que o fluxo tradicional, outras solicitacoes, obras e notificacoes continuam intactos.

## Dependencias pendentes

A cadeia de aprovacao real, notificacoes e demais triggers foi analisada, mas nao integralmente reproduzida em testes de ponta a ponta. Os grants de ativacao e a publicacao sao passos separados, nao autorizados nesta fase. Corrigir km pelo sistema exige superficie de UI apropriada para operadores habilitados e auditoria.

Viajantes com nome puramente manual nao foram solicitados para cobertura e nao sao colaboradores privados cadastrados. Estender futuramente exige identidade persistente.

**O novo fluxo continua desativado.**
