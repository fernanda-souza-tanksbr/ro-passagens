# C2 — baseline minimo de servicos reais (16/11/2026)

## Escopo e evidencias
Workflow: `.github/workflows/folga-c2-servicos-reais.yml`. Usa PostgreSQL 17 e PostgREST v12.2.8 em containers efemeros no GitHub Actions, exclusivamente com UUIDs e dados ficticios. Nenhuma URL/chave de producao; nenhuma escrita no Supabase/Vercel.

### Definicoes SQL reutilizadas sem reconstituir Portal inteiro
- `tests/sql/folgaCampoFixture.sql`: tabelas minimas de funcionarios, obras, colaboradores privados, roles, responsaveis, solicitacoes e auditoria.
- `tests/sql/folgaCampoLegadoRealFixture.sql`: colunas adicionais.
- `docs/implantacao/folga-campo-etapa-a-aditiva-RASCUNHO.sql`, `folga-campo-etapa-b-coordenada-RASCUNHO.sql`, `folga-campo-etapa-c1-permissoes-RASCUNHO.sql`: DDL e funcoes A/B/C1.
- `tests/sql/folgaCampoLegadoRealCaptura.sql`: definicoes reais anteriormente capturadas do controle de ciclo, auditoria, antecipacao e bloqueio de compra.
- `tests/c2-real/postgrest-bootstrap.sql`: roles REST, JWT, RLS restritiva e adaptador de auth.uid() para claims do PostgREST.

### Simulacoes exatas e limites
1. **GoTrue/Supabase Auth nao esta instalado neste workflow.** O token JWT HS256 e assinado no runner; a validacao de assinatura, expiracao, role e autorizacao HTTP e feita por PostgREST real. Login, refresh, revogacao, MFA, confirmacao de email e ciclo de sessao GoTrue nao sao comprovados.
2. `auth.users` e uma tabela ficticia minima, nao o esquema Auth oficial. `auth.uid()` e adaptada para `request.jwt.claims` e `test.uid` usado em testes SQL anteriores.
3. `public.ro_criar_solicitacao_com_aprovador` e a implementacao **reduzida do fixture** com SECURITY DEFINER apenas no banco temporario; testa a chamada legada e o bloqueio do trigger B, mas nao as validacoes completas de aprovacoes, documentos, notificacoes e regras operacionais de producao.
4. `public.ro_can_view_private_addresses` e helper simplificado ja usado no teste C1; nao substitui autorizacao integral do cadastro privado.
5. RLS e aplicada restritivamente a todas as tabelas publicas do fixture; sem acesso direto REST. Nao representa a matriz completa de policies do Portal.
6. Nao ha e-mails, compras, arquivos Storage ou dados reais.

### Matriz de comprovacao
- Testes SQL PostgreSQL 17 A/B/C1 existentes cobrem operacoes de km, correcoes, auditoria, permissoes, antecipacao e bloqueios em roles reais de banco.
- Testes HTTP do novo workflow verificam token assinado, negacao anon, gate false, consulta com gate true, criacao nova, bloqueio do cliente legado e ferias.
- A suite React Playwright da C2 e separada e intercepta HTTP; nao confundir com servicos reais.
- So declarar C2 pronta quando todos os workflows no commit final estiverem verdes e os limites acima forem aceitos.
