# Etapa C2 — Homologação da interface e gate de publicação

Data: 13/11/2026. Projeto Portal TanksBR: Supabase `hukhwirdrpylxpaedjbc`, Vercel `portal-tks-br`. Branch `feat/folga-campo-regimes-distancia`.

**Proibição:** este documento não autoriza aplicar a migration C2, ligar `novo_fluxo_distancia`, mudar variável de produção nem promover deploy do RO Passagens.

## Evidências e ambientes

- A `20261112192620`, B `20261113110519`, C1 `20261113164939` aplicadas. Configuração de ativação deve permanecer **false** até uma futura aprovação.
- As novas RPCs C1 requerem `novo_fluxo_distancia=true`; com false rejeitam qualquer execução funcional.
- `src/pages.tsx`: `NOVO_FLUXO_FOLGA_ATIVO=false` no código atual. O preview da branch com esse arquivo NÃO mostra ainda a Folga por km.
- Vercel `portal-tks-br` compartilha `VITE_SUPABASE_URL`, `VITE_SUPABASE_PROJECT_ID` e `VITE_SUPABASE_PUBLISHABLE_KEY` entre **production e preview**. Assim, **proibido** fazer testes com escrita em preview desse projeto; preview de frontend não implica banco isolado.
- Criado projeto **separado** Vercel `ro-folga-campo-homologacao` (ID `prj_r5GAUXcLIfZCKhM4AfJA8EOafoRH`) **sem variáveis de ambiente**, sem Git conectado, com SSO. Conteúdo estático enviado de `homologacao/folga-campo/index.html`. Este projeto não é o `portal-tks-br`.
- URL de conferência visual: `https://ro-folga-campo-homologacao-9t5ftfput-tanks.vercel.app`.
- CSP do mock: `connect-src 'none'`, `default-src 'none'`; não contém SDK Supabase, fetch, XMLHttpRequest nem WebSocket; sem login, sem dados, aprovações, compras ou e-mails.
- GitHub Actions navegador em `.github/workflows/validar-folga-c2-interface.yml`, Playwright/Chromium em runner GitHub Ubuntu 24.04 e dados fictícios.
- Testes SQL separados em PostgreSQL17 descartável (`.github/workflows/testar-folga-sql.yml` e `.github/workflows/validar-folga-etapa-c1-pg17.yml`).

## Duas camadas diferentes de homologação

1. **Interface demonstrativa:** as regras, mensagens, campos e estados são simulados localmente, para aprovação visual; não é o aplicativo React completo, não faz login Supabase e não executa RPC HTTP. Os botões apenas alteram memória do navegador.
2. **Backend e contratos:** testes unitários do código verdadeiro (`src/folgaCampoRegimes.ts`, `src/folgaCampoIntegracao.ts`, `src/folgaCampoCompatibilidade.ts`, `src/folgaCampoConsulta.ts`) e testes SQL com PostgreSQL17/roles/fixtures fictícios. São diferentes do teste completo da interface do RO com Auth + PostgREST reais.

**Ponto de bloqueio para release:** antes de ativar C2 em produção, ainda é exigida a integração integral React + autenticação + RPC num ambiente realmente separado. Nenhum teste de escrita no preview que compartilha Supabase de produção pode suprir esse requisito.

## Cenários

| Cenário | Interface visual fictícia | Código/SQL real (testes isolados) |
|---|---|---|
| 0/200: ônibus/7d | Incluído | `tests/folgaCampoRegimes.test.ts` |
| 201/600: ônibus/14d | Incluído | Mesmo teste |
| 601/800: ambos/45d | Incluído | Mesmo teste |
| 801/1500: ambos/90d | Incluído | Mesmo teste |
| 1501+: avião/90d | Incluído | Mesmo teste |
| Primeiro pedido, sem folga anterior | Incluído | `tests/folgaCampoIntegracao.test.ts` |
| Mesma obra reutiliza km | Incluído | `tests/folgaCampoCompatibilidade.test.ts` |
| Mudança de obra / retorno | Incluído | `tests/folgaCampoIntegracao.test.ts` + SQL |
| Privado com/sem vínculo | Incluído | `tests/sql/folgaCampoPrivados.sql` + C1 |
| Antecipação, justificativa, aprovação/compra | Incluído | `tests/sql/folgaCampoAprovacoes.sql` + B real |
| Correção e histórico preservado | Incluído | `tests/sql/folgaCampoPermissoes.sql` + C1 |
| Duplicidade de folgas futuras | Incluído | `tests/sql/folgaCampoDuplicidadeReal.sql` |
| Férias/desligamento usam RPC legada | Incluído | `tests/folgaCampoCompatibilidade.test.ts` |
| Auth, 29 triggers completos, SMTP e compra operacional | **Não validado E2E** | Não executar em produção como substituto |

## Compatibilidade de versões — risco concreto

| Cliente / banco | Consequência |
|---|---|
| Frontend atual, A+B+C1 e gate `false` | Fluxo de produção atual continua pela RPC legada |
| Frontend novo com flag `true`, banco gate `false` | RPCs novas retornam `FOLGA_CAMPO_KM_AINDA_DESATIVADO`; NÃO publicar novo UI ativo antes de ativar o banco |
| Frontend novo `true`, banco gate `true` | Caminho previsto, sujeito a testes integrados e liberação |
| Frontend antigo `false`, banco gate `true` | RPC legada de Folga pode ser bloqueada com `FOLGA_CAMPO_DISTANCIA_OBRIGATORIA_NOVO_FLUXO`; outros motivos permanecem |
| Frontend novo `false` (como branch atual), banco gate `true` | Também bloqueia pedidos de Folga; publicação desacoplada causa falha |

**Consequência:** não existe hoje mecanismo comprovado de transição sem interrupção para sessões antigas de Folga. O roteiro de ativação deve prever uma janela operacional controlada, aviso para atualizar abas abertas, impedimento de novas solicitações de Folga durante transição, e plano de suporte/rollback. Alternativamente, implementar e homologar protocolo de compatibilidade com clientes antigos ANTES do release. Não afirmar que a versão atual é compatível com todos os clientes após C2.

## Plano de liberação coordenada FUTURA (sujeito a aprovação)

1. Obter aceite visual da demonstração e registrar correções de UX na branch.
2. Preparar ambiente Auth+RPC verdadeiramente isolado (não produção) ou serviços mock de Auth e RPC adequados; executar testes Playwright no app React real, sem e-mails/compra reais.
3. Revisar se o React consulta a versão atual do banco e se a UI pode fazer fallback seguro com gate desligado; **não permitir fallback silencioso** à RPC antiga após C2.
4. Preparar build da versão real (flag da interface ainda desligada até release), validar CI, checks e tags GitHub. Confirmar `main` de produção, seu deployment e risco de abas antigas.
5. Definir manutenção curta para novas Folgas e aviso de recarregamento às equipes; preservar aprovações, outras solicitações, Obras Control. Escolher ordem do switch para não expor janela de criação incompatível.
6. Antes da troca: confirmar backup recente recuperável, gate=false, permissões C1, hashes do SQL C2, último deploy e logs de erros. Não reaplicar migrations antigas.
7. Só com autorização expressa: publicar/promover frontend definitivo, aplicar somente migration C2 via `apply_migration` e conferir imediatamente o gate/compatibilidade. Separar cada ação registrando horários. Não usar o presente preview estático como deploy de produção.
8. Verificar canários autorizados: Folga 200/201/601/801/1501; sem histórico, CC, privado, antecipação, aprovação, compras, e-mail, exclusões e outros motivos. Sem gerar solicitações operacionais involuntárias.
9. Monitorar erros de RPC e Vercel, falhas de aprovação, bloqueios de compra, pedidos duplicados e acesso do Obras Control.

## Reversão pontual da ativação — se ainda for necessária

- `docs/implantacao/folga-campo-reversao-ativacao-RASCUNHO.sql` mantém dados, snapshots e episódios; desliga flag e revoga novas RPCs. NÃO excluir nada. Aplicar somente após diagnóstico e autorização de rollback.
- O frontend de produção deve voltar à versão com novo fluxo DESLIGADO na mesma janela; se backend gate=false e UI=true haverá erros. Uma reversão SQL isolada sem rollback coordenado da UI é insegura.
- Como os dois apps compartilham banco, evitar Restore integral. Backups são contingência excepcional.
- As definições das etapas A/B/C1 devem permanecer, não descartar o histórico de distância.

## Decisão pendente

A interface de demonstração está disponível à revisão visual; **não há aprovação para C2 ou deploy da aplicação de produção**. A etapa C2 só pode ser considerada pronta para ativação após sanar o risco de transição entre frontend antigo/novo e demonstrar integração Auth/RPC isolada com frontend React real.
