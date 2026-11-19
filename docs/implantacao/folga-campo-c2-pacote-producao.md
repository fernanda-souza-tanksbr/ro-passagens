# C2 — pacote de produção da Folga de Campo semanal

- Código funcional homologado: `14de85b0670c4be12faa9fa03c49abed23c438f2`.
- Migração de produção: `sql/folga_semanal_c2_producao.sql`.
- Fonte executável imutável: `sql/folga_semanal_trigger_draft.sql` no SHA homologado. A migração contém exatamente o mesmo trecho executável desde `CREATE OR REPLACE FUNCTION` até o `CREATE TRIGGER` final; somente cabeçalho e guardas SQL anteriores foram acrescentados.
- Rollback de referência: `sql/folga_semanal_rollback.sql` no SHA homologado. Este rollback contém `BEGIN/COMMIT`; executar somente em ferramenta que não encapsule automaticamente uma transação, ou remover apenas esses delimitadores externos no executor transacional.
- A migração de produção não contém `BEGIN/COMMIT` porque `Supabase apply_migration` gerencia a transação.
- Pré-condições: hash MD5 da função original `5bf4dee929b2b07344f9ff52b2bf2e45`; trigger original exato; gate `novo_fluxo_distancia=true`; suspensão seletiva `novas_folgas_campo=true`. Falha em qualquer guarda interrompe o DDL.
- Antes de migrar: registrar a definição original, confirmar deployment DISTANCIA READY e sem aliases, ativar suspensão seletiva e confirmar somente Folga bloqueada; não realizar INSERT de teste em produção.
- Depois de migrar: comparar definição instalada com a parte executável homologada, verificar novo trigger e gate; promover deployment preparado, verificar manifesto DISTANCIA, autenticação e RPCs em leitura; somente então liberar suspensão.
- Não alterar snapshots nem solicitações existentes.
- **Restrição de rollback:** após novas solicitações no regime semanal/distância, não aplicar automaticamente o rollback antigo. Suspender novas Folgas, inspecionar solicitações criadas e dependências, avaliar compatibilidade dos snapshots e obter autorização específica. Não apagar registros, nem restaurar todo o banco.
