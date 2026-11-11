# Resultado da primeira execução real SQL em PostgreSQL descartável

Data: 11/11/2026. Projeto RO Passagens, branch `feat/folga-campo-regimes-distancia`.

## Execução

- GitHub Actions: `Folga de Campo - testes SQL isolados`.
- Execução aprovada: https://github.com/fernanda-souza-tanksbr/ro-passagens/actions/runs/43068797378
- PostgreSQL 16 temporário do GitHub Actions, banco fictício `folga_teste`.
- Nenhuma conexão com o Supabase de produção; nenhuma alteração na Vercel.
- Aplicados e executados de verdade os rascunhos **01, 08, 04, 10, 11 e 09**, em ordem controlada com triggers de INSERT/UPDATE.
- A primeira tentativa falhou por configurar a identidade simulada em uma conexão psql diferente. O teste foi ajustado em commit `9a5c7f1` e passou.

## Cenários exercitados com SQL real

1. Primeira folga e declaração de 200 km; verifica episódio, snapshot e intervalo de sete dias.
2. Nova obra sem km; exige km e comprova ausência de gravação.
3. Erro forçado *depois* da inserção na função legada simulada; comprova rollback de episódio, auditoria, pedido e contexto.
4. Nova solicitação no mesmo CC reutiliza km e episódio.
5. Troca de CC para 601 km cria episódio e snapshot, intervalo 45 dias, apenas um episódio ativo.
6. Retorno ao CC inicial sem confirmação é recusado; com confirmação cria novo episódio e preserva os anteriores.
7. UPDATE de status preserva snapshot e previsão; alteração direta de km histórico é rejeitada.
8. Limites 200/201, 600/601, 800/801, 1500/1501 e transporte aéreo acima de 1500 km.

## Limitações (impedem promoção a produção)

- A função legada `ro_criar_solicitacao_com_aprovador` e a checagem de duplicidade são **simulações**, não as funções reais de produção. Assim, a cadeia completa de aprovação, notificações, documentos, validação de elegibilidade e compra não foi testada em banco.
- Não foram testados concorrência com duas conexões, política completa de RLS para usuários autenticados, função 12 de consulta nem função 03 de correção de km.
- Os testes foram criados com uma única identidade fictícia de teste.
- Não há migração única, pronta e aprovada; os arquivos continuam classificados como rascunhos.
- O frontend permanece com a nova funcionalidade explicitamente desativada.
- Antes de publicar, revisar **todos os gatilhos existentes** e o comportamento transacional das funções legadas, incluindo aprovações e a política de documentos.

## Condição para avançar

Completar fixtures com permissões e concorrência, testar consulta e correção, consolidar migração e executar revisão de segurança. Produção somente depois de backup e autorização explícita.
