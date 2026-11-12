# Preflight somente leitura — Portal TanksBR / RO Passagens

Data de verificacao: 12/11/2026. Nenhuma alteracao em producao.

## Versao e integridade de referencia

- Supabase Portal TanksBR: project ref `hukhwirdrpylxpaedjbc`, status `ACTIVE_HEALTHY`, PostgreSQL 17.6.1.141 (engine 17), regiao us-east-2.
- GitHub privado `fernanda-souza-tanksbr/ro-passagens`: branch principal `main` no commit `908552a92e3d30bbfdf686dc5b313777c6a465a3`.
- Vercel `portal-tks-br`, ambiente production: deploy READY `dpl_26tjYVCFaGssCq4UYbTmm2Dku5Nj`, do mesmo commit e branch main.
- A branch de desenvolvimento `feat/folga-campo-regimes-distancia` nao foi mesclada na main nem implantada na producao.
- A funcao legada `ro_criar_solicitacao_com_aprovador(jsonb,jsonb)` permanece e coordena aprovador, atualizacao protegida de aprovacao, historico e notificacoes. A cadeia posterior valida PIX, hospedagem, documentos, identidade e outros campos.

## Compatibilidade de colaboradores privados

- `public.ro_funcionarios_enderecos_privados` possui `id`, `ativo` e `funcionario_id` opcional.
- A cadeia original insere `colaborador_id` e `funcionario_id` vinculado no pedido; colaboradores sem vinculo mantem `funcionario_id=null`.
- O modelo de episodio de CC da feature usa funcionario vinculado como chave canonica quando presente; caso contrario, colaborador privado.
- A consulta do frontend precisa aceitar que o servidor resolva `funcionario_id` para um cadastro privado: o formulario foi corrigido no commit `ac9afd7c46df046a1be60f9243b2a36a187a8fab`.
- Nao alterar registros de funcionarios, colaboradores privados ou a lotacao oficial para contornar vinculos ausentes.

## Autorizacao de correcao de distancia

- Coordenadores/gerentes por `public.user_roles`; operador RO ativo por `public.ro_is_operador_ativo`.
- Confirmado que `auth.users` disponibiliza `deleted_at` e `banned_until` para inibir correcao por conta excluida ou banida.
- Leitura agregada dos perfis corretivos existentes: 16 papeis, nenhum usuario inexistente no Auth, excluido ou banido no momento da verificacao.
- Rascunho 03 atualizado para exigir usuario Auth ativo, preservando a autorizacao global por funcao. Fixture SQL testa contas banidas e excluidas, sem dados reais.

## Revisao de seguranca

- Supabase Security Advisor consultado em modo somente leitura. Existem avisos preexistentes em objetos diversos (RLS sem policy, search_path mutavel e EXECUTE de SECURITY DEFINER). Como nao foi feito DDL de producao nesta feature, tais avisos nao derivam dela.
- Nenhuma mudanca geral de grants, RLS, funcoes do Obras Control ou do RO Passagens foi aplicada. Avaliar avisos em auditoria propria, sem misturar com este rollout.
- Novas RPCs continuam indisponiveis aos clientes no banco real, pois ainda nao existem ali.

## Backup: comprovacao pendente

A integracao Supabase disponivel aqui permite leitura de objetos e verificacao de status, **mas nao apresenta uma operacao de exportacao/restauracao ou comprovante de backup recuperavel**. Backups manuais de etapas anteriores nao substituem backup fresco preimplantacao. Antes do primeiro DDL, exigir comprovante de backup atualizado e estrategia de recuperacao validada.

## Restricoes antes de producao

1. A feature ainda nao foi executada com todas as funcoes e triggers reais em um ambiente homologado completo; fixtures isoladas usam mocks da cadeia existente.
2. Rascunhos SQL nao foram aplicados ao projeto de producao.
3. Interface permanece com `NOVO_FLUXO_FOLGA_ATIVO=false`.
4. Nao conceder EXECUTE nem ativar o gate de distancia ate demonstrar compatibilidade da cadeia real e obter autorizacao explicita.
5. Qualquer rollout requer recapturar commit main, deployment Vercel, definicoes e grants SQL para detectar mudancas desde o preflight.
