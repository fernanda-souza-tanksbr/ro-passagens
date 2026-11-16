-- C2: trava seletiva de novas Folgas, independente do gate de quilometragem.
-- PREPARACAO: NAO EXECUTAR EM PRODUCAO SEM AUTORIZACAO.
-- Instalar inicialmente com ativo=false; acionar antes da janela de deploy.
begin;
set local lock_timeout = '5s';
create table if not exists ro_private.folga_suspensao_criacao (
  chave text primary key check (chave='novas_folgas_campo'),
  ativo boolean not null default false,
  atualizado_em timestamptz not null default now()
);
insert into ro_private.folga_suspensao_criacao(chave,ativo)
values ('novas_folgas_campo',false) on conflict (chave) do nothing;
alter table ro_private.folga_suspensao_criacao enable row level security;
revoke all on ro_private.folga_suspensao_criacao from public,anon,authenticated;

create or replace function ro_private.bloquear_nova_folga_em_transicao()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.motivo='folga_campo'
     and exists (select 1 from ro_private.folga_suspensao_criacao
                 where chave='novas_folgas_campo' and ativo)
  then
    raise exception 'FOLGA_CAMPO_TEMPORARIAMENTE_SUSPENSA' using errcode='P0001';
  end if;
  return new;
end;
$$;
revoke all on function ro_private.bloquear_nova_folga_em_transicao() from public,anon,authenticated;
drop trigger if exists ro_00_suspender_novas_folgas_campo on public.ro_passagem_solicitacoes;
create trigger ro_00_suspender_novas_folgas_campo
before insert on public.ro_passagem_solicitacoes
for each row execute function ro_private.bloquear_nova_folga_em_transicao();
commit;

-- JANELA AUTORIZADA (executar separadamente):
-- update ro_private.folga_suspensao_criacao
-- set ativo=true, atualizado_em=now() where chave='novas_folgas_campo';
-- LIBERACAO / REVERSAO SEM PERDA DE HISTORICO:
-- update ro_private.folga_suspensao_criacao
-- set ativo=false, atualizado_em=now() where chave='novas_folgas_campo';
-- A trava incide somente em INSERT de motivo folga_campo, nao em UPDATE
-- de aprovacoes, historicos, ferias, desligamentos ou outros motivos.
