# Limite de escopo — RO Passagens exclusivamente

Decisao confirmada em 2026-11-10: **nao modificar o sistema de alocacao de funcionarios, Obras Control ou qualquer outro aplicativo**. Os episodios chamados de "alocacao" nesta melhoria sao registros **internos do RO Passagens**, destinados somente a reutilizar quilometragem e determinar regime de Folga de Campo.

## Criacao atomica (desenho para implementacao)
1. A solicitacao de Folga de Campo e enviada pela tela atual, com CC explicitamente escolhido, km informado quando necessario e confirmacao quando houver retorno.
2. Uma RPC transacional, a ser implementada **no proprio banco do RO Passagens**, identifica usuario autenticado e verifica se ele pode solicitar para o funcionario, respeitando as permissoes ja existentes.
3. Adquirir lock transacional por funcionario. Ler episodio interno vigente e historico do CC selecionado. Se mudou o CC, encerrar episodio interno anterior e iniciar novo, mas **somente dentro da transacao de criacao**.
4. Primeiro CC: km inteiro obrigatorio. Mesmo CC: reutilizar km. Retorno ao CC: mostrar km historico e exigir confirmacao expressa. Correcoes continuam reservadas a coordenador/gerente/equipe RO, sem filtro por CC.
5. Derivar regime e intervalo no servidor; registrar snapshot imutavel por solicitacao.
6. Invocar a funcao existente `ro_criar_solicitacao_com_aprovador` sem reescrever o fluxo de aprovacao. **A atual trigger de ciclo deve estar atualizada na mesma implantacao**; caso contrario a nova RPC nao pode ser liberada.
7. Se a criacao falhar, rollback de todas as alteracoes internas de episodio, confirmacao e snapshot.
8. Nao atualizar `funcionarios`, `obras`, qualquer tabela oficial de lotacao/alocacao ou dados de Obras Control. Essas tabelas sao somente referencias de leitura.

## Pontos de atencao
- A funcao de criacao atual executa UPDATE depois do INSERT, portanto o trigger de Folga deve preservar o snapshot e nao reinterpretar a quilometragem em alteracoes de status/aprovacao.
- `ro_passagem_solicitacoes` e o historico existente continuam preservados; mudanca de CC nao altera solicitacoes anteriores.
- A confirmacao de retorno deve estar associada ao episodio novo e a pessoa autenticada, e nao somente a um checkbox enviado pelo navegador.
- Necessario revisar o caminho para viajantes cadastrados como colaboradores (`colaborador_id`) antes de aceitar solicitacoes de Folga nesse fluxo.
- Ainda nao ha RPC transacional executavel: preparar implementacao e testes, conferir triggers e restricoes, e aplicar somente com backup e autorizacao especifica.

## Criterios de aceite
- Criar Folga no mesmo CC nao pede km novamente.
- Mudar CC exige km novo; retornar a CC anterior exige confirmacao do km historico.
- Falha na criacao nao muda episodio interno.
- Nenhum dado oficial de alocacao ou outro aplicativo e escrito.
- Apenas os perfis autorizados corrigem km, independentemente do CC.
- Ultima Folga aprovada e finalizada ancora o proximo intervalo; antecipacao preserva justificativa e aprovacao.
