# Gate de implantacao — Folga de Campo por distancia

Atualizado em 12/11/2026. **Nao executar o pacote de testes em producao.**

## Entregas tecnicas

- Pacote atomico descartavel: `tests/sql/folgaCampoPacoteIntegrado.sql`, composto de oito rascunhos coordenados.
- Fluxo de testes: `.github/workflows/testar-folga-sql.yml` (PostgreSQL 16 temporario).
- O teste de duplicidade usa o mesmo predicado da funcao de producao `ro_funcionario_possui_folga_futura_ativa`, com nomes de argumentos adaptados a fixture. Resultados em banco isolado.
- O teste de concorrencia considera corretamente que uma segunda Folga futura ativa deve ser bloqueada, revertendo mudanca de CC.
- O teste `folgaCampoGrants.sql` exige RLS e ausencia de EXECUTE para anon/authenticated nas novas RPCs antes da ativacao.

## O que ja foi comprovado por teste SQL isolado

- Criacao, reutilizacao de km, transferencia interna, retorno confirmado.
- Rollback diante de erros de validacao e falhas posteriores.
- Correcoes autorizadas e historico preservado, com papeis simulados.
- Cadeia simplificada de aprovador, reprovacao, historico e rollback.
- Duplicidade futura ativa e concorrencia serializada para mesmo funcionario.
- Instalacao atomica de funcoes e triggers em schema *ficticio*.

## Bloqueios reais antes da implantacao

1. O pacote consolidado esta em `tests/sql`, **nao** em `supabase/migrations`. Sua fixture reproduz so parte das tabelas e gatilhos reais. Nao aplicar arquivo de testes no Supabase.
2. A cadeia completa do Supabase tem validacoes adicionais de status, compra, notificacao, documentos, auditabilidade e acesso que nao sao integralmente exercitadas pelo mock.
3. Novas RPCs estao intencionalmente sem EXECUTE para authenticated. Concessoes e politicas finais ainda exigem auditoria.
4. A integracao de criacao no frontend permanece desligada; ao ativar, e preciso combinar `p_solicitacao`, `p_documentos` e argumentos do adaptador, mais consulta com funcionario e CC consistentes.
5. O tratamento de colaboradores privados e viajantes manuais foi explicitamente recusado pelo novo wrapper preliminar; regra de negocio e compatibilidade precisam ser resolvidas.
6. Falta roteiro de rollback especifico para producao, com backup verificavel, historico de migrations e validacao de integridade.
7. Testes de ponta a ponta sobre todas as funcoes REAIS no ambiente compartilhado nao foram realizados. Nao alterar o projeto Portal TanksBR sem autorizacao.

## Regras que nao podem regredir

- Intervalos por distancia: 0–200=7; 201–600=14; 601–800=45; >800=90 dias; transporte conforme faixa.
- Ultima Folga de Campo **aprovada/dispensada e finalizada** como referencia.
- Justificativa de antecipacao, aprovacao RO e bloqueio de compra.
- Nenhuma atualizacao na lotacao oficial, `funcionarios`, `obras` ou Obras Control.
- Snapshots historicos imutaveis; correcao somente em episodio vigente com auditoria.

## Proximo trabalho autonomo

Revisar cadeia final de criacao sob privilegios, compatibilidade com visibilidade e fluxo de colaboradores, consolidar a migracao **para revisao** com comandos de backup e rollback. Solicitar autorizacao somente antes de executar DDL ou deploy em producao.
