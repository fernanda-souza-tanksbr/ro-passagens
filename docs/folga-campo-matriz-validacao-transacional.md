# Preparacao para validacao transacional — Folga de Campo

**Estado:** projeto em desenvolvimento; scripts 01–12 em `docs/sql` sao rascunhos, nao migracoes aprovadas. **Nao executar em producao.**

## Ordem observada no Supabase

Leitura de `pg_trigger` confirmou que os triggers BEFORE com mesma operacao rodam em ordem alfabetica pelo nome. Na tabela `public.ro_passagem_solicitacoes`, os relevantes incluem `ro_exigir_fluxo_aprovacao_nova`, `ro_proteger_aprovacao_antecipacao`, `ro_proteger_campos_aprovacao`, `ro_validar_ciclo_folga_campo`, `ro_validar_nova_solicitacao` e `ro_validar_solicitacao_visibilidade`. Na proposta, `ro_guardar_snapshot_folga` executara antes de `ro_validar_ciclo_folga_campo` em UPDATE.

## Falha concreta identificada e corrigida

No rascunho 11, o trigger de auditoria continha um `elsif` que acessava `old.status`, mesmo podendo ser acionado por INSERT. A funcao foi corrigida para distinguir explicitamente `tg_op='INSERT'` de `tg_op='UPDATE'`, impedindo referencia a OLD na operacao sem registro anterior.

## Matriz de testes transacionais a executar em banco descartavel

| Cenario | Operacao | Resultado esperado |
|---|---|---|
| 1 | Criar Folga inicial com CC e km inteiro | Registro + episodio + snapshot, todos coerentes |
| 2 | Criar Folga sem km em CC nunca usado | Erro, zero solicitacoes e episodios adicionais |
| 3 | Criar Folga com dados invalidos | Rollback integral do episodio, contexto privado, auditoria e solicitacao |
| 4 | Criar Folga em CC atual | Reaproveita episodio e km anterior |
| 5 | Voltar a CC usado, sem confirmar | Erro e nenhum episodio de retorno |
| 6 | Voltar a CC usado, confirmado | Novo episodio com km anterior, sem alterar antigos |
| 7 | Tentar sobrescrever km via criacao normal | Recusa a substituicao |
| 8 | Duas criacoes concorrentes para mesmo funcionario | Advisory lock + regra de folga futura, sem episodios conflitantes |
| 9 | Finalizar solicitação | Nao modifica snapshot nem recalcula previsao original |
| 10 | Recusar solicitação | Preserva snapshot, trata antecipacao recusada |
| 11 | Alterar diretamente snapshot historico via UPDATE | Trigger de guarda recusa |
| 12 | Solicitacao legacy sem contexto | Mantem ciclo e auditoria anteriores |
| 13 | Usuario nao autenticado e CC nao permitido | Consulta e criacao negadas |
| 14 | Distancia proxima dos limites 200/201, 600/601, 800/801 e 1500/1501 | Intervalos 7,14,45,90 e transporte correto |
| 15 | Falha posterior em aprovador/notificacao | Sem episodio nem pedido persistido |
| 16 | Repetir UUID de solicitacao | Unicidade bloqueia; episodio anterior nao se altera |
| 17 | Usuario vinculado a colaborador privado | Deve seguir politica definida antes da liberacao; nao vazar distancia |
| 18 | Corrigir km por responsavel autorizado | Auditoria obrigatoria, passado imutavel |

## Bloqueios para montar fixture real

1. Os rascunhos 01–12 ainda nao sao migracao SQL consolidada; dependem de comparacao integral com funcoes de producao.
2. A RPC de consulta ainda tem EXECUTE revogado para `authenticated`; testar acessos antes de conceder.
3. A RPC de criacao tambem nao foi concedida, nem integrada ao envio do frontend.
4. O componente visual segue desativado; nenhum teste de ponta a ponta foi feito.
5. Falta banco PostgreSQL descartavel com schema minimo adequado. Nao usar dados reais nem ramificacao Supabase paga.
6. A auditoria do novo fluxo deve ser testada contra as demais validacoes e notificacoes ja existentes.

## Verificacoes automatizadas atuais

O teste `tests/folgaCampoTransacaoSqlDraft.test.ts` verifica estaticamente invariantes de ordem, bloqueio de acesso, OLD/NEW e rollback implícito. **Nao equivale a executar as transacoes no PostgreSQL.**

## Gate para producao

Backup verificavel + SQL revisado + teste PostgreSQL isolado aprovado + autorizacao explicita do usuario. Nao realizar DDL nem deploy antes dessas condicoes.
