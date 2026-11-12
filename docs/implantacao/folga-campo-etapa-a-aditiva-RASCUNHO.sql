-- RASCUNHO - ETAPA A / ADITIVA, NAO EXECUTAR NA PRODUCAO.
-- Nenhum trigger existente sera alterado. As RPCs continuam sem EXECUTE.
-- Exige backup, verificacao da versao de referencia e autorizacao.
begin;
do $guard$
begin
  if to_regclass('public.ro_passagem_solicitacoes') is null
    or to_regclass('public.funcionarios') is null
    or to_regclass('public.obras') is null
    or to_regprocedure('public.ro_criar_solicitacao_com_aprovador(jsonb,jsonb)') is null
  then raise exception 'PREFLIGHT_RO_PASSAGENS_INCOMPATIVEL'; end if;
end
$guard$;

-- ===== ORIGEM: docs/sql/folga-campo-01-estruturas-RASCUNHO.sql =====
-- RASCUNHO NAO EXECUTAR EM PRODUCAO
-- Etapa 1: estruturas aditivas, sem substituir funcoes ou triggers existentes.
-- Revisar backup, autorizacoes, politicas e dependencias antes de executar.

create table if not exists public.ro_folga_alocacoes (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  obra_id uuid not null references public.obras(id),
  iniciada_em timestamptz not null default now(),
  encerrada_em timestamptz,
  distancia_km integer not null check (distancia_km >= 0),
  confirmada_em timestamptz,
  confirmada_por uuid,
  origem_alocacao_id uuid references public.ro_folga_alocacoes(id),
  criado_em timestamptz not null default now(),
  constraint ro_folga_alocacoes_datas check (encerrada_em is null or encerrada_em >= iniciada_em)
);
create unique index if not exists ro_folga_alocacao_ativa_unica
  on public.ro_folga_alocacoes(funcionario_id)
  where encerrada_em is null;
create index if not exists ro_folga_alocacoes_funcionario_obra
  on public.ro_folga_alocacoes(funcionario_id,obra_id,iniciada_em desc);
alter table public.ro_folga_alocacoes enable row level security;
revoke all on public.ro_folga_alocacoes from anon,authenticated;

create table if not exists public.ro_folga_distancia_auditoria (
  id bigint generated always as identity primary key,
  alocacao_id uuid not null references public.ro_folga_alocacoes(id),
  distancia_anterior_km integer check (distancia_anterior_km >= 0),
  distancia_nova_km integer not null check (distancia_nova_km >= 0),
  acao text not null check (acao in ('declaracao','confirmacao','correcao')),
  realizado_por uuid not null,
  realizado_em timestamptz not null default now(),
  justificativa text
);
alter table public.ro_folga_distancia_auditoria enable row level security;
revoke all on public.ro_folga_distancia_auditoria from anon,authenticated;

alter table public.ro_passagem_solicitacoes
  add column if not exists folga_alocacao_id uuid references public.ro_folga_alocacoes(id),
  add column if not exists folga_distancia_km integer check (folga_distancia_km >= 0),
  add column if not exists folga_regime_faixa text,
  add column if not exists folga_intervalo_dias integer check (folga_intervalo_dias in (7,14,45,90));

-- Funcao pura e privada: sem leitura de dados e sem SECURITY DEFINER.
-- Nao conceder EXECUTE a clientes; o servidor devera chama-la na futura RPC.
create schema if not exists ro_private;
revoke all on schema ro_private from public,anon,authenticated;
create or replace function ro_private.regime_folga_km(p_km integer)
returns table(faixa text, intervalo_dias integer, transporte text)
language sql immutable
set search_path = ''
as $$
  select
    case when p_km <= 200 then 'ate_200'
         when p_km <= 600 then '201_600'
         when p_km <= 800 then '601_800'
         when p_km <= 1500 then '801_1500'
         else 'acima_1500' end,
    case when p_km <= 200 then 7
         when p_km <= 600 then 14
         when p_km <= 800 then 45
         else 90 end,
    case when p_km <= 600 then 'onibus'
         when p_km <= 1500 then 'onibus_ou_aviao'
         else 'aviao' end
  where p_km is not null and p_km >= 0;
$$;
revoke all on function ro_private.regime_folga_km(integer) from public,anon,authenticated;


-- NAO INCLUIDOS NESTA ETAPA:
-- 1. RPC autorizada de declaracao/confirmacao/correcao e identificacao de episodio.
-- 2. RPC de consulta por funcionario e CC com validacao de acesso.
-- 3. Adaptacao da RPC de criacao e triggers; nao alterar cadeia de aprovacao.
-- 4. Backfill e estrategia de dados historicos.
-- 5. Testes de permissao e rollback validado.
-- OBS: a FK funcionarios(id) deve ser confirmada contra o identificador real
-- empregado em ro_passagem_solicitacoes.funcionario_id antes de aplicar.



-- ===== ORIGEM: docs/sql/folga-campo-08-contexto-privado-transacional-RASCUNHO.sql =====
-- RASCUNHO NAO EXECUTAR EM PRODUCAO
-- Preparacao transacional de contexto de Folga de Campo.
-- Complementa 01-07; NAO substitui isoladamente triggers existentes.
-- A tabela fica em schema privado, sem acesso via Data API.
create schema if not exists ro_private;

create table if not exists ro_private.folga_criacao_contexto (
  solicitacao_id uuid primary key,
  funcionario_id uuid not null references public.funcionarios(id),
  obra_id uuid not null references public.obras(id),
  alocacao_id uuid not null references public.ro_folga_alocacoes(id),
  distancia_km integer not null check (distancia_km >= 0),
  regime_faixa text not null,
  intervalo_dias integer not null check (intervalo_dias in (7,14,45,90)),
  criado_por uuid not null,
  criado_em timestamptz not null default now()
);

alter table ro_private.folga_criacao_contexto enable row level security;
revoke all on ro_private.folga_criacao_contexto from public, anon, authenticated;
revoke all on schema ro_private from anon, authenticated;

-- Padrao para uso no corpo da RPC SECURITY DEFINER:
-- 1. exigir auth.uid() e validar motivo='folga_campo', funcionario_id,
--    obra_id, id uuid, distancia/confirmacao, permissoes e aprovador.
-- 2. obter lock por funcionario, respeitando a ordem ja usada pelo trigger.
-- 3. chamar ro_private.preparar_episodio_folga; grava episodio e auditoria.
-- 4. inserir contexto nesta tabela COM id da solicitacao e auth.uid().
-- 5. chamar public.ro_criar_solicitacao_com_aprovador com o MESMO id.
-- 6. exigir retorno do MESMO id; apagar contexto antes de retornar.
-- Tudo ocorre numa unica transacao PostgreSQL da RPC. Excecao reverte tudo.
--
-- Padrao para o BEFORE INSERT trigger coordenado:
-- SELECT * FROM ro_private.folga_criacao_contexto
-- WHERE solicitacao_id=NEW.id AND funcionario_id=NEW.funcionario_id
-- AND obra_id=NEW.obra_id AND criado_por=auth.uid();
-- Se encontrou, aplicar snapshot ANTES da insercao e calcular ciclo novo.
-- Se nao encontrou, manter caminho legado sem exigir km.
-- Nunca usar set_config/current_setting como prova de autorizacao.
--
-- IMPORTANTE: um SECURITY DEFINER sem search_path seguro e autorizacao
-- explicita seria vulneravel; nao publicar sem auditoria de grants.
-- O wrapper e o trigger precisam ser ativados na MESMA entrega.
-- A tabela so pode ser gravada por codigo privilegiado e validado.
--
-- PENDENCIAS BLOQUEANTES:
-- * Validar se o id recebido no JSON e realmente preservado em toda a cadeia.
-- * Validar se os gatilhos de UPDATE da aprovacao nao recalculam snapshot.
-- * Conferir existencia da estrutura 01 antes de executar este SQL.
-- * Testar rollback, concorrencia, grants e compatibilidade no ambiente isolado.
-- * Backup e autorizacao explicita antes de qualquer DDL em producao.



-- ===== ORIGEM: docs/sql/folga-campo-04-episodio-transacional-RASCUNHO.sql =====
-- RASCUNHO SQL - NAO EXECUTAR NO BANCO DE PRODUCAO
-- Dependencia: folga-campo-01-estruturas-RASCUNHO.sql
-- Funcao interna para ser chamada NA MESMA TRANSACAO da RPC de criacao.
-- Nao chamar isoladamente: sua execucao isolada mudaria o historico interno
-- sem criar a solicitacao. Nenhuma tabela do sistema oficial de alocacao e escrita.
create or replace function ro_private.preparar_episodio_folga(
  p_funcionario_id uuid,
  p_obra_id uuid,
  p_distancia_declarada_km integer,
  p_confirma_retorno boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_novo_id uuid;
  v_km integer;
  v_faixa text;
  v_intervalo integer;
  v_transporte text;
  v_acao text;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if p_funcionario_id is null or p_obra_id is null then
    raise exception 'FUNCIONARIO_CC_OBRIGATORIOS';
  end if;
  -- A RPC chamadora deve confirmar autorizacao para criar em nome do funcionario.
  -- Este lock deve ser compartilhado com a validacao de ciclo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_funcionario_id::text, 904)
  );
  select * into v_atual
  from public.ro_folga_alocacoes
  where funcionario_id=p_funcionario_id and encerrada_em is null
  for update;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    if p_distancia_declarada_km is not null
       and p_distancia_declarada_km <> v_atual.distancia_km then
      raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
    end if;
    v_km:=v_atual.distancia_km;
    v_novo_id:=v_atual.id;
    v_acao:=null;
  else
    select * into v_anterior
    from public.ro_folga_alocacoes
    where funcionario_id=p_funcionario_id and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;

    if v_anterior.id is not null then
      if p_confirma_retorno is distinct from true then
        raise exception 'CONFIRMACAO_RETORNO_OBRIGATORIA';
      end if;
      if p_distancia_declarada_km is not null
         and p_distancia_declarada_km <> v_anterior.distancia_km then
        raise exception 'CORRECAO_SOMENTE_POR_RPC_AUTORIZADA';
      end if;
      v_km:=v_anterior.distancia_km;
      v_acao:='confirmacao';
    else
      if p_distancia_declarada_km is null or p_distancia_declarada_km < 0 then
        raise exception 'DISTANCIA_OBRIGATORIA_OU_INVALIDA';
      end if;
      v_km:=p_distancia_declarada_km;
      v_acao:='declaracao';
    end if;

    if v_atual.id is not null then
      update public.ro_folga_alocacoes
      set encerrada_em=pg_catalog.now()
      where id=v_atual.id;
    end if;
    insert into public.ro_folga_alocacoes(
      funcionario_id,obra_id,distancia_km,confirmada_em,confirmada_por,origem_alocacao_id
    ) values (
      p_funcionario_id,p_obra_id,v_km,pg_catalog.now(),auth.uid(),v_anterior.id
    ) returning id into v_novo_id;
    insert into public.ro_folga_distancia_auditoria(
      alocacao_id,distancia_anterior_km,distancia_nova_km,
      acao,realizado_por
    ) values (
      v_novo_id,v_anterior.distancia_km,v_km,v_acao,auth.uid()
    );
  end if;

  select faixa,intervalo_dias,transporte
  into v_faixa,v_intervalo,v_transporte
  from ro_private.regime_folga_km(v_km);

  return pg_catalog.jsonb_build_object(
    'alocacao_id',v_novo_id,'obra_id',p_obra_id,
    'distancia_km',v_km,'regime_faixa',v_faixa,
    'intervalo_dias',v_intervalo,'transporte',v_transporte
  );
end;
$$;
revoke all on function ro_private.preparar_episodio_folga(uuid,uuid,integer,boolean)
  from public,anon,authenticated;

-- INTEGRACAO AINDA NAO PRONTA:
-- A RPC publica de criacao deve executar preparar_episodio_folga e a
-- ro_criar_solicitacao_com_aprovador na MESMA transacao, apos validar permissao.
-- O trigger ro_validar_ciclo_folga_campo precisa ser atualizado para calcular
-- pela distancia do episodio e pela ultima data_ida aprovada+finalizada.
-- O snapshot devera ser escrito na solicitacao de forma protegida.
-- Nao conceder acesso a esta funcao privada ate completar e testar o fluxo.



-- ===== ORIGEM: docs/sql/folga-campo-03-correcao-RASCUNHO.sql =====
-- RASCUNHO: NAO EXECUTAR EM PRODUCAO.
-- Depende de folga-campo-01-estruturas-RASCUNHO.sql.
-- Revisar grants, identificacao de usuario ativo, trigger de protecao de snapshot,
-- e autorizacao de escrita antes de disponibilizar qualquer RPC.

-- Funcao de autorizacao interna; nao conceder EXECUTE a anon/authenticated.
create or replace function ro_private.pode_corrigir_distancia_folga(p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select p_user is not null and (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = p_user and ur.role::text in ('coordenador','gerente')
    )
    or public.ro_is_operador_ativo(p_user)
  );
$$;
revoke all on function ro_private.pode_corrigir_distancia_folga(uuid) from public,anon,authenticated;

-- Correcao atomica apenas do episodio vigente.
-- SECURITY DEFINER exige auditoria e verificacao de permissoes; manter em schema privado.
create or replace function ro_private.corrigir_distancia_folga(
  p_alocacao_id uuid,
  p_nova_distancia_km integer,
  p_justificativa text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_user uuid := auth.uid();
  v_funcionario_id uuid;
begin
  if v_user is null or not ro_private.pode_corrigir_distancia_folga(v_user) then
    raise exception 'CORRECAO_QUILOMETRAGEM_NAO_AUTORIZADA';
  end if;
  if p_nova_distancia_km is null or p_nova_distancia_km < 0 then
    raise exception 'DISTANCIA_INVALIDA';
  end if;
  if length(btrim(coalesce(p_justificativa,''))) < 10 then
    raise exception 'JUSTIFICATIVA_CORRECAO_OBRIGATORIA';
  end if;
  -- Compartilha o advisory lock da criacao para serializar correcao e
  -- transferencia de CC do mesmo funcionario.
  select funcionario_id into v_funcionario_id
  from public.ro_folga_alocacoes where id=p_alocacao_id;
  if v_funcionario_id is null then raise exception 'ALOCACAO_ATIVA_NAO_ENCONTRADA'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_funcionario_id::text,904)
  );
  select * into v_atual
    from public.ro_folga_alocacoes
    where id = p_alocacao_id and encerrada_em is null
    for update;
  if not found then raise exception 'ALOCACAO_ATIVA_NAO_ENCONTRADA'; end if;
  if v_atual.distancia_km = p_nova_distancia_km then
    raise exception 'DISTANCIA_SEM_ALTERACAO';
  end if;

  update public.ro_folga_alocacoes
     set distancia_km = p_nova_distancia_km,
         confirmada_por = v_user,
         confirmada_em = now()
   where id = p_alocacao_id;

  insert into public.ro_folga_distancia_auditoria(
    alocacao_id, distancia_anterior_km, distancia_nova_km,
    acao, realizado_por, justificativa
  ) values (
    p_alocacao_id, v_atual.distancia_km, p_nova_distancia_km,
    'correcao', v_user, btrim(p_justificativa)
  );

  -- Nunca atualizar snapshots em ro_passagem_solicitacoes.
  return jsonb_build_object(
    'alocacao_id',p_alocacao_id,
    'distancia_anterior_km',v_atual.distancia_km,
    'distancia_nova_km',p_nova_distancia_km
  );
end;
$$;
revoke all on function ro_private.corrigir_distancia_folga(uuid,integer,text) from public,anon,authenticated;

-- PROXIMOS PASSOS ANTES DE USAR:
-- 1. Expor somente uma RPC publica de entrada, com auth.uid() e grants explicitos.
-- 2. Validar status de usuario ativo para coordenador/gerente.
-- 3. Integrar criacao atomica de episodio com ro_criar_solicitacao_com_aprovador
--    sem reescrever cadeia de aprovacao; garantir lock por funcionario.
-- 4. Proteger snapshots de alteracao direta e testar permissao com JWT real.
-- 5. Testar falha transacional e concorrencia. Nao executar este arquivo isoladamente.



-- ===== ORIGEM: docs/sql/folga-campo-12-consulta-contexto-RASCUNHO.sql =====
-- RASCUNHO 12 - CONSULTA SEGURA DE CONTEXTO DE FOLGA
-- NAO EXECUTAR EM PRODUCAO. Requer estruturas do arquivo 01.
-- O acesso precisa ser equivalente ao acesso a criacao de solicitacao.
-- IMPORTANTE: validar politicas de acesso por funcionario antes de conceder EXECUTE.
create or replace function public.ro_consultar_contexto_distancia_folga(
  p_funcionario_id uuid,
  p_obra_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_atual public.ro_folga_alocacoes%rowtype;
  v_anterior public.ro_folga_alocacoes%rowtype;
  v_km integer;
  v_estado text;
  v_ultima date;
  v_futura uuid;
begin
  if auth.uid() is null then raise exception 'AUTENTICACAO_OBRIGATORIA'; end if;
  if p_funcionario_id is null or p_obra_id is null then
    raise exception 'FUNCIONARIO_CC_OBRIGATORIOS';
  end if;
  -- Mesmos filtros canonicos de funcionario e CC atualmente aplicados
  -- pelo catalogo e pelo trigger ro_validar_solicitacao_visibilidade.
  -- A helper de funcionarios e SECURITY DEFINER: chamada interna somente.
  if public.ro_funcionario_disponivel_para_usuario(auth.uid(),p_funcionario_id) is distinct from true then
    raise exception 'FUNCIONARIO_INDISPONIVEL';
  end if;
  if not exists (
    select 1 from public.ro_catalogo_centros_custo() c
    where c.id=p_obra_id
  ) then
    raise exception 'CENTRO_CUSTO_INDISPONIVEL';
  end if;
  select * into v_atual from public.ro_folga_alocacoes
  where funcionario_id=p_funcionario_id and encerrada_em is null
  order by iniciada_em desc limit 1;

  if v_atual.id is not null and v_atual.obra_id=p_obra_id then
    v_estado:='reutilizar';v_km:=v_atual.distancia_km;
  else
    select * into v_anterior from public.ro_folga_alocacoes
    where funcionario_id=p_funcionario_id and obra_id=p_obra_id
    order by iniciada_em desc,id desc limit 1;
    if v_anterior.id is not null then
      v_estado:='confirmar';v_km:=v_anterior.distancia_km;
    else
      v_estado:='informar';v_km:=null;
    end if;
  end if;

  select s.data_ida into v_ultima
  from public.ro_passagem_solicitacoes s
  where s.funcionario_id=p_funcionario_id and s.motivo='folga_campo'
    and s.status='finalizada'
    and s.aprovacao_status in ('aprovada','dispensada')
    and s.data_ida <= (pg_catalog.now() at time zone 'America/Sao_Paulo')::date
  order by s.data_ida desc,s.id desc limit 1;

  v_futura:=public.ro_funcionario_possui_folga_futura_ativa(p_funcionario_id,null);
  return pg_catalog.jsonb_build_object(
    'funcionario_id',p_funcionario_id,'obra_id',p_obra_id,
    'distancia_km',v_km,'retorno_ao_cc',v_estado='confirmar',
    'estado',v_estado,'ultima_folga_data_ida',v_ultima,
    'proxima_folga_prevista',case when v_km is not null and v_ultima is not null
      then v_ultima+(select intervalo_dias from ro_private.regime_folga_km(v_km))
      else null end,
    'solicitacao_futura_existente_id',v_futura
  );
end;
$$;
revoke all on function public.ro_consultar_contexto_distancia_folga(uuid,uuid)
  from public,anon,authenticated;

-- A autorizacao agora reflete os catalogos atuais. Ainda nao conceder EXECUTE:
-- 1. exercitar casos negativos (anon, CC restrito, funcionario indisponivel);
-- 2. validar como funcionarios com vinculo privado devem operar;
-- 3. revisar exposicao de historico e consulta por perfis no teste integrado;
-- 4. garantir que grants nao exponham tabelas auxiliares diretamente.


commit;
