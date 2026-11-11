# Verificacao real de compatibilidade — Folga de Campo
Data: 2026-11-11. Projeto Supabase Portal TanksBR. **Somente leitura**. Nao foi executado DDL/DML.
## Funcoes consultadas diretamente no catalogo pg_proc
- public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb): chama ro_criar_solicitacao_colaborador_validada; valida aprovador, autoaprovacao e dispensa; atualiza aprovacao_status, insere historico e notifica.
- public.ro_validar_ciclo_folga_campo(): BEFORE INSERT/UPDATE; usa pg_advisory_xact_lock(hashtextextended(funcionario_id::text,904)), verifica ro_funcionario_possui_folga_futura_ativa, consulta ro_obter_ciclo_folga_funcionario, exige justificativa >=10 e invalida aprovacao anterior quando mudam campos relevantes.
- public.ro_auditar_ciclo_folga_campo(): AFTER INSERT/UPDATE; registra ciclo_folga_calculado e ciclo_folga_avancado; atualmente usa +90 na finalizacao.
- public.ro_criar_solicitacao_colaborador_validada(jsonb,jsonb): preserva validacao de viajante manual e delega a cadeia existente.

## Bloqueadores de ativacao encontrados
1. O wrapper 05 grava snapshot apos INSERT, portanto nao atende ao BEFORE INSERT.
2. O trigger atual recalcula ciclo ao mudar status; migracao deve preservar snapshots de pedidos anteriores.
3. O lock ja existe no trigger: nao introduzir nova ordem de locks que cause deadlock.
4. A compatibilidade do caminho legado deve ser mantida durante implantacao: se nao houver contexto validado de km, usar o comportamento antigo sem exigir distancia.
5. O contexto por GUC nao pode ser usado sozinho como prova de autorizacao, pois pode ser definido pelo cliente.
6. A atualizacao de aprovacao apos INSERT pode acionar outros triggers; revisar ordem e invariantes antes de migrar.
7. A auditoria atual usa +90 fixo, precisa ser alterada somente em ativacao coordenada.

## Testes bloqueantes de liberacao
- Chamada antiga ro_criar_solicitacao_com_aprovador para folga sem km continua permitida durante compatibilidade.
- Nova chamada sem km em CC novo falha e reverte tudo; chamada antiga nao falha por ausencia de km.
- Duplicidade futura permanece bloqueada nos dois caminhos.
- Antecipacao exige justificativa >=10 e aprovacao RO antes de compra.
- Mudanca de data/justificativa invalida aprovacao quando aplicavel.
- Aprovador e dispensa seguem as regras atuais.
- Falha em aprovador, duplicidade ou validacao reverte episodio, auditoria e solicitacao.
- Simultaneidade de dois pedidos para mesmo funcionario nao cria dois episodios ativos.
- Historico antigo e snapshots nao sao regravados ao finalizar pedido.
- Nenhum UPDATE em funcionarios/obras nem em sistemas de alocacao.
- Rollback de codigo/frontend mantem caminho antigo operacional.

## Status
Inspecao do catalogo: concluida. Testes SQL transacionais e de concorrencia: **nao executados**. Migracao final: **nao implementada**. Producao: **sem alteracoes**.
