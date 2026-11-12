# Gate de implantação — Etapa A aditiva (Folga de Campo por km)

**Estado:** preparado para avaliação; NÃO executado no Supabase de produção.
**Ambiente:** Portal TanksBR / `hukhwirdrpylxpaedjbc` (compartilhado com Obras Control).
**Branch:** `feat/folga-campo-regimes-distancia`. Não mesclar em `main` e não publicar Vercel nesta etapa.

## Fonte canônica versionada

- Implantação: `docs/implantacao/folga-campo-etapa-a-aditiva-RASCUNHO.sql`.
- Reversão exclusiva da etapa A (apenas vazia e antes de B): `docs/implantacao/folga-campo-reversao-etapa-a-RASCUNHO.sql`.
- Homologação A isolada: `tests/sql/folgaCampoEtapaAIsolada.sql`, GitHub Actions `.github/workflows/validar-folga-etapa-a-pg17.yml`.
- Os SQLs são versionados pelo commit GitHub. **Nenhum arquivo de migração histórico antigo será reaplicado**.

## Descoberta de divergência de histórico

- A listagem obtida por `list_migrations` no Supabase retorna 41 registros (último `20261109144800 destino_manual_sem_endereco_rh_20261109`).
- A branch RO Passagens contém 82 arquivos em `supabase/migrations` (até `202610210002`).
- Nenhum número de versão de arquivo coincide com o histórico remoto, embora existam estruturas equivalentes no banco. Isso **não** prova ausência de aplicação antiga; possivelmente houve aplicação por SQL direto e pelo projeto Obras Control.
- Portanto, **não executar** `supabase db push`, `supabase db reset`, scripts antigos em lote, nem reparar automaticamente o histórico.
- Caminho recomendado: após autorização expressa, chamar `Supabase.apply_migration` **uma única vez** com nome `folga_campo_etapa_a_aditiva` e exatamente o SQL versionado da Etapa A; confirmar o retorno e consultar novamente `list_migrations`. Essa operação registra uma migration nova no histórico remoto sem alterar registros anteriores.
- Após a aplicação, criar em `supabase/migrations` arquivo correspondente à **versão efetivamente retornada** pelo Supabase, com o SQL idêntico, no branch de desenvolvimento. Não inventar versão nem encadear a execução de migrations antigas. Manter registro do commit/sha do SQL executado.
- Não usar `execute_sql` para instalar os objetos da Etapa A, porque não registra migration, gerando novo drift.

## Escopo comprovado da Etapa A

- Cria `public.ro_folga_alocacoes` e `public.ro_folga_distancia_auditoria`, ambas com RLS, sem concessões diretas a anon/authenticated.
- Adiciona **somente quatro colunas anuláveis** em `public.ro_passagem_solicitacoes` com constraints/FK.
- Cria novo schema `ro_private`, `ro_private.folga_configuracao` com `ativo=false`, `ro_private.folga_criacao_contexto` e funções auxiliares.
- Cria `public.ro_consultar_contexto_distancia_folga` e `public.ro_corrigir_distancia_folga`, com EXECUTE revogado a PUBLIC/anon/authenticated na mesma transação.
- **Não cria nem modifica triggers**, não substitui a RPC original de criação, não altera uma só linha de solicitações/funcionarios/obras; sem alterações no frontend.
- `lock_timeout=5s` e `statement_timeout=90s`: se houver conflito/bloqueio, falhar e reverter a transação, **não** aumentar os limites automaticamente.
- O preflight bloqueia reexecução caso o schema privado ou as tabelas já existam.

## Limites da evidência de homologação

- A homologação A isolada roda PostgreSQL **17** em GitHub Actions, aplica A **sem** B e verifica quatro colunas, catálogo, gate desativado, RLS e ausência de EXECUTE público; compara a definição da RPC legada e a contagem de triggers antes/depois; rejeita reaplicação; executa reversão pontual e reconfere o estado inicial.
- Testes completos prévios A+B+C1+C2 já passaram em PostgreSQL 16 com mocks; **não** provaram a execução de todos os 28 triggers reais de produção.
- Foram conferidas em leitura as assinaturas de funções reais e a estrutura da tabela, inclusive casos de colaborador privado. Um teste integral em réplica com todas as triggers reais permanece para a Etapa B/C2, antes de qualquer ativação. Não criar projeto de homologação pago sem aprovação.
- O teste de schema não substitui ensaio de carga, verificação de latência e comparação de todas as funções existentes; preservar limite de timeout.

## Antes de pedir execução

1. Verificar `main` e deploy production Vercel READY e confirmar que seguem no mesmo commit de referência; não alterar `main`.
2. Confirmar backup físico de origem recuperável mais recente no painel Supabase **imediatamente antes da mudança**, seu horário e o risco de perder alterações posteriores a ele. A captura de 12/11/2026 07h24 comprova a existência da opção de restauração, **não um teste de restauração**.
3. Consultar `list_migrations`; confirmar novas tabelas/schema/colunas ainda ausentes, sem versão parcial de A; conferir diferenças de estrutura e grants.
4. Registrar hashes/definições de `ro_criar_solicitacao_com_aprovador`, `ro_validar_ciclo_folga_campo`, `ro_auditar_ciclo_folga_campo`, todos os triggers existentes e suas contagens, com **somente SELECT**.
5. Confirmar que GitHub Actions da etapa A PostgreSQL17 concluiu todos os passos com sucesso.
6. Obter autorização expressa para o exato SQL da etapa A. Não entender autorização da preparação como autorização para executar produção.

## Execução futura autorizada

1. Aplicar **somente A** por `Supabase.apply_migration`, nome `folga_campo_etapa_a_aditiva`, transação única fornecida no SQL.
2. Conferir histórico `list_migrations`, tabelas, RLS, grants, quatro colunas e gate `false`; funções/triggers existentes devem ser idênticos, não apenas contar o mesmo número.
3. Conferir o RO Passagens (criação de outra motivação, listagem, aprovações, compras e notificações existentes) e Obras Control (login, obras, funcionários, leituras), **sem gerar solicitações reais de teste involuntariamente**.
4. Registrar resultado, commit, versão de migration, comprovante de backup e preflight. Não avançar para B/C1/C2 sem outra decisão.

## Reversão

- Se A falhar **durante** a transação: PostgreSQL desfaz automaticamente a alteração.
- Se A for concluída e **B ainda não executada**, confirmar que tabelas A estão vazias e que nenhuma das quatro colunas tem valores. Executar a reversão pontual em transação, **somente com autorização explícita**; ela verifica ausência de B e de dados antes de remover colunas, funções, tabelas e schema novos.
- Em caso de qualquer dependência nova, dados preenchidos ou B já presente: **não usar** a reversão A; analisar opção específica sem destruir histórico.
- Backup físico Supabase é última alternativa, pois a restauração integral pode reverter solicitações/obras mais recentes e não inclui objetos do Storage.
