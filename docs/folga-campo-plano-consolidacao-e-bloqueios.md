# Revisao de consolidacao SQL - Folga de Campo

## Estado

Os arquivos 01 a 11 sao rascunhos de desenvolvimento. **Nao sao uma migracao unica executavel.** A atualizacao do arquivo 10 integrou a preservacao do ciclo em UPDATE de status, mas nao comprova equivalencia funcional com o trigger atual.

## Ordem de ativacao proposta (apos backup e autorizacao)

1. Validar FKs, tipos, grants e fluxo de funcionario/colaborador.
2. Criar estruturas aditivas 01 e contexto privado 08, com acesso restrito.
3. Instalar funcoes privadas de regime, episodio, calculo e autorizacao.
4. Substituir coordenadamente funcao de validacao de ciclo, auditoria e guarda de snapshot, sem perder regras do fluxo legado.
5. Instalar wrapper 09 com verificacao de snapshot e rollback.
6. Expor RPC de consulta de contexto e testar fluxo novo ainda desativado no frontend.
7. Testar permissao, concorrencia, cancelamento, aprovacao, recusa e historico.
8. Somente apos testes, habilitar novo fluxo no formulario e publicar.

## Bloqueios identificados

- O arquivo 10 ainda nao replica integralmente o corpo do trigger de producao; deve ser comparado linha a linha antes da troca.
- A auditoria do arquivo 11 deve preservar eventos e estrutura esperados pelos consumidores atuais.
- A guarda do arquivo 11 deve ser revisada em conjunto com a ordem alfabetica de execucao dos BEFORE triggers.
- A consulta de contexto de funcionario/CC e a integracao real do componente no formulario estao pendentes.
- O contrato da RPC precisa alinhar os argumentos efetivos do frontend, incluindo p_solicitacao e p_documentos.
- O ciclo deve considerar apenas ultima folga finalizada e aprovada/dispensada, sem recalcular pedidos historicos.
- Garantir que nenhuma mudanca atinja o Obras Control ou a alocacao oficial.
- Sem ambiente pago: testes de funcoes puras locais e, quando possivel, banco PostgreSQL isolado sem dados reais.

## Criterio de conclusao

Nao executar DDL de producao ate eliminar todos os bloqueios, validar rollback e obter autorizacao explicita.
