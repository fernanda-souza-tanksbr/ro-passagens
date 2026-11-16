# Etapa C2 — Transição coordenada (NÃO EXECUTAR SEM AUTORIZAÇÃO)

## Estado atual
- Branch de desenvolvimento somente; manifesto `public/folga-campo-release.json` inicia em `{"modo":"legado","versao_minima":2}`.
- A chave `novo_fluxo_distancia` do Supabase de produção permanece falsa.
- Não modificar Obras Control nem criar deploy de produção como parte desta homologação.
- O manifesto de versão é um aviso ao cliente, **não é barreira de segurança**. A barreira obrigatória é o gatilho SQL existente da Etapa B, que bloqueia Folga de Campo legada quando a chave estiver ativa.

## Pré-condições obrigatórias
1. Backup validado e versão de referência de GitHub/Vercel/Supabase registrada.
2. Homologação real de Auth, PostgREST, RLS e RPCs, ou aceitação explícita dos riscos residuais.
3. Verificar que a build de destino contém o novo código de versão, o manifesto e a flag `VITE_FOLGA_CAMPO_KM_ENABLED=C2_PRODUCAO_APROVADA` **somente quando autorizada**.
4. Validar em isolamento a ordem de ativação e plano de reversão, incluindo o Obras Control.

## Ordem proposta para uma futura janela autorizada
1. Publicar primeiro o cliente de compatibilidade com a flag nova **desligada** e manifesto em modo `legado`. Confirmar férias, desligamentos e operações usuais.
2. Em publicação separada, colocar manifesto em `transicao` e confirmar que novas Folgas são suspensas no cliente atualizado; os demais motivos continuam. **Abas antigas podem não ler o manifesto**; não depender só desta etapa.
3. Em janela curta e autorizada, ativar o gate SQL `novo_fluxo_distancia` no banco somente após conferir a versão de destino; o gatilho da Etapa B então impede Folga legada inclusive de abas antigas. A consulta C1 e a RPC nova dependem desse gate.
4. Publicar cliente novo com flag ativada e manifesto `distancia` (versão mínima 2), validar em sessão nova e aba antiga, depois liberar a janela. Evitar intervalo prolongado entre gate e novo cliente.
5. Conferir ausência de gravações incompatíveis, logs, solicitação fictícia somente em ambiente isolado; em produção, usar validação operacional autorizada, sem compras nem emails de teste não aprovados.

## Reversão
- Não reverter migrations A/B/C1 sem análise de dependências e backup.
- Se houver falha antes do gate, restaurar manifesto `legado` e cliente anterior.
- Após gate, não voltar simplesmente à versão legada: isso bloqueará novas Folgas. Manter suspensão em `transicao`, avaliar dados já gravados e executar reversão coordenada autorizada do gate/cliente.
- Abas antigas não são atualizáveis retroativamente. O servidor deve continuar rejeitando a RPC legada de Folga quando o gate estiver ativo.
- Não usar uma alteração do manifesto como mecanismo de controle do banco.

## Evidência e limites
- Testes Playwright com React verdadeiro e HTTP simulado comprovam renderização e aviso, não RLS/PostgREST real.
- O repositório contém somente as migrations incrementais A/B/C1 do novo fluxo, sem baseline integral das tabelas/funções históricas. `supabase db reset` sobre banco vazio não reproduz o Portal TanksBR; não marcar testes reais de RPC como aprovados até reconstruir um baseline fictício consistente.
- Nenhum serviço pago é necessário para GitHub Actions com containers efêmeros, sujeito às cotas de minutos do plano GitHub. Não habilitar ações que possam gerar cobrança adicional.
