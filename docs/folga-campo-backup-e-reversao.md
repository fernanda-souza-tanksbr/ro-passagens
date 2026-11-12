# Plano de backup, ativacao e reversao — Folga de Campo por distancia

**Somente planejamento. Proibida execucao em producao sem autorizacao explicita.**

## Objetos existentes que precisam de copia verificavel

- Banco Supabase do projeto Portal TanksBR (`hukhwirdrpylxpaedjbc`), com identificacao da versao de referencia.
- Definicao completa atual de `public.ro_validar_ciclo_folga_campo()` e `public.ro_auditar_ciclo_folga_campo()`, obtidas de `pg_get_functiondef`.
- Definicoes e ordem dos gatilhos existentes sobre `public.ro_passagem_solicitacoes`, obtidas de `pg_get_triggerdef`.
- Confirmacao de backups regulares e snapshot manual testado. Sem alterar Storage ou tabelas de Obras Control.
- Registro do commit GitHub e deployment Vercel em producao ANTES da alteracao.

## Duas fases transacionais propostas

**Etapa A**, `docs/implantacao/folga-campo-etapa-a-aditiva-RASCUNHO.sql`:
cria somente tabelas adicionais, politica inicial de acesso restrito, funcoes privadas e RPC de consulta ainda sem grants. **Nao troca os triggers de solicitacoes existentes.** No ambiente temporario, essa etapa deve manter a criacao antiga inalterada.

**Etapa B**, `docs/implantacao/folga-campo-etapa-b-coordenada-RASCUNHO.sql`:
substitui as duas funcoes ligadas a triggers existentes, inclui guarda de snapshot e wrapper novo sem EXECUTE para clientes. So pode ser considerada depois de backup dos corpos originais e testes de compatibilidade com cadeia real.

**Ativacao posterior**: conceder permissoes estritamente necessarias, conectar UI a RPC e fazer deploy em etapa separada, apos homologacao. A constante `NOVO_FLUXO_FOLGA_ATIVO` permanece `false` ate entao.

## Reversao

1. Desabilitar imediatamente o novo fluxo da interface e restaurar a versao de producao de referencia da Vercel, se ele tiver sido ativado.
2. Em transacao SQL controlada, restaurar o texto exato previamente exportado das duas funcoes existentes, mantendo os triggers com seus nomes. Reverter o guard adicional somente apos confirmar que seu uso nao interfere em solicitacoes ja criadas com snapshot.
3. Revogar EXECUTE das RPCs novas antes de nova exposicao.
4. **Nao apagar** as tabelas de distancia nem colunas adicionadas se ja houver solicitacoes ou episodios vinculados: isso destruiria trilha de auditoria e violaria FKs. Preservar dados, sem modificar snapshots historicos.
5. Conferir criacao tradicional, aprovacoes, notificacoes, antecipacao, bloqueio de compra, folgas duplicadas e integridade de Obras Control.

## Criterios de bloqueio

- Sem validacao do fluxo de viajantes privados/manuais, nao habilitar a funcionalidade para esses casos; preservacao do comportamento atual requer decisao explicita.
- O mock nao representa a cadeia real de documentos, notificacoes e outros triggers; `success` no PostgreSQL descartavel nao equivale a homologacao.
- A funcionalidade de correcao global exige RPC publica auditada e checagem de atividade do operador; ainda nao foi integrada a UI.
- Nao aplicar arquivos de `tests/sql` no Supabase real. Nao executar scripts de `docs/implantacao` isoladamente nem sem aprovacao.

## Verificacoes finais

Antes de uma publicacao, verificar se commits, definicoes SQL, grants e dados nao mudaram desde a revisao. Testar em etapas, monitorar erros e documentar o resultado. Nenhum deploy automatico e autorizado por este documento.
