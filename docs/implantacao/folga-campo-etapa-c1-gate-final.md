# Folga de Campo por km — gate final da Etapa C1 (permissões)

**Situação:** somente preparação/homologação; **não aplicada no Supabase de produção**.
**Projeto:** Portal TanksBR `hukhwirdrpylxpaedjbc`, compartilhado com Obras Control.
**Dependências já aplicadas:** Etapa A `20261112192620` e Etapa B `20261113110519`.
**Branch:** `feat/folga-campo-regimes-distancia`.

## Arquivos versionados

- Aplicação (única migration proposta C1): `docs/implantacao/folga-campo-etapa-c1-permissoes-RASCUNHO.sql`
- Reversão pontual e transacional: `docs/implantacao/folga-campo-reversao-etapa-c1-RASCUNHO.sql`
- Matriz de testes de acesso: `tests/sql/folgaCampoC1PermissoesRole.sql`
- GitHub Actions PostgreSQL17: `.github/workflows/validar-folga-etapa-c1-pg17.yml`

## Decisão de segurança

A versão inicial do rascunho C1 era somente três GRANTs e permitiria chamar o endpoint de criação mesmo antes da ativação. A C1 revisada acrescenta `ro_private.autorizar_acesso_folga(uuid)` e um guard dentro das **três RPCs públicas novas**.

O guard faz:
1. Exige `auth.uid()` real, conta ainda existente no Auth, não excluída e não banida.
2. Exige `ro_private.folga_configuracao.ativo=true`; com gate desligado, rejeita **consultas, correções e criações** pelo novo fluxo.
3. Para `colaborador_id` de cadastro privado, exige `public.ro_can_view_private_addresses(auth.uid())=true`.
4. Nas consultas/criações de funcionário regular mantém `public.ro_funcionario_disponivel_para_usuario` e `ro_catalogo_centros_custo` existentes, preservando os escopos de visibilidade do RO Passagens. A consulta não inventa uma regra de titularidade individual: funcionários que o catálogo atual autoriza para um operador seguem visíveis. Usuários não devem acessar funcionários fora do catálogo.
5. Na correção, a função `ro_private.corrigir_distancia_folga` existente ainda exige coordenador, gerente ou operador RO ativo, justificativa com >=10 caracteres, bloqueios de concorrência e auditoria. Snapshots anteriores não mudam.
6. Sem grants em `ro_private`, sem SELECT/INSERT/UPDATE/DELETE direto nas tabelas novas, sem EXECUTE para `anon` ou `PUBLIC` nas três RPCs.

## Matriz final

| Tipo de usuário | RPC consulta contexto | RPC cria Folga km | RPC corrige distância | Tabelas privadas/dados diretos |
|---|---|---|---|---|
| Anônimo ou não autenticado | Negado | Negado | Negado | Negado |
| Autenticado ativo, usuário comum | Permitido somente após C2 e com CC/funcionário visíveis | Permitido somente após C2 e com validações legadas | Negado sem papel de correção | Negado |
| Coordenador ativo | Igual usuário ativo | Igual usuário ativo | Sim após C2, com justificativa/auditoria | Negado |
| Gerente ativo | Igual usuário ativo | Igual usuário ativo | Sim após C2, com justificativa/auditoria | Negado |
| Operador ativo RO | Igual usuário ativo | Igual usuário ativo | Sim após C2, com justificativa/auditoria | Negado |
| Auth excluído/banido | Negado | Negado | Negado | Negado |
| Cadastro privado sem vínculo | Apenas usuário com permissão privada existente, após C2 | Mesmo filtro e validação da RPC legada | Apenas perfil autorizado | Negado |
| Cadastro privado vinculado | Igual acima; funcionário vinculado como chave canônica | Igual acima | Apenas perfil autorizado | Negado |

**Enquanto `novo_fluxo_distancia=false`, TODOS os três endpoints novos rejeitam operações mesmo para authenticated autorizado.** As funções antigas de criação continuam disponíveis; C1 não as altera.

## Escopo exato de alteração planejada para produção

- Substituir **somente três definições novas já criadas em A/B**: `public.ro_consultar_contexto_distancia_folga`, `public.ro_criar_folga_campo_com_distancia`, `public.ro_corrigir_distancia_folga`, incluindo o guard, preservando suas assinaturas.
- Criar uma função auxiliar em `ro_private` sem uso externo.
- Conceder `EXECUTE` de **somente três RPCs novas** a `authenticated` e revogar explicitamente `PUBLIC`/`anon`.
- **Não** modificar funções/gatilhos legados do RO Passagens, funções de aprovação, compra, e-mail, férias, desligamento ou tabelas do Obras Control.
- **Não** habilitar fluxo, C2 ou deploy Vercel.
- Migration inclui `BEGIN/COMMIT`, `lock_timeout=5s`, `statement_timeout=120s`, preflight de objetos, gate desligado, hashes reais das funções e ausência de grants anteriores.

## Homologação

O banco temporário PostgreSQL 17 recebe fixture fictícia, A+B, C1, reversão pontual com restauração dos três hashes originais e nova C1. Testa `SET ROLE authenticated` e `SET ROLE anon`, bloqueio integral com gate false, testes de acesso com gate true **somente dentro de transação revertida**, conta banida/excluída, privado com/sem vínculo, consulta com identidade inexistente, tentativa de SELECT direto, correção autorizada por operador/coordenador/gerente, negação de usuário comum, justificativa, auditoria e imutabilidade do snapshot. O teste volta a zero registros e gate false ao final.

Limitação: as funções principais das etapas A/B são as homologadas, mas o cenário temporário ainda não clona a cadeia inteira de 29 gatilhos reais, Auth/JWT HTTP e dados de produção. Prova permissões PostgreSQL com papéis reais, não equivalência integral do aplicativo.

## Condições de implantação — somente mediante nova autorização

1. Confirmar backup Pro físico recuperável **próximo da execução**. Último confirmado em 13/11/2026 às 07h24min12s BRT. Registrar alerta sobre registros posteriores ao backup.
2. Confirmar `main` e deployment intactos; projetos A+B ativos; gate false; 43 migrations antes de C1; ausência de C1 parcial; hashes das três RPCs exatamente `bc6e1d8c6c5a5a2c5d3c4e91610eec91`, `c7d39b69c3297eb76c9da691ca7ceae2`, `2ae400e3e5ea5a9b702cf0e670156be9`; nenhum grant novo em conflito.
3. Aplicar **exatamente o SQL versionado** somente via `Supabase.apply_migration` nome `folga_campo_etapa_c1_permissoes`; não executar migrations antigas (históricos divergentes).
4. Confirmar `list_migrations` +1, gate false, três RPCs com EXECUTE authenticated e sem anon, sem USAGE de schema privado nem grants de tabela, RLS original, hash das funções/triggers antigos idêntico.
5. Confirmar por leitura a ausência de dados novos, estrutura de Obras Control intacta e sem erros relevantes nos logs. Não criar solicitações, compras ou notificações em produção.
6. Criar arquivo `supabase/migrations/<versao_gerada>_folga_campo_etapa_c1_permissoes.sql` com bytes idênticos ao SQL executado, na branch e sem merge/deploy.
7. Se pré-condição falhar, **não executar** e informar divergência.

## Reversão pontual

- Falha dentro da transação de aplicação: rollback PostgreSQL automático.
- C1 aplicada, gate false, ainda sem novos dados/etapas C2: executar a reversão SQL por migration própria, **somente após autorização de rollback**; restaura hashes B das 3 RPCs, revoga GRANTs novos e remove apenas o helper `ro_private.autorizar_acesso_folga`. Preserva A, B, tabelas, snapshots históricos e 29 triggers.
- Quando houver ativação, dados novos, ou alterações imprevistas, bloqueia a reversão automatizada; exige diagnóstico específico. Não restaurar banco compartilhado inteiro como primeira alternativa.
