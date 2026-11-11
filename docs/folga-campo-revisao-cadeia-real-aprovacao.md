# Revisao da integracao com aprovacao real — Folga de Campo

Consultas de leitura ao Supabase `Portal TanksBR` em 11/11/2026. Nenhum DDL, DML ou deploy executado.

## Cadeia efetiva

1. `public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb)` valida usuario, isencao por perfil, candidato a aprovador e autoaprovacao limitada a coordenador.
2. Estabelece o contexto existente `ro.approval_creation` e chama `ro_criar_solicitacao_colaborador_validada`, que chega ao INSERT de solicitacao.
3. O BEFORE INSERT atual `ro_exigir_fluxo_aprovacao_nova` exige esse contexto legado; o novo wrapper 09 o preserva chamando a RPC atual, nao inserindo diretamente.
4. Depois do INSERT, a RPC legada estabelece `ro.aprovacao_rpc` e atualiza `aprovador_id`, `aprovacao_status` e data de aprovacao. `ro_proteger_campos_aprovacao` so permite essas mudancas por essa cadeia.
5. A RPC grava `ro_passagem_historico` e pode notificar a equipe. Toda excecao propagada no novo wrapper deve reverter episodio, auditoria e solicitacao.

## Pontos de compatibilidade encontrados

- A flag da nova Folga de Campo continua desligada no frontend; a RPC legada continua em uso.
- O novo wrapper 09 **nao pode substituir ou emular** o contexto `ro.approval_creation`; a RPC original e a unica autoridade.
- `ro_proteger_aprovacao_antecipacao` protege as mudancas no status da antecipacao e permite alterações coordenadas quando status/data/funcionario/motivo/justificativa mudam. Precisamos testar o BEFORE UPDATE em combinacao com o gatilho 10.
- A atual `ro_auditar_ciclo_folga_campo` usa +90; a versao proposta 11 preserva nomes dos eventos, mas altera o valor calculado para pedidos novos.
- A aprovacao ocorre **apos** o INSERT. No instante em que o BEFORE INSERT calcula a proxima folga, o pedido novo ainda nao esta aprovado; o gatilho deve consultar somente folgas anteriores finalizadas e aprovadas/dispensadas, excluindo o ID de NEW.
- A troca de CC ocorre no wrapper antes da RPC legada, mas todos os passos estao na mesma transacao: rollback de qualquer erro posterior deve desfazer o episodio.

## Limites dos testes atualmente aprovados

O PostgreSQL descartavel usa **mock** da RPC legada, dos candidatos a aprovador, da validacao de duplicidade e do catalogo de funcionarios. Por isso, sucesso nas execucoes 43073800311 e 43073800229 nao equivale a homologacao da cadeia real de aprovacao e notificacao.

## Proximos testes obrigatorios em ambiente isolado

1. Reproduzir com fidelidade a atualizacao de aprovador, aprovacao_status e historico da RPC real, usando roles e funcoes emulado apenas quando inevitavel.
2. Confirmar que o UPDATE de aprovacao nao reinicia a antecipacao nem modifica o snapshot.
3. Confirmar rejeicao de autoaprovacao indevida e de aprovador invalido com rollback do episodio.
4. Confirmar retorno de erro de envio/notificacao se e somente se a cadeia real o propagaria, e rollback correto quando necessario.
5. Validar regras de visibilidade de CC, funcao de consulta 12 e correcao 03 com papeis reais; nao liberar EXECUTE antecipadamente.
6. Revisar todos os BEFORE/AFTER triggers; a fixture atual so modela os de ciclo/auditoria/guarda.

## Estado

**Nao pronto para aplicacao em producao.** Rascunhos 01–12 ainda dependem de revisao integrada, migracao consolidada e testes de concorrencia. O banco compartilhado com Obras Control deve permanecer inalterado ate backup validado e autorizacao expressa.
