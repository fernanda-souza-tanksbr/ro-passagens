\set ON_ERROR_STOP on
\ir ../../docs/implantacao/folga-campo-c2-suspensao-seletiva-RASCUNHO.sql
update ro_private.folga_suspensao_criacao set ativo=true where chave='novas_folgas_campo';
do $$
declare v public.ro_passagem_solicitacoes%rowtype;
begin
  v.motivo:='folga_campo';
  begin
    perform ro_private.bloquear_nova_folga_em_transicao() from (select 1) s;
    raise exception 'TESTE_NAO_VALIDOU_TRIGGER';
  exception when others then
    if sqlerrm <> 'trigger functions can only be called as triggers' then raise; end if;
  end;
end $$;
-- Executa INSERT pela tabela real do fixture: validacao dos demais motivos
-- ocorre no HTTP test-postgrest.sh, mantendo os outros gatilhos do baseline.
