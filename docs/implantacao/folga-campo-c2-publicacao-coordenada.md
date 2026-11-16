# C2 — roteiro fechado de publicação coordenada (PREPARAÇÃO, NÃO EXECUTAR)
Referência funcional homologada: `35008f9466e10c6b8140c51d02a441028acc8b95`.
Este documento operacional não altera regras de negócio. A publicação exige autorização já concedida e todas as verificações de segurança no momento da janela.

## Invariantes
- Nunca liberar novas Folgas durante a troca de versões. A trava SQL `ro_private.folga_suspensao_criacao.ativo=true` precede qualquer promoção.
- `novo_fluxo_distancia=false` até o cliente definitivo estar publicado, inspecionado e em modo `distancia`.
- Manifesto é aviso/UX, **não** barreira para abas antigas. A barreira é o trigger SQL, e, após liberação, a exigência da Etapa B.
- Não executar testes de INSERT operacional; testes de criação completos já foram feitos em ambiente isolado.
- Não alterar Obras Control; não reaplicar A/B/C1; não restaurar banco inteiro.

## Três artefatos imutáveis (mesmo código funcional)
A origem funcional é o SHA homologado; as alterações de manifesto são somente de release. Cada build deve registrar seu SHA, `VITE_FOLGA_CAMPO_KM_ENABLED`, modo do manifesto, ID de deployment e checksum do `dist`/manifesto.

| Artefato | Vite no momento do build | /folga-campo-release.json | Comportamento |
|---|---|---|---|
| COMPAT | variável ausente (não definir `C2_PRODUCAO_APROVADA`) | `{"modo":"legado","versao_minima":2}` | cliente v2 usa RPC legada; suspensão SQL mantém Folga bloqueada durante janela |
| TRANSICAO | variável ausente | `{"modo":"transicao","versao_minima":2}` | bloqueia novas Folgas no cliente v2; suspensão SQL é a barreira para abas antigas |
| DISTANCIA | `C2_PRODUCAO_APROVADA` | `{"modo":"distancia","versao_minima":2}` | cliente v2 usa nova RPC; suspensão SQL permanece ativa até validação |

**Atenção:** o `import.meta.env.VITE_FOLGA_CAMPO_KM_ENABLED` é compilado pelo Vite. Alterar env após build não altera bundle. O manifesto é um arquivo estático empacotado no deploy; mudar JSON em uma branch sem novo deploy/promoção não altera a produção. Não usar variável de produção global que contamine builds COMPAT/TRANSICAO. Preferir três builds imutáveis de produção, gerados com env explícita em CI protegida, com o mesmo código funcional, mudando apenas os dois parâmetros de release. O deploy de `main` via integração Git pode ser automático: bloquear auto-promoção antes de qualquer merge (Deployment Checks / configuração de domínio) ou usar CI controlado com `--skip-domain`; não assumir que o merge seja inofensivo.

## Preparação isolada, sem publicação
1. Usar runner GitHub Actions protegido com checkout do SHA homologado, Node conforme lockfile, `npm ci`, `npm run build`. Para cada variante, injetar o valor Vite **antes** do build, escrever `public/folga-campo-release.json` com o modo correspondente e gerar build separado, sem reaproveitar `dist` ou cache de build. Nenhum runner precisa de conexão com Supabase de produção.
2. Verificar no `dist/folga-campo-release.json` JSON exato e `dist/index.html`; inspecionar bundle para confirmar que o cliente COMPAT/TRANSICAO não está habilitado e o DISTANCIA está habilitado (idealmente por teste de navegador com manifesto real, sem banco de produção). Registrar checksums e SHA.
3. Para Vercel, o caminho de promoção segura é `vercel deploy --prebuilt --prod --skip-domain` seguido de `vercel promote <deployment-url>`. Os builds `--prebuilt` devem ser produzidos com `vercel build --prod` e o ambiente Vite correto **no processo de build**, não apenas em `vercel deploy`. Verificar que o `vercel pull` não sobrescreveu a variante; não promover preview como substituto de produção.
4. Confirmar antes da janela que CI dispõe de VERCEL_TOKEN, VERCEL_ORG_ID e VERCEL_PROJECT_ID em secrets/vars protegidos, versão fixada da CLI, e que não haverá publicação automática não coordenada pela integração Git. Se isso não estiver garantido, PARAR.

## Sequência de produção, com checkpoints
0. Registrar backup recente recuperável, main SHA, deploy READY, 44 migrations e gate false. Confirmar que o SQL da trava corresponde ao arquivo homologado e que a coluna `motivo` aceita `folga_campo`.
1. Aplicar **somente** migration `folga_campo_c2_suspensao_seletiva` com o conteúdo de `docs/implantacao/folga-campo-c2-suspensao-seletiva-RASCUNHO.sql`, inicialmente false. Confirmar tabela privada, RLS, REVOKE, trigger habilitado e valor false.
2. Em transação controlada, `update ro_private.folga_suspensao_criacao set ativo=true, atualizado_em=now() where chave='novas_folgas_campo';`. Ler valor true e confirmar gate false. Nenhuma nova Folga deve ser permitida. Não efetuar INSERT de teste na produção.
3. Preparar os três deploys de produção sem atribuição de domínio (`--skip-domain`) e inspecionar SHA, conteúdo do manifesto, cache header e build mode. Se a integração Git atribuir domínio automaticamente, PARAR e corrigir a configuração antes de continuar.
4. Promover COMPAT. Verificar URL canônica, `/folga-campo-release.json` em modo legado, `Cache-Control: no-store`, cliente compatível, login/consultas de leitura e demais motivos; suspensão SQL continua true.
5. Promover TRANSICAO. Verificar modo transicao, mensagem de atualização/suspensão e que os demais motivos continuam disponíveis. Abas anteriores a v2 não são atualizáveis à força; manter trigger true.
6. Promover DISTANCIA (build comprovadamente com flag `C2_PRODUCAO_APROVADA`), ainda com gate false e suspensão true. Verificar manifesto `distancia`, JS correspondente, UI e login em sessão limpa. A nova RPC ainda deve retornar gate desativado; não criar solicitações reais.
7. Ativar `novo_fluxo_distancia=true` pelo SQL de `docs/implantacao/folga-campo-etapa-c2-ativar-RASCUNHO.sql` após conferir grants e estado esperado. Suspensão permanece true. Verificar gate true, trigger da Etapa B, RLS e funções; observar logs sem escrita de teste.
8. Validar operacionalmente interface e leitura de contexto com conta autorizada, sem criar Folga, compra ou e-mail. Verificar preservação das rotas de férias/desligamento/aprovação e ausência de erros de auth/RPC. Os testes de escrita já foram isolados; qualquer teste operacional de escrita requer solicitação real legitimamente autorizada, nunca dados fictícios em produção.
9. Se todos os checkpoints passarem, `update ro_private.folga_suspensao_criacao set ativo=false, atualizado_em=now() where chave='novas_folgas_campo';`. Confirmar false, gate true e manifesto distancia; monitorar erros e primeiras solicitações reais.
10. Registrar commit final publicado, deployment ID, migration, estados e logs. Não avançar se qualquer checkpoint falhar.

## Cache, abas antigas e reversão
- `vercel.json` define `Cache-Control: no-store, max-age=0, must-revalidate` e Content-Type JSON para o manifesto; verificar cabeçalhos **na URL canônica** em cada promoção, incluindo CDN. `fetch` usa `cache:no-store`. JS antigo pode continuar em memória: apenas o trigger SQL impede gravação incompatível.
- Ao falhar ANTES de liberar: manter suspensão true, manter gate false (ou voltar a false se já ativado), promover COMPAT **somente com a suspensão ativa**. Confirmar manifesto legado e rotas não Folga.
- Ao falhar DEPOIS de liberar: primeiro reativar suspensão true; avaliar solicitações já gravadas e riscos de desativar gate antes de qualquer mudança. Reverter gate/cliente coordenadamente; nunca apagar snapshots, históricos ou auditorias.
- Se reversão exigir mudança de dados existentes ou afetar outras funcionalidades, PARAR e solicitar autorização específica. Não restaurar todo o Supabase compartilhado.
- Não liberar COMPAT com gate true ou DISTANCIA com gate false e suspensão false. O servidor é a fonte de verdade.
