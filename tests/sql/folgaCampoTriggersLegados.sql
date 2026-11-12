-- Apenas fixture PostgreSQL descartavel.
-- Representa a EXISTENCIA e nomes dos triggers ja instalados na producao.
-- As funcoes sao simulacoes, nao o SQL vigente no Supabase.
\set ON_ERROR_STOP on
create function public.ro_validar_ciclo_folga_campo()
returns trigger language plpgsql as $$
begin return new; end
$$;
create trigger ro_validar_ciclo_folga_campo
before insert or update of funcionario_id,motivo,data_ida,status,folga_antecipacao_justificativa
on public.ro_passagem_solicitacoes for each row
execute function public.ro_validar_ciclo_folga_campo();

create function public.ro_auditar_ciclo_folga_campo()
returns trigger language plpgsql as $$
begin return new; end
$$;
create trigger ro_auditar_ciclo_folga_campo
after insert or update of status on public.ro_passagem_solicitacoes for each row
execute function public.ro_auditar_ciclo_folga_campo();

select 'FOLGA_TRIGGERS_LEGADOS_FIXTURE_OK' as resultado;
