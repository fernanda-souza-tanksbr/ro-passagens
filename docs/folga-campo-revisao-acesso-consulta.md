# Revisao de autorizacao da consulta de quilometragem

Verificacao somente leitura no Supabase Portal TanksBR em 11/11/2026.

## Resultado

- `ro_is_operador_ativo(auth.uid())` identifica operadores RO ativos.
- `ro_is_rh_active(auth.uid())` identifica responsaveis RH ativos.
- `ro_criar_solicitacao_validada` delega as validacoes de criacao para `ro_criar_solicitacao_validada_pre_operacional`; portanto nao e seguro assumir que todo usuario autenticado pode consultar o historico de qualquer funcionario.
- O rascunho 12, sendo SECURITY DEFINER, ainda NAO implementa uma politica de acesso por funcionario. Seus grants devem continuar revogados.
- Nao conceder permissao apenas com base em autenticacao. Precisamos examinar a politica real de solicitante/funcionario e os caminhos de colaborador privado.

## Decisao de seguranca

Nao publicar a RPC de consulta ate que a autorizacao seja implementada e testada para: solicitante regular, operador RO, RH, usuario sem acesso ao funcionario, funcionario de outro CC e colaborador privado.

A camada frontend `consultarContextoFolga` ja falha de forma fechada: erro de RPC nao equivale a ausencia de km.
