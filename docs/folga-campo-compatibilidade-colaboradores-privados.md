# Bloqueio funcional: Folga de Campo de colaboradores privados

Leitura agregada do Supabase Portal TanksBR em 12/11/2026. Nenhuma escrita realizada.

## Evidencia (solicitacoes de Folga de Campo nao excluidas)

- Total: 76.
- Com `colaborador_id` (cadastro privado): 23.
- Desses, 20 possuem `funcionario_id` vinculado, 3 nao possuem vinculo.
- Com viajante manual: 0.

## Impacto tecnico

- O wrapper novo `ro_criar_folga_campo_com_distancia` recusa explicitamente `colaborador_id` e `viajante_nome_informado`. Ele nao pode ser ativado para TODAS as Folgas sem resolver este caso.
- `ro_folga_alocacoes.funcionario_id` e obrigatorio e tem FK a `public.funcionarios(id)`. Os tres viajantes privados sem vinculo nao podem receber episodio nesta tabela.
- Nao alterar o cadastro privado oficial nem a lotacao do Obras Control.
- Nao permitir que pedidos de colaboradores privados passem inadvertidamente pela RPC antiga se a politica for exigir distancia para todos: isso criaria comportamento desigual silencioso.
- A consulta futura deve autorizar os mesmos sujeitos que o catalogo/trigger atual e preservar o controle sobre endereco privado.
- Historico anterior permanece imutavel; a primeira declaracao de distancia deve ser realizada apenas no pedido novo valido.

## Decisao de negocio necessaria antes de ativar

Escolher entre:
(A) aplicar o novo regime a todas as Folgas de Campo, incluindo colaboradores privados com e sem vinculo a `funcionarios`; requer adaptar o modelo do episodio a duas identidades de viajante e ampliar os testes; ou
(B) habilitar primeiro somente para funcionarios padrao e manter os casos privados explicitamente no processo anterior, com regra de excecao visivel e documentada.

Recomendacao tecnica: A, para manter a regra de Folga uniforme e evitar exclusoes involuntarias.

## Seguranca

Nao executar DDL, criar perfis novos, atribuir funcionario ficticio ou mudar `funcionarios` para contornar a falta de vinculo. Todo o trabalho permanece na branch ate a decisao e os testes.
