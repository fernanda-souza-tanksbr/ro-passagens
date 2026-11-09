# Decisoes aprovadas — alocacao e autorizacao global

## Regra de alocacao
Ao selecionar um CC diferente do CC vigente **numa nova Folga de Campo**, considerar transferencia de alocacao para esse CC. Registrar novo episodio apenas na transacao de criacao bem-sucedida, nunca apenas ao alterar a selecao do formulario. Retorno ao CC anterior: exibir km historico e exigir confirmacao. A mudanca nao reinicia o historico da ultima folga valida. Preservar CC e snapshot dos pedidos anteriores.

## Regra de correcoes
Autorizar globalmente usuarios com role `coordenador` ou `gerente` em `public.user_roles`, e integrantes ativos da equipe RO por `public.ro_is_operador_ativo(auth.uid())`. Nao limitar por CC. Consultar papeis atuais em cada RPC; nunca confiar no frontend. Exigir autenticacao, registrar quem, quando, valor anterior e novo; aplicar apenas a futuros pedidos.

**Verificacao do esquema existente:** `public.app_role` possui `assistente`, `supervisor`, `coordenador`, `gerente`, `diretor`. Nao existe enum `ro`; a equipe RO e identificada em `ro_responsaveis` pela funcao existente `ro_is_operador_ativo`. A regra aqui nao concede autorizacao automaticamente a `diretor`, `supervisor` ou `assistente`, salvo se tambem integrarem a equipe RO.

## Predicado SQL proposto para a RPC de correcao
```sql
if auth.uid() is null or not (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role::text in ('coordenador','gerente')
  )
  or public.ro_is_operador_ativo(auth.uid())
) then
  raise exception 'CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA';
end if;
```

## Pendencias de implementacao
Verificar status ativo dos usuarios e demais funcoes de acesso existentes antes de publicar. Criar RPC transacional de alocacao + criacao, com lock por funcionario; vincular episodio e snapshot a solicitacao. A correcao deve atualizar somente o episodio vigente, preservando snapshots anteriores. Nenhuma funcao foi aplicada no Supabase.
