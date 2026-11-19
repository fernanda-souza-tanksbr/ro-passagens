# Auditoria de confidencialidade de desligamentos — 2026-11-19

STATUS: INVESTIGACAO / NAO APROVADO PARA PRODUCAO. Nenhuma mudanca aplicada ao Supabase.

## Regra obrigatoria
Para motivo = 'desligamento', em qualquer subtipo/status: somente solicitante_id = auth.uid() OU integrante ativo de public.ro_responsaveis (ro_can_operate()). Identidade de passageiro, gerente, RH, diretor, aprovador ou admin isoladamente NAO autoriza. Outros motivos preservados. Excluidas continuam sujeitas a regra existente, salvo acesso RO.

## Vulnerabilidades verificadas em catalogo de producao (somente leitura)
- ro_sol_select: permite todos usuarios internos ativos para registros nao excluidos.
- ro_nomes_colaboradores_solicitacoes: SECURITY DEFINER retorna nome sem checar solicitante/RO.
- ro_custos_operacionais_visiveis: SECURITY DEFINER retorna valores de custos sem checar solicitante/RO.
- ro_solicitacao_foi_comprada: SECURITY DEFINER booleano sem auth; permite inferencia de status.
- ro_ultimo_pix_viajante: SECURITY DEFINER busca historico de solicitacoes por identidade, sem filtro por motivo/autorizacao; pode expor PIX.
- ro_relatorio_centros_custo: SECURITY DEFINER inclui desligamentos em agregados e lista de responsaveis, autorizado via ro_can_view_all().
- ro_can_view_internal_document: permite RH, gerente, diretor ou criador do documento; precisa excecao de desligamento.
- ro_auditoria_interna: SELECT via ro_can_manage_rh() OR ro_can_view_internal_document(); precisa restricao por solicitacao.
- ro_passagem_documentos_internos e storage.objects (ro_internal_storage_select): dependem da funcao acima.
- ro_passagem_custos: SELECT via ro_can_view_all() sem filtro por solicitacao.
- ro_passagem_notificacoes: SELECT permite aprovador, sem filtro por motivo.
- ro_listar_minhas_notificacoes: SECURITY DEFINER retorna notificacoes aprovador sem filtro por motivo.
- ro_passagem_anexos, ro_passagem_historico, ro_resolucao_operacional e storage.objects ro_storage_select: SELECT vinculado a RLS da solicitacao; confirmar comportamento de OR com policies FOR ALL.
- ro_obter_dados_emissao_passagem: restrito a operador RO ativo, preservar.
- ro_email_logs: SELECT via ro_can_view_all(), precisa verificar metadados e correlacao.
- storage.objects: avaliar buckets privados, signed URLs ja emitidas, policies INSERT/UPDATE/DELETE e download.
- public.notificacoes: gerentes veem todas, procurar referencias a desligamentos em mensagens/metadata.
- revisar todas as demais funcoes SECURITY DEFINER que consultam solicitacoes, incluindo retornos indiretos, EXISTS, COUNT, JSON e funcoes de escrita com retorno.

## Estrategia
1. Capturar definicoes exatas pg_get_functiondef, pg_get_expr, grants, triggers, views, storage policies e esquema C2 do banco instalado. Registrar hashes para preflight e rollback.
2. Criar funcao interna de autorizacao por solicitacao (sem confiar em user_metadata) e aplicar a todas as saidas de dados. Evitar recursao RLS, controlar EXECUTE e search_path.
3. Preservar ro_can_operate() para todos RO ativos, inclusive compra, custos, anexos, finalizacao e cancelamento.
4. Aplicar migracao unica transacional, com lock_timeout curto, verificacoes de precondicao, sem emails ou alteracao de dados.
5. Testar com PostgreSQL 17 isolado, esquema de producao sem dados reais, usuarios ficticios, RLS REST/RPC/storage, testes positivos RO/solicitante e negativos passageiro/gerente/aprovador/RH/admin, multiplas identidades, todos status, e regressao motivos nao desligamento/C2.
6. Frontend React real em ambiente de teste isolado; confirmar 404/estado vazio para acesso negado e nenhuma falha de carregamento.
7. Somente depois de homologacao: janela autorizada, snapshot de definicoes, aplicar SQL sem rebuild frontend, smoke tests RO e rollback SQL imediato em caso de regressao.

## Bloqueadores
Nao promover o rascunho security/drafts/desligamento_ro_sol_select.sql isoladamente.
Nenhum teste isolado ou homologacao frontend foi executado ainda.
Nao alterar producao, aliases, Ignored Build Step ou fluxo C2.
