-- Permite destino manual somente quando nao existe endereco residencial valido no RH.
-- Backup: database/backups/20261109_ro_aplicar_destino_residencial_before_manual.sql
ALTER TABLE public.ro_passagem_solicitacoes DROP CONSTRAINT ro_destino_residencial_origem_ck;
ALTER TABLE public.ro_passagem_solicitacoes ADD CONSTRAINT ro_destino_residencial_origem_ck CHECK (destino_residencial_origem IS NULL OR destino_residencial_origem IN ('rh','excepcional','manual'));
CREATE OR REPLACE FUNCTION public.ro_aplicar_destino_residencial()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
declare v_end record; v_interpretado record;
begin
  if new.motivo not in ('ferias','folga_campo','recesso') then
    new.destino_residencial_origem:=null;
    new.destino_residencial_justificativa:=null;
    return new;
  end if;
  if new.destino_residencial_origem='excepcional' then
    if length(trim(coalesce(new.destino_residencial_justificativa,'')))<10 then
      raise exception 'JUSTIFICATIVA_DESTINO_EXCEPCIONAL_OBRIGATORIA';
    end if;
    return new;
  end if;
  select cidade,uf into v_end
  from public.ro_funcionarios_enderecos_privados
  where id=new.colaborador_id
     or (new.colaborador_id is null and funcionario_id=new.funcionario_id)
  order by id=new.colaborador_id desc limit 1;
  if found then
    select * into v_interpretado
    from public.ro_interpretar_cidade_uf_residencial(v_end.cidade,v_end.uf);
  end if;
  if coalesce(v_interpretado.possui_endereco,false) then
    if new.destino_residencial_origem='manual' then
      raise exception 'DESTINO_MANUAL_NAO_PERMITIDO_COM_ENDERECO_RH';
    end if;
    new.destino:=v_interpretado.cidade||' / '||v_interpretado.uf;
    new.destino_residencial_origem:='rh';
    new.destino_residencial_justificativa:=null;
    return new;
  end if;
  if new.destino_residencial_origem='rh' then
    -- Sem endereco RH, preserva o destino informado, sem justificativa excepcional.
    new.destino_residencial_origem:='manual';
  elsif new.destino_residencial_origem is distinct from 'manual' then
    raise exception 'DESTINO_RESIDENCIAL_ORIGEM_INVALIDA';
  end if;
  if length(btrim(coalesce(new.destino,'')))<3 then
    raise exception 'DESTINO_MANUAL_OBRIGATORIO';
  end if;
  new.destino_residencial_justificativa:=null;
  return new;
end
$function$;
