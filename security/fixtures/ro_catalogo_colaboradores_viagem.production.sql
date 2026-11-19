-- READ-ONLY SNAPSHOT: pg_get_functiondef(public.ro_catalogo_colaboradores_viagem())
-- Source: production Portal TanksBR, 2026-11-19. This is NOT a migration.
CREATE OR REPLACE FUNCTION public.ro_catalogo_colaboradores_viagem()
 RETURNS TABLE(id uuid, nome text, funcionario_id uuid, ativo boolean, visivel_obras_control boolean, visivel_passagens boolean, escopo_passagens text, obra_id uuid, obra_nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select f.id,
         f.nome,
         f.id,
         true,
         f.visivel_obras_control,
         f.visivel_passagens,
         f.escopo_passagens,
         atual.obra_id,
         o.nome
  from public.funcionarios f
  left join lateral(
    select a.obra_id
    from public.alocacoes a
    where a.funcionario_id=f.id
    order by a.data desc
    limit 1
  ) atual on f.visivel_obras_control
  left join public.obras o on o.id=atual.obra_id
  where public.ro_funcionario_disponivel_para_usuario(auth.uid(),f.id)

  union all

  select e.id,
         e.nome,
         null::uuid,
         true,
         false,
         true,
         'restrito_ro'::text,
         null::uuid,
         null::text
  from public.ro_funcionarios_enderecos_privados e
  where auth.uid() is not null
    and e.ativo
    and e.funcionario_id is null

  order by 2;
$function$;
