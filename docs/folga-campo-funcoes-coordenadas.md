# Atualizacao coordenada de funcoes — Folga de Campo

**Status:** especificacao para revisao; NAO EXECUTAR EM PRODUCAO.

## Funcoes reais verificadas em leitura (2026-11-09)
- `ro_criar_solicitacao_com_aprovador(jsonb,jsonb)`: verifica autenticacao e aprovador, chama `ro_criar_solicitacao_colaborador_validada`, aplica `aprovacao_status` e notifica. **Preservar assinatura e corpo; nao substituir.**
- `ro_criar_solicitacao_colaborador_validada`: delega a `_pre_rh_manual` e depois a `_pre_operacional`. Evitar reescrever esta cadeia.
- `ro_obter_ciclo_folga_funcionario(uuid)`: atualmente busca finalizadas sem filtrar aprovacao e usa `coalesce(folga_data_prevista_ciclo,data_ida)+90`. Manter a assinatura antiga para consumidores legados ate migracao.
- `ro_validar_ciclo_folga_campo()`: trigger antes de insert/update; verifica duplicata, calcula antecipacao, exige justificativa e preserva aprovacao existente quando cabivel. **Preservar verificacoes de duplicata, justificativa e aprovacoes.**
- `ro_auditar_ciclo_folga_campo()`: trigger de auditoria; atualmente registra `folga_data_prevista_ciclo+90`. Ajustar somente quando snapshot e regime estiverem disponiveis.
- `ro_aprovar_antecipacao_folga(uuid)`: aprovacao exclusiva de operador RO; manter inalterada.
- `ro_bloquear_compra_folga_pendente` e `ro_bloquear_compra_antecipacao_pendente`: manter inalteradas.

## Ordem obrigatoria de implantacao
1. Backup verificavel e roteiro de rollback; obter autorizacao especifica antes de qualquer escrita no Supabase principal.
2. Criar estruturas internas para **episodios de alocacao**, declaracoes/correcoes e snapshot imutavel por solicitacao. Nao basta indice unico funcionario+CC, pois retorno ao mesmo CC requer confirmacao.
3. RLS/grants minimos, verificacao de papeis na RPC (nao no frontend), log de autor e valores antes/depois; validar compatibilidade com funcionario/colaborador e identidade de quem pode declarar.
4. Nova RPC de consulta de contexto com parametros funcionario e **CC atual**, devolvendo km salvo, se exige confirmacao, historico valido, intervalo e proxima data. Nao assumir que CC de transferencia ou retorno e CC atual.
5. RPC atomica de registro/confirmacao de distancia e criacao da solicitacao; preservar `ro_criar_solicitacao_com_aprovador` e sua cadeia. Validar servidor-side a distancia inteira e o regime derivado, nunca confiar no snapshot recebido do navegador.
6. Trigger de ciclo: basear a proxima data na **data_ida real** da Folga anterior finalizada e aprovada/dispensada, usando intervalo do CC atual; garantir que UPDATE de status/aprovacao nao reinterprete pedidos antigos com novo CC/regime.
7. Trigger de auditoria: registrar a data real de referencia, km, faixa, intervalo e proxima data derivada; nunca usar +90 fixo.
8. Integrar `src/FolgaCampoQuilometragem.tsx` ao `NovaSolicitacao`, com consulta dependente de funcionario/motivo/**obra_id**, controle de respostas antigas e validacao de confirmacao. Integrar a RPC de escrita apenas depois do banco.
9. Testar fluxo completo: primeira folga, troca de CC, retorno ao mesmo CC, correcao autorizada e negada, aprovacoes dispensadas, antecipacao pendente/aprovada, compra bloqueada, pedidos pendentes sem recalc retroativo e migracao de registros legados.
10. Publicar somente com aprovacao final.

## Contratos de dados propostos (nao existentes ainda)
Consulta: `ro_obter_contexto_folga_campo(p_funcionario_id uuid,p_obra_id uuid)` -> `{distancia_km, retorno_ao_cc, requer_confirmacao, ultima_folga_realizada, proxima_folga_prevista, intervalo_dias, transporte}`.
Criacao: manter `ro_criar_solicitacao_com_aprovador(p_solicitacao,p_documentos)` como entrada publica; a camada de persistencia deve aceitar dados de declaracao apenas em transacao e calcular snapshot no servidor. A implementacao exata depende de examinar as constraints/triggers e permissao de declaracao.
Correcao: RPC restrita a perfis autorizados; somente alocacao vigente/futuros pedidos, log em `ro_auditoria_interna` com anterior/novo e usuario.

## Bloqueios para producao
Nao aplicar funcoes SQL incompletas, nao mudar o calculo isoladamente, nao enviar snapshot ao RPC antigo, nao usar `CREATE OR REPLACE` sem revisar dependencias, nao conceder EXECUTE publico a funcoes privilegiadas. Testes locais nao substituem validacao integrada.
