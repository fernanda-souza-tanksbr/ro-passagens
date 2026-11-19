# PR #6 — Plano de publicação supervisionada

**Estado:** somente plano; nenhuma operação de produção autorizada ou executada.

## Pré-condições

1. Confirmar backup físico recente do Supabase `hukhwirdrpylxpaedjbc` com Restore disponível, incluindo horário e identificador.
2. Conferir o HEAD exato do PR, Preview READY e testes direcionados, TypeScript, lint e build; verificar que a revisão do SQL/rollback foi concluída.
3. Confrontar tabelas, colunas, funções e gatilhos com o banco em leitura, e repetir a verificação imediatamente antes de aplicar SQL. Especificamente `ro_catalogo_colaboradores_viagem`, `ro_motivo_possui_retorno`, `ro_obter_dados_para_refazer_solicitacao`, `ro_notificar_retorno_pendente` a RPC `ro_criar_solicitacao_com_aprovador`, a política RLS de `ro_responsaveis` e a nova RPC `ro_listar_responsaveis_filtro` (ausente no baseline).
4. Confirmar os quatro domínios operacionais ainda no deployment `dpl_9LkjBivyrvFtpSjFvqhZeGdUnkoS`; guardar ID e procedimento de Instant Rollback.
5. Obter autorização explícita separada para SQL e publicação. Não criar branches pagas nem tocar C2 ou confidencialidade.

## Ordem segura

1. **SQL primeiro, em janela controlada:** executar **uma vez** `supabase/manual/20261119_restringir_viagem_administrativa_NAO_APLICAR.sql` no projeto correto, em transação. O SQL amplia o catálogo RO para registros privados sem vínculo operacional, disponibiliza os responsáveis RO por RPC restrita sem abrir a RLS, habilita o motivo administrativo no helper de retorno, preserva dados de refação, mantém notificações dos outros motivos e instala o gatilho de proteção de passageiros e datas. Enquanto a versão antiga estiver ativa, passageiros operacionais que tentarem Viagem Administrativa passarão a ser bloqueados (resultado desejado, mas requer aviso à equipe).
2. **Verificação pós-SQL:** conferir as definições de funções/gatilho e as permissões; ler amostras agregadas, sem modificar solicitações reais. Não criar e-mails, compras ou aprovações. Validação integrada de escrita deve ocorrer somente em ambiente isolado com dados fictícios, quando disponível.
3. **Frontend:** após SQL aprovado e somente após autorização para publicar, preparar deployment de produção com o commit revisado, **sem atribuir domínios**, mantendo os quatro aliases no deployment estável. Não confiar no merge para criar build automático de Production (Ignored Build Step personalizado).
4. **Gate de domínio:** validar login, navegação e fluxos não destrutivos na URL temporária usando configuração production correta e manifesto legado/C2 inalterado; promover o deployment revisado na janela autorizada; confirmar os quatro aliases e execução operacional RO.
5. Registrar commits, deployment IDs, horário, resultado e comandos usados.

## Reversão

- **Se falhar após SQL, antes da promoção:** não promover; os quatro domínios seguem no deployment anterior. Avaliar se é seguro rodar o SQL de rollback, conferindo primeiro a inexistência de dados de retorno administrativos novos. O script **aborta a transação** se houver registros; nunca remover informação para forçar rollback.
- **Se falhar após promoção:** primeiro Instant Rollback/reatribuição dos quatro domínios ao deployment estável; verificar login e solicitações. Depois avaliar o SQL de rollback separadamente. A alteração de helper/catálogo no banco pode permanecer se houver dados novos, e isso é preferível a perda de dados.
- **Ponto de atenção:** a função antiga `ro_motivo_possui_retorno` não reconhece retorno administrativo; não restaurá-la se existirem retornos administrativos novos.
- Não reexecutar migrations antigas, não modificar C2, configurações SMTP ou confidencialidade dos desligamentos.

## Riscos e limitações

- Os Previews estão ligados ao Supabase de produção: **não fazer testes de escrita**.
- Testes SQL de estrutura estática não substituem execução numa instância isolada PostgreSQL 17. Exigir essa etapa para declaração de compatibilidade total se não houver evidência de parse/execução real.
- A implementação de Viagem Administrativa com retorno depende de **SQL e frontend em conjunto**; nunca promover o frontend antes de confirmar o SQL.
- O catálogo RO novo passa a expor também registros privados vinculados apenas a funcionários não operacionais; revisar duplicações potenciais na seleção com equipe RO durante homologação.
