-- Backup da funcao de producao antes da alteracao de destino manual (09/11/2026).
-- Para reverter: executar a definicao abaixo e restaurar a constraint de origem conforme o arquivo da migracao.
CREATE OR REPLACE FUNCTION public.ro_aplicar_destino_residencial()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_end record;v_interpretado record;begin
 if new.motivo not in ('ferias','folga_campo','recesso') then new.destino_residencial_origem:=null;new.destino_residencial_justificativa:=null;return new;end if;
 if new.destino_residencial_origem='excepcional' then if length(trim(coalesce(new.destino_residencial_justificativa,'')))<10 then raise exception 'JUSTIFICATIVA_DESTINO_EXCEPCIONAL_OBRIGATORIA';end if;return new;end if;
 select cidade,uf into v_end from public.ro_funcionarios_enderecos_privados where id=new.colaborador_id or (new.colaborador_id is null and funcionario_id=new.funcionario_id) order by id=new.colaborador_id desc limit 1;
 if not found then raise exception 'ENDERECO_RESIDENCIAL_NAO_CADASTRADO';end if;
 select * into v_interpretado from public.ro_interpretar_cidade_uf_residencial(v_end.cidade,v_end.uf);
 if not v_interpretado.possui_endereco then raise exception 'ENDERECO_RESIDENCIAL_NAO_CADASTRADO';end if;
 new.destino:=v_interpretado.cidade||' / '||v_interpretado.uf;new.destino_residencial_origem:='rh';new.destino_residencial_justificativa:=null;return new;
end $function$
;
