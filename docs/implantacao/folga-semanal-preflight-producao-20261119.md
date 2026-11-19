# Folga semanal — preflight antes de publicar (estado observado em 19/11/2026)

## Estado operacional CONFIRMADO, não presumir estado inicial C2
- A produção Vercel do Portal RO tem cliente/manifesto `distancia` (versão 2) e não deve ser trocada por cliente `legado` desta branch sem revisão.
- Consulta SQL fornecida pela operação após recuperação: `novo_fluxo_distancia=true`, `novas_folgas_campo=false`. A equipe RO conseguiu consultar km, criar solicitação real e prosseguir com compra. Preservar este estado.
- Existem solicitações com snapshots da C2, incluindo pelo menos uma ativa em 19/11. Nunca remover snapshots, históricos ou reaplicar rollback antigo indiscriminadamente.
- PR #7 foi integrado nesta branch em `f6a2a81bdb5136e92377a978df75a2ce259ed858`; workflows isolados Node 22 e PostgreSQL 17 passaram nesta revisão.
- `main` está divergente desta branch (várias alterações de outros módulos e workflows); **não fazer merge integral** nem presumir que a branch atual seja release pronto.
- PR #6 (Viagem Administrativa) segue isolado. Não misturar suas alterações sem teste e sequência de implantação próprios.

## Bloqueios objetivos a resolver ANTES de publicar
1. Construir branch de integração a partir do `main` efetivamente aprovado e conciliar seletivamente alterações C2 relevantes. Conferir diferença contra o **deployment ativo** (CLI pode divergir de `main`). Comparar `src/pages.tsx`, `src/App.tsx`, módulos Folga, regras de solicitações, migrations e manifesto, sem sobrescrever melhorias paralelas.
2. Compilar e testar no SHA final: `npm ci`, `npm run typecheck`, `npm test`, `npm run build`; executar integração PostgreSQL 17 isolada (incluindo quatro semanas, conflito, concorrência, perfis privados, 14/45/90, rollback); CI verde deve corresponder ao **mesmo SHA** que será publicado.
3. Inspecionar no banco **somente por SELECT** qual função/trigger C2 já está instalado, seu hash e se o pacote `sql/folga_semanal_c2_producao.sql` foi de fato aplicado; o gate true **não prova** que o trigger semanal está instalado. Não executar novamente C2 por dedução. Usar versionamento/registro de migrations e `pg_get_functiondef` para comparação.
4. Rever diferença entre cliente publicado `distancia` e `public/folga-campo-release.json` nesta branch (`legado`). O novo build final deve ter manifesto `distancia` e `VITE_FOLGA_CAMPO_KM_ENABLED=C2_PRODUCAO_APROVADA` **no build**, e testes garantindo o modo; não confiar em env definida após compilar.
5. Preparar deployment `--prebuilt --prod --skip-domain`, inspecionar o artefato sem promover nem atribuir aliases e manter um rollback específico pronto. Não gastar quota Vercel se ainda bloqueada.
6. Na janela, somente se uma migration adicional for necessária: controlar suspensão seletiva em transação; verificar estados antes e depois; evitar bloquear compras/aprovações e manter outros motivos operacionais. **Não reexecutar a sequência antiga COMPAT/TRANSICAO/DISTANCIA automaticamente**: a produção já opera `distancia`.
7. Após publicação, usar solicitação real autorizada para validar criação semanal sem duplicações e continuidade operacional; não usar funcionários fictícios, compras ou e-mails de teste em produção.

## Consulta de preflight somente leitura (executor Supabase)
```sql
SELECT
  (SELECT ativo FROM ro_private.folga_configuracao WHERE chave='novo_fluxo_distancia') AS gate_distancia,
  (SELECT ativo FROM ro_private.folga_suspensao_criacao WHERE chave='novas_folgas_campo') AS suspensao,
  md5(pg_get_functiondef('public.ro_validar_ciclo_folga_campo()'::regprocedure)) AS hash_funcao_ciclo,
  (SELECT pg_get_triggerdef(oid)
   FROM pg_trigger
   WHERE tgrelid='public.ro_passagem_solicitacoes'::regclass
     AND tgname='ro_validar_ciclo_folga_campo') AS definicao_trigger,
  (SELECT count(*)
   FROM public.ro_passagem_solicitacoes
   WHERE motivo='folga_campo' AND folga_alocacao_id IS NOT NULL
     AND excluida_em IS NULL) AS snapshots_c2_ativos;
```
**Não fazer UPDATE se o resultado divergir do estado aprovado.** A migration guardada `sql/folga_semanal_c2_producao.sql` exige estado de suspensão específico e hash anterior. Se a função semanal já estiver instalada, a migration guardada pode falhar corretamente; não remover guardas para forçar reaplicação.

## Critério de GO/NO-GO
GO somente com: branch final isolada e CI verde, function/trigger do banco identificados, snapshots preservados, manifesto e flag `distancia` conferidos no deployment pronto, rollback validado, ausência de alteração não aprovada nos demais módulos, janela de promoção autorizada.
NO-GO se qualquer etapa depender de hipóteses sobre estado do banco, se o manifesto efetivo for legado/transição, se não houver rollback seguro, ou se a publicação atribuir aliases automaticamente.
