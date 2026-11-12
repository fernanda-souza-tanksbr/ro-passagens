# Gate de preparação da Etapa B — Folga de Campo por quilometragem

**Escopo:** preparação e testes apenas. Nenhuma alteração da Etapa B no Supabase produção.
**Ambiente:** Portal TanksBR (`hukhwirdrpylxpaedjbc`), PostgreSQL 17.
**Referência já aplicada:** Etapa A `20261112192620`, gate `ro_private.folga_configuracao.ativo=false`.
**Branch:** `feat/folga-campo-regimes-distancia`.

## Entregáveis versionados

1. `docs/implantacao/folga-campo-etapa-b-coordenada-RASCUNHO.sql`: migration proposta, transacional, com `lock_timeout=5s`, `statement_timeout=120s`, preflight de dependências e hashes das duas funções antigas.
2. `docs/implantacao/folga-campo-reversao-etapa-b-RASCUNHO.sql`: reversão transacional que restaura as definições originais extraídas por SELECT da produção, removendo só RPC e trigger novos de B. **Recusa reversão quando há snapshots ou episódios gravados, ou gate ativo.**
3. `tests/sql/folgaCampoLegadoRealCaptura.sql`: seis funções e quatro gatilhos selecionados, capturados com `pg_get_functiondef` e `pg_get_triggerdef` diretamente do Supabase (sem dados dos usuários). São fixtures de leitura, nunca devem ser aplicados em produção.
4. `tests/sql/folgaCampoLegadoRealFixture.sql` e `tests/sql/folgaCampoEtapaBRealRegressao.sql`: dados fictícios, validações específicas de funcionamento legado e novo.
5. `.github/workflows/validar-folga-etapa-b-real-pg17.yml`: homologação isolada PostgreSQL 17, incluindo instalação A+B, reversão B, restauração dos hashes legados, reaplicação B e testes.
6. `.github/workflows/testar-folga-sql.yml`: testes abrangentes com fixtures e mocks controlados, separados da homologação de funções reais.

## Alterações exatas de B

- `CREATE OR REPLACE FUNCTION public.ro_validar_ciclo_folga_campo()`: seleciona o ciclo tradicional quando não há contexto de distância e mantém o fluxo legada enquanto a configuração privada está desligada; com contexto criado pela RPC nova, usa snapshot de quilometragem e intervalo.
- `CREATE OR REPLACE FUNCTION public.ro_auditar_ciclo_folga_campo()`: mantém trilha de ciclo com origem distinguida e acrescenta km / intervalo a eventos futuros.
- `CREATE FUNCTION public.ro_guardar_snapshot_folga()` + um trigger BEFORE UPDATE em `public.ro_passagem_solicitacoes`: protege histórico contra alterações diretas em qualquer UPDATE; trigger não existia em A.
- `CREATE FUNCTION public.ro_criar_folga_campo_com_distancia(jsonb,jsonb,integer,boolean)`: envolve preparação do episódio e RPC legada de solicitação numa transação. `EXECUTE` revogado para `PUBLIC`, `anon`, `authenticated`; B não libera o novo fluxo.
- Não altera `ro_criar_solicitacao_com_aprovador`, `ro_obter_ciclo_folga_funcionario`, `ro_bloquear_compra_antecipacao_pendente`, `ro_proteger_aprovacao_antecipacao`, `ro_proteger_recusa_terminal`, triggers de e-mails, compras ou aprovação. Não escreve em `funcionarios`, `alocacoes` ou `obras`.

## Estado real conferido (12/11/2026)

- 42 migrations remotas, última `20261112192620 folga_campo_etapa_a_aditiva`.
- Etapa B ainda não existe, flag continua `false`, 28 gatilhos ativos de aplicação no `ro_passagem_solicitacoes`.
- Hash global da definição dos 28 triggers: `1c2661e143449419dccf97bd18e9f4a7`.
- Hash `ro_validar_ciclo_folga_campo()`: `49a68dd1572810e5a18a996cd901df9e`.
- Hash `ro_auditar_ciclo_folga_campo()`: `589eb30a46581641c8bedf80e3d5e50e`.
- Hash `ro_criar_solicitacao_com_aprovador(jsonb,jsonb)`: `ad11c0490fc5bcdb187dfeb37951e49c`.
- Hash `ro_bloquear_compra_antecipacao_pendente()`: `292878f70182f054624ac4fc584adef0`.
- Hash `ro_proteger_recusa_terminal()`: `0d740ff1817b686ef32ff2d38cf48a15`.

## Limitações reais dos testes

- A captura contém definições genuínas de seis funções e quatro triggers críticos para ciclo/compra, mas **não constitui uma réplica completa** de todas as 28 triggers, serviços de email, aprovação e dados do Obras Control. Os testes continuam com um subconjunto de schema e dados fictícios.
- As execuções de testes não comprovam comportamento de negócio ponta a ponta sob usuário real, nem entrega SMTP, nem efeitos de autenticação no navegador.
- Garantia do gate: B não ativa regra. Ainda assim, substituição de duas funções executadas por triggers na tabela de solicitações pode afetar o legado, por isso os testes pós-implantação e reversão devem estar prontos.

## Estratégia de execução de B (somente após autorização específica)

1. Identificar backup mais recente na UI Supabase Pro; registrar horário e reconhecer possíveis perdas desde a captura, sem restaurar.
2. Verificar código versionado, `main`, deploy Vercel e histórico de migrations. Não usar `supabase db push` nas 82 migrations não alinhadas.
3. Verificar `gate=false`; B ausente; snapshot novo ainda vazio; hashes das duas funções e das 28 triggers idênticos aos de referência; checar funções de aprovação, compra, recusa e RFC de criação legada.
4. Aplicar SQL **exato** versionado em B usando Supabase `apply_migration`, uma vez, com nome `folga_campo_etapa_b_coordenada`. Não enviar C1/C2, não atualizar Vercel.
5. Confirmar que `list_migrations` registrou apenas B; registrar versão efetivamente criada como arquivo SQL idêntico em `supabase/migrations/<versao>_folga_campo_etapa_b_coordenada.sql`, sem inventar versão antes de aplicar.
6. Confirmar `gate=false`, RPC nova sem `EXECUTE` para anon/authenticated, triggers originais presentes e **somente um novo** trigger de snapshot; comparar hashes das funções não modificadas.
7. Executar verificações operacionais não destrutivas do RO Passagens e do Obras Control. Não criar solicitação real de teste não autorizada.

## Reversão

- Falha dentro da transação: rollback PostgreSQL automático, sem usar Restore.
- B aplicada, gate desligado, sem novos snapshots ou episódios: somente após autorização de reversão, executar `folga-campo-reversao-etapa-b-RASCUNHO.sql` via migration versionada específica, preservar A, confirmar hashes legados restaurados.
- Se houver dados novos, ativação ou dependências inesperadas: o rollback preparado **bloqueia-se**, exigindo plano individual de preservação de dados; nunca apagar dados para forçar reversão.
- Restore físico integral do Supabase não é a primeira opção, pois o banco é compartilhado pelo Obras Control.

## Critério de decisão

Pedir uma autorização única e explícita apenas quando GitHub Actions das suites SQL, B real PostgreSQL 17 e frontend concluírem com `success`. A autorização cobrirá somente B; C1/C2 e Vercel permanecem fora do escopo.
