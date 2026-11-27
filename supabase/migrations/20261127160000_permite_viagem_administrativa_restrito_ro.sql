-- Ajuste restrito: viagem administrativa de empregados restrito_ro não operacionais.
-- Preserva o corpo, SECURITY DEFINER/INVOKER, search_path, ACL e demais regras
-- da funcao instalada. Aplicar manualmente depois da revisao, sem inserts.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $patch$
DECLARE
  v_def text;
  v_old text := $old$
  -- Sem nome avulso nem apenas funcionario_id. O passageiro deve constar
  -- no cadastro privado RO e possuir vínculo não operacional ou nenhum vínculo.
  if new.colaborador_id is null or new.viajante_nome_informado is not null then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  select e.ativo, e.funcionario_id
  into v_ativo, v_funcionario_vinculado
  from public.ro_funcionarios_enderecos_privados e
  where e.id=new.colaborador_id;
  if not coalesce(v_ativo,false) then
    raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
  end if;
  if new.funcionario_id is distinct from v_funcionario_vinculado then
    raise exception 'VIAGEM_ADMINISTRATIVA_VINCULO_DIVERGENTE';
  end if;

  -- O vínculo só é permitido quando não pertence ao cadastro operacional.
  if v_funcionario_vinculado is not null then
    select coalesce(f.visivel_obras_control,true)
    into v_vinculo_operacional
    from public.funcionarios f where f.id=v_funcionario_vinculado;
    if coalesce(v_vinculo_operacional,true) then
      raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
    end if;
  end if;
$old$;
  v_new text := $new$
  -- Passageiros privados continuam sujeitos às verificações originais.
  -- Funcionarios internos restritos do RO, nao operacionais, podem usar
  -- viagem administrativa sem precisar de cadastro privado duplicado.
  if new.colaborador_id is null then
    if new.viajante_nome_informado is not null
       or new.funcionario_id is null
       or not exists (
         select 1
           from public.funcionarios f
          where f.id = new.funcionario_id
            and f.ativo is true
            and f.deleted_at is null
            and f.visivel_obras_control is false
            and f.visivel_passagens is true
            and f.escopo_passagens = 'restrito_ro'
       ) then
      raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
    end if;
  else
    if new.viajante_nome_informado is not null then
      raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
    end if;
    select e.ativo, e.funcionario_id
      into v_ativo, v_funcionario_vinculado
      from public.ro_funcionarios_enderecos_privados e
     where e.id = new.colaborador_id;
    if not coalesce(v_ativo, false) then
      raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
    end if;
    if new.funcionario_id is distinct from v_funcionario_vinculado then
      raise exception 'VIAGEM_ADMINISTRATIVA_VINCULO_DIVERGENTE';
    end if;
    if v_funcionario_vinculado is not null then
      select coalesce(f.visivel_obras_control, true)
        into v_vinculo_operacional
        from public.funcionarios f
       where f.id = v_funcionario_vinculado;
      if coalesce(v_vinculo_operacional, true) then
        raise exception 'VIAGEM_ADMINISTRATIVA_PASSAGEIRO_INELEGIVEL';
      end if;
    end if;
  end if;
$new$;
BEGIN
  IF to_regprocedure('public.ro_validar_passageiro_viagem_administrativa()') IS NULL THEN
    RAISE EXCEPTION 'FUNCAO_VIAGEM_ADMINISTRATIVA_AUSENTE';
  END IF;

  SELECT pg_get_functiondef('public.ro_validar_passageiro_viagem_administrativa()'::regprocedure)
    INTO v_def;

  -- Executa somente na versao com o bloco original exato (uma ocorrencia).
  IF v_def IS NULL OR
    (length(v_def) - length(replace(v_def, v_old, ''))) <> length(v_old) THEN
    RAISE EXCEPTION 'REGRA_VIAGEM_ADMINISTRATIVA_DIVERGENTE: nao foi aplicada';
  END IF;

  IF v_def NOT LIKE '%if new.data_retorno is not null and new.data_retorno < new.data_ida then%' THEN
    RAISE EXCEPTION 'VALIDACAO_RETORNO_AUSENTE: nao foi aplicada';
  END IF;

  EXECUTE replace(v_def, v_old, v_new);

  IF pg_get_functiondef('public.ro_validar_passageiro_viagem_administrativa()'::regprocedure)
     NOT LIKE '%f.escopo_passagens = ''restrito_ro''%' THEN
    RAISE EXCEPTION 'FALHA_VALIDACAO_REGRA_RESTRITO_RO';
  END IF;
END
$patch$;

COMMIT;

-- Validacao somente leitura apos COMMIT:
-- SELECT position('f.escopo_passagens = ''restrito_ro''' IN
--   pg_get_functiondef('public.ro_validar_passageiro_viagem_administrativa()'::regprocedure)) > 0
-- AS restrito_ro_habilitado;
