# Folga C2 — homologação React e transição compatível (16/11/2026)

## Limite estrito
Nenhuma mudança em Supabase ou Vercel de produção; sem merge em main; sem cobrança de serviços e sem e-mails/compras reais. A flag SQL continua `novo_fluxo_distancia=false`.

## Homologação integrada sem custos extras
GitHub Actions `.github/workflows/validar-folga-c2-react.yml` compila o projeto Vite/React da **branch real** com SDK `@supabase/supabase-js` original e URL fictícia `http://127.0.0.1:4174`. Os testes `tests/e2e/folgaCampoReactIntegrado.spec.ts` abrem `/nova`, fazem login via método `signInWithPassword`, carregam catálogos e verificam que o cliente constrói chamadas `ro_consultar_contexto_distancia_folga`.

O Auth **HTTP é simulado** e as RPCs HTTP **são interceptadas por Playwright** no processo do runner; nenhum serviço Auth/PostgREST real é iniciado. O token, identidades, funcionários, obras e aprovações são fictícios. Conexões externas são bloqueadas. Isso é integração real de interface e SDK, mas não comprova semântica do Supabase Auth em rede real.

As regras, acesso `authenticated`, RLS, auditoria, RPC e triggers continuam nos workflows PostgreSQL 17 previamente preparados e executados isoladamente. Ainda não existe suíte contendo a cadeia HTTP Supabase Auth/PostgREST + PostgreSQL original inteira num único serviço efêmero; para tal seria preciso iniciar GoTrue/PostgREST/PG17 em GitHub Actions, sem ambiente do usuário, com mais preparação e testes. Não afirmar cobertura onde só há mock.

## Matriz de transição (respeitar gatilhos B)
- **Frontend antigo + SQL false:** funcionamento antigo permitido.
- **Frontend novo com build flag false + SQL false:** mesma compatibilidade.
- **Frontend novo com build flag true + SQL false:** a nova RPC rejeita corretamente; não liberar formulário assim.
- **Frontend novo com build flag true + SQL true:** caminho novo após habilitação.
- **Frontend antigo + SQL true:** a RPC legada para `folga_campo` é deliberadamente bloqueada pelo gatilho B; não é seguro relaxar, pois contornaria as regras de km.

## Decisão técnica
Uma transição inteiramente transparente para abas antigas **não é garantível** sem permitir que clientes desatualizados contornem a nova validação. A solução recomendada é manter gatilho B, implementar aviso de atualização do cliente quando a versão do site mudar e agendar uma **janela restrita de manutenção de novas solicitações de Folga de Campo**; demais motivos, relatórios, Obras Control e rotinas RO permanecem operacionais.

### Checklist de execução futura, dependente de autorização separada
1. Antes: backup recente disponível, logs e hashes A/B/C1, 44 migrations, status Vercel, teste Auth/RPC completo, aviso de manutenção para solicitantes, equipe RO e coordenação.
2. Preparar frontend definitivo e canários sem apontá-los para produção antes da liberação. Os previews atuais `portal-tks-br` compartilham `VITE_SUPABASE_*` com produção e não são isolados.
3. Informar início da janela: **novas Folgas temporariamente suspensas**; outras solicitações e demais operações devem continuar.
4. Publicar frontend aprovado e validar assets/versão em aba recém-aberta, mantendo gate SQL false durante a troca.
5. Ativar **somente a migration C2 autorizada**. Validar em leitura `ativo=true`, grants, assinaturas e hashes do backend.
6. Requerer atualização/recarregamento de abas antigas antes de novas Folgas. Servir comunicado explícito e bloquear submissões da versão antiga. Não liberar fallback para criação legada.
7. Encerrar janela somente após conferir nova interface, submissão canário autorizada, antecipações e bloqueios de compra. Verificar outros motivos e Obras Control.
8. Monitorar falhas das RPCs e notificações. Registrar tempos, commit/deploy, versão da migration e ocorrências.

### Reversão
Se gate SQL true + frontend novo falhar: suspender **novas Folgas**, diagnosticar primeiro. Com autorização específica, desligar gate C2 e restaurar frontend anterior (build flag false), garantindo ambos compatíveis. Preservar episódios, snapshots e auditoria. Evitar o arquivo de reversão antigo que também revoga grants C1, a menos que realmente necessário; preferir rollback mínimo e versionado que altere apenas a flag, mantendo grants e DDL intactos. Não restaurar banco inteiro compartilhado e não excluir dados.

## Pendências de aprovação
Homologar visualmente a interface; comprovar funcionamento Auth + RPC via serviços reais isolados ou aceitar explicitamente separação Playwright HTTP mock + PostgreSQL17; implementar e testar aviso de versão antiga ou adotar janela operacional com comunicação e controle de submissões. Somente então propor data e autorização da publicação.
