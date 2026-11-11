# Consolidacao da Folga de Campo — implantacao sem interrupcao
**Status: preparacao, nao executar.** Escopo exclusivo RO Passagens. Este documento substitui a leitura isolada dos rascunhos 01–07, que permanecem como referencia historica e NAO devem ser executados em sequencia.

## Invariante principal
Ate a publicacao autorizada, toda solicitacao de Folga de Campo deve continuar sendo criada pela RPC existente `public.ro_criar_solicitacao_com_aprovador`, com as validacoes, bloqueios e aprovacoes atuais. Nenhuma alteracao de codigo, schema, grants, trigger ou funcao no Supabase de producao durante a preparacao. A branch GitHub nao pode ser promovida automaticamente.

## Correcoes identificadas nos rascunhos
1. A etapa 05 grava snapshot apos INSERT: **invalido** porque a trigger BEFORE INSERT ja calcula o ciclo. Substituir por calculo e snapshot dentro do BEFORE INSERT, obtidos de episodio interno validado na mesma transacao.
2. A etapa 04 usa lock por funcionario e altera episodio antes de chamar a RPC existente. Essa ordem so e aceitavel se toda a transacao reverter em erro e a autorizacao para criar em nome do funcionario for verificada corretamente.
3. A etapa 01 usa indice de um episodio ativo por funcionario: isso e historico **interno do RO**, nao altera lotacao oficial em `funcionarios` ou `obras`.
4. A etapa 02 pressupoe que a selecao do CC significa mudanca de episodio; confirmar somente ao salvar a solicitacao, nao ao mudar o combobox.
5. A etapa 03 deve validar coordenador/gerente em `user_roles` e equipe RO ativa via `ro_is_operador_ativo`, sem restricao de CC. Revisar tambem status de usuario ativo.
6. A etapa 06 usa `data_ida` da ultima folga aprovada/dispensada e finalizada, nunca a data prevista anterior; nao recalcular snapshots antigos.
7. A etapa 07 alerta corretamente que GUC (`set_config`) nao e controle de autorizacao. Nao confiar nela sem vinculo verificavel ao episodio e a solicitacao.

## Estrategia de implantacao sem bloquear solicitacoes
**Fase A — preparacao isolada:** desenvolver e testar arquivos SQL e frontend na feature branch; zero alteracoes em producao.
**Fase B — instalacao aditiva (somente apos backup e autorizacao):** criar tabelas internas, colunas opcionais e funcoes privadas, com RLS/grants fechados; nao substituir triggers nem RPC antiga. Manter frontend de producao intocado. Validar que solicitacoes legadas ainda sao aceitas.
**Fase C — ativacao coordenada (somente apos testes e autorizacao):** atualizar validacao do ciclo e auditoria, implantar RPC transacional e frontend compatível. O fluxo legado continua funcionando ate o instante da ativacao. Fazer verificacao de compatibilidade de chamadas antigas, pois trocar trigger antes do frontend pode bloquear pedidos.
**Fase D — observacao/rollback:** validar criacao real com conta de teste autorizada e monitorar erros; plano de reversao de funcoes e frontend previamente testado. Nao prometer rollback sem perda de dados; snapshots ja gravados exigem avaliacao.

## Contrato do backend consolidado (proposto)
- `ro_private.regime_folga_km(km)`: regra pura, intervalos 7/14/45/90.
- `ro_private.contexto_folga_campo(funcionario,cc)`: leitura do episodio interno e ultima folga valida, com camada publica autenticada ainda a implementar.
- `ro_private.preparar_episodio_folga(...)`: dentro da transacao de criacao, com lock e validacao de retorno.
- `ro_private.corrigir_distancia_folga(...)`: somente roles autorizadas, com justificativa e auditoria.
- `public.ro_criar_folga_campo_com_distancia(...)`: orquestra preparacao + criacao pela RPC atual; deve validar permissao e disponibilizar snapshot antes do BEFORE INSERT. **O rascunho 05 nao atende ainda esse contrato.**
- Trigger de validacao: se houver contexto validado da nova RPC, usar km/episodio e snapshot; se nao houver, preservar caminho legado durante fase de compatibilidade. Nao aceitar contexto forjado do cliente.
- Trigger de auditoria: ler snapshot quando presente; para pedidos legados, preservar comportamento historico sem reinterpretar registros.
- Apos estabilizacao, decidir se o caminho legado para novas Folgas sera descontinuado; nao fazer isso durante a ativacao inicial.

## Matriz minima de testes antes de qualquer implantacao
1. Folga legada continua sendo criada enquanto o codigo novo nao esta publicado.
2. Primeira Folga: km obrigatorio apenas no novo fluxo.
3. Mesmo CC reutiliza km; novo CC exige km; retorno ao CC exige confirmacao.
4. Mudanca de CC nao altera lotacao oficial e nao altera Folgas anteriores.
5. Ciclo usa ultima `data_ida` aprovada/dispensada e finalizada.
6. Antecipacao exige justificativa, aprovacao RO e preserva bloqueio de compra.
7. Erro na criacao reverte episodio, auditoria e snapshot.
8. Correcoes globais permitidas a coordenador/gerente/RO ativo, negadas aos demais.
9. Chamadas simultaneas para mesmo funcionario nao criam dois episodios ativos.
10. UPDATE de status/aprovacao nao recalcula o regime de pedidos pendentes.
11. Usuarios e aplicativos existentes (Obras Control e alocacao oficial) nao sao alterados.
12. Validar migracao/rollback e garantir que a fase aditiva nao muda o fluxo atual.

## Bloqueios
Ainda faltam a implementacao SQL final e testes de banco com autorizacao real. Nao executar os rascunhos 01–07, nem o wrapper 05, em producao. A consolidacao e um contrato tecnico, nao uma migracao pronta.
