# Comparacao com as funcoes reais de producao (somente leitura)

Consulta realizada no projeto Supabase Portal TanksBR em 11/11/2026. Nenhum SQL de escrita executado.

## Confirmacoes

- `ro_criar_solicitacao_com_aprovador` valida aprovador, dispensa, autoaprovacao, atualiza status de aprovacao, registra historico e notifica. O wrapper 09 preserva a chamada original.
- `ro_criar_solicitacao_colaborador_validada_pre_operacional` usa o ID fornecido no JSON ou gera UUID. A exigencia de ID explicito do wrapper 09 e compatível com o frontend atual.
- `ro_validar_ciclo_folga_campo` ja faz lock de funcionario, impede folga futura duplicada, valida justificativa, invalida aprovacao de antecipacao se dados mudarem e marca recusa.
- `ro_auditar_ciclo_folga_campo` emite os eventos `ciclo_folga_calculado` e `ciclo_folga_avancado`. Manter nomes e chaves legadas no JSON de detalhes.
- `ro_obter_ciclo_folga_funcionario` usa data de Sao Paulo, calcula proxima previsao por +90 e nao filtra aprovacao. A nova regra so pode ser aplicada ao novo fluxo ate migracao segura.
- O frontend atual ainda chama a RPC antiga; o novo fluxo permanece desativado.

## Correcoes e riscos concretos

1. **Data local**: arquivo 10 atualizado para usar `(now() at time zone 'America/Sao_Paulo')::date` como no codigo atual.
2. **Atualizacao de status**: arquivo 10 agora preserva previsao e antecipacao em UPDATE sem alteracao dos parametros de calculo. Testar especificamente transicao `solicitada -> finalizada` e `solicitada -> recusada`.
3. **Auditoria**: arquivo 11 preserva nomes de eventos e campos anteriores e adiciona intervalo/distancia; contudo, sua substituicao integral ainda depende de testes.
4. **Historico**: a regra nova deve buscar a ultima folga `finalizada` e com `aprovacao_status` em `aprovada`/`dispensada`, ordenada por `data_ida`. Nao alterar retrospectivamente snapshots.
5. **Seguranca de snapshots**: a guarda BEFORE UPDATE do arquivo 11 e indispensavel porque o trigger atual nao e acionado quando apenas colunas de km mudam.
6. **Contexto privado**: a tabela do arquivo 08 e temporaria por solicitacao, removida na mesma transacao; ainda falta garantir que nenhum caminho alternativo a RPC privilegiada possa inserir linhas.
7. **Risco de auto-referencia**: quando um pedido novo e finalizado, a consulta de ciclo nao deve escolher o proprio pedido como ancora. A rotina de criacao exclui `new.id`; testar todos os casos.
8. **Colaborador privado**: o wrapper 09 explicitamente recusa `colaborador_id`; confirmar regra de negocio antes de ativar para esse publico.
9. **Falha no frontend**: a interface do adaptador `planejarRotaCriacao` so devolve argumentos extras; `p_solicitacao` e `p_documentos` precisam ser combinados na chamada da RPC nova. Nao habilitar antes dessa integracao.
10. **Integridade e concorrencia**: os drafts 04/09 precisam de testes de rollback e corrida; `preparar_episodio_folga` adquire o mesmo advisory lock do trigger. Confirmar ausencia de deadlocks com outros gatilhos.
11. **Novo fluxo ainda incompleto**: falta RPC segura de consulta funcionario/CC, componente conectado ao formulario e migracao consolidada testavel. Os arquivos 01-11 nao devem ser executados em sequencia.

## Proximas verificacoes tecnicas

- Inspecionar corpo de `ro_criar_solicitacao_validada`, triggers e grants que alteram `obra_id` ou status.
- Implementar RPC de consulta segura e testes de compatibilidade isolados.
- Integrar o componente de quilometragem ao formulario com flag desligada.
- Construir migracao consolidada revisada; testar em banco local sem custos e sem dados de producao.
- Somente apos backup, aprovacao explicita e testes, considerar DDL no banco compartilhado.
